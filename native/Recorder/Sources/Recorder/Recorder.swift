import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// MARK: - CLI Entry Point
@available(macOS 14.0, *)
@main
struct RecorderCLI {
    
    static func main() async {
        let args = CommandLine.arguments
        var displayId: UInt32?
        var outputPath: String?
        
        // Manual argument parsing
        var i = 1
        while i < args.count {
            switch args[i] {
            case "--displayId", "-d":
                if i + 1 < args.count, let id = UInt32(args[i + 1]) {
                    displayId = id
                    i += 2
                } else {
                    fputs("Error: Missing or invalid value for --displayId.\n", stderr)
                    exit(1)
                }
            case "--outputPath", "-o":
                if i + 1 < args.count {
                    outputPath = args[i + 1]
                    i += 2
                } else {
                    fputs("Error: Missing value for --outputPath.\n", stderr)
                    exit(1)
                }
            default:
                i += 1
            }
        }
        
        guard let parsedDisplayId = displayId, let parsedOutputPath = outputPath else {
            fputs("Usage: \(args[0]) --displayId <id> --outputPath <path>\n", stderr)
            exit(1)
        }
        
        do {
            try await run(displayId: parsedDisplayId, outputPath: parsedOutputPath)
        } catch {
            // Any unhandled errors bubble up here
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
    
    static func run(displayId: UInt32, outputPath: String) async throws {
        // Expand tilde in path (e.g. ~/Desktop -> /Users/username/Desktop)
        let expandedPath = (outputPath as NSString).expandingTildeInPath
        let outputURL = URL(fileURLWithPath: expandedPath)
        
        // Validation: Verify if file already exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            fputs("Error: Output file already exists at '\(outputURL.path)'.\n", stderr)
            exit(1)
        }
        
        // Fetch Shareable Content
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            fputs("Error fetching shareable content: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        
        if content.displays.isEmpty {
            fputs("Error: No displays found. Ensure Terminal has Screen Recording permissions.\n", stderr)
            exit(1)
        }
        
        // Validation: Verify displayId exists
        guard let display = content.displays.first(where: { $0.displayID == displayId }) else {
            let available = content.displays.map { String($0.displayID) }.joined(separator: ", ")
            fputs("Error: Invalid displayId '\(displayId)'. Available display IDs are: \(available)\n", stderr)
            exit(1)
        }
        
        // Setup output directory if it doesn't exist
        let dirURL = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dirURL.path) {
            do {
                try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            } catch {
                fputs("Error creating directory for output path: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        
        // Initialize Recorder
        let recorder = Recorder(display: display, outputURL: outputURL)
        do {
            try await recorder.start()
            fputs("Recording started. Press [Enter] or send [Ctrl+C] to stop...\n", stdout)
            fflush(stdout)
        } catch {
            fputs("Failed to start recording: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        // Graceful termination handler (stdin enter \n, EOF, & Control+C)
        let stopSignal = AsyncStream<Void> { continuation in
            let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
            sigint.setEventHandler {
                continuation.yield()
            }
            signal(SIGINT, SIG_IGN)
            sigint.resume()
            
            FileHandle.standardInput.readabilityHandler = { handle in
                let data = handle.availableData
                // Detect EOF (empty data) or new line triggers
                if data.isEmpty || data.contains(10) || data.contains(13) {
                    continuation.yield()
                    // Uninstall asynchronously to safely break the infinite EOF spin without deadlocking
                    DispatchQueue.global().async {
                        handle.readabilityHandler = nil
                    }
                }
            }
            
            continuation.onTermination = { _ in
                sigint.cancel()
                DispatchQueue.global().async {
                    FileHandle.standardInput.readabilityHandler = nil
                }
            }
        }
        
        for await _ in stopSignal {
            break
        }
        
        fputs("Stopping recording...\n", stdout)
        fflush(stdout)
        
        do {
            try await recorder.stop()
            fputs("Recording saved successfully to: \(outputURL.path)\n", stdout)
        } catch {
            fputs("Error finalizing recording: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

// MARK: - Recorder Engine
@available(macOS 14.0, *)
class Recorder: NSObject, SCStreamDelegate, SCStreamOutput {
    let display: SCDisplay
    let outputURL: URL
    
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    
    private var isRecording = false
    private var hasWrittenFirstFrame = false
    private var hasPrintedError = false // Prevents stderr flooding at 60 FPS
    
    // Process stream buffers on a dedicated thread to ensure zero frame-dropping and memory safety
    private let queue = DispatchQueue(label: "com.screenrecorder.queue", qos: .userInteractive)
    
    init(display: SCDisplay, outputURL: URL) {
        self.display = display
        self.outputURL = outputURL
    }
    
    func start() async throws {
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        
        // Capture at actual internal retina resolution, strictly forcing EVEN dimensions for hardware encoders
        let rawWidth = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        let rawHeight = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.width = (rawWidth / 2) * 2
        config.height = (rawHeight / 2) * 2
        
        // Strict 60 FPS Cap
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.showsCursor = true
        config.captureResolution = .best // Requires macOS 14.0
        
        // AVAssetWriter Setup (H.264 | 60 FPS)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: 60
            ]
        ]
        
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        
        guard writer.canAdd(input) else {
            throw NSError(domain: "Recorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate AVAssetWriter input."])
        }
        writer.add(input)
        
        self.assetWriter = writer
        self.videoInput = input
        
        // Stream Initialization
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = newStream
        
        try await newStream.startCapture()
        
        // Safely mutate `isRecording` on the dedicated queue to prevent TSAN races
        queue.sync { self.isRecording = true }
    }
    
    func stop() async throws {
        // Evaluate condition and flip flag synchronously to avoid races with the delegate callback
        let wasRecording = queue.sync { () -> Bool in
            let state = self.isRecording
            self.isRecording = false
            return state
        }
        
        guard wasRecording else { return }
        
        if let stream = stream {
            do {
                try await stream.stopCapture()
            } catch {
                fputs("Error stopping stream: \(error.localizedDescription)\n", stderr)
            }
        }
        
        // Guarantee synchronization with the serial buffer queue while finishing AVAssetWriter ops
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [weak self] in
                guard let self = self, let writer = self.assetWriter, let input = self.videoInput else {
                    continuation.resume(returning: ())
                    return
                }
                
                if writer.status == .writing && self.hasWrittenFirstFrame {
                    input.markAsFinished()
                    writer.finishWriting {
                        if let error = writer.error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                } else if writer.status == .failed, let error = writer.error {
                    continuation.resume(throwing: error)
                } else {
                    writer.cancelWriting()
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    // MARK: - SCStreamOutput
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Enforce tight autoreleasepool allocation context to prevent memory bloat during dense 60fps streaming
        autoreleasepool {
            // isRecording is safely read here without a lock since we are executing on the same `queue` where it is mutated
            guard isRecording, type == .screen, sampleBuffer.isValid else { return }
            
            // Extract the metadata frame attachment (ensure generation was completed)
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first,
                  let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRawValue),
                  status == .complete else {
                return
            }
            
            guard let writer = assetWriter, let input = videoInput else { return }

            if writer.status == .unknown {
                // Safely guard against startWriting failures (e.g., sandbox/disk space errors)
                // Returning early allows the next frame to catch the `.failed` status gracefully.
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            }
            
            if writer.status == .writing, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
                hasWrittenFirstFrame = true
            } else if writer.status == .failed {
                if !hasPrintedError {
                    if let error = writer.error {
                        fputs("AssetWriter Error: \(error.localizedDescription)\n", stderr)
                    }
                    hasPrintedError = true
                }
            }
        }
    }
    
    // MARK: - SCStreamDelegate
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("Stream Error: \(error.localizedDescription)\n", stderr)
    }
}