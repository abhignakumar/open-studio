import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreGraphics
import ApplicationServices

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
            fputs("Usage: \(args[0]) --displayId <id> --outputPath <dir_path>\n", stderr)
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
        let outputDirURL = URL(fileURLWithPath: expandedPath)
        
        // Output Files Mapping
        let displayURL = outputDirURL.appendingPathComponent("display.mp4")
        let clicksURL = outputDirURL.appendingPathComponent("mouse-clicks.json")
        let movesURL = outputDirURL.appendingPathComponent("mouse-moves.json")
        let metadataURL = outputDirURL.appendingPathComponent("metadata.json")
        
        // Setup output directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: outputDirURL.path) {
            do {
                try FileManager.default.createDirectory(at: outputDirURL, withIntermediateDirectories: true)
            } catch {
                fputs("Error creating directory for output path: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        
        // Validation: Verify if files already exist to prevent destructive overwriting
        let fm = FileManager.default
        if fm.fileExists(atPath: displayURL.path) || fm.fileExists(atPath: clicksURL.path) || fm.fileExists(atPath: movesURL.path) || fm.fileExists(atPath: metadataURL.path) {
            fputs("Error: One or more target output files already exist in '\(outputDirURL.path)'.\n", stderr)
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
        
        // Initialize Recorder
        let recorder = try Recorder(display: display, outputDirURL: outputDirURL)
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
            fputs("Recording and mouse events saved successfully to: \(outputDirURL.path)\n", stdout)
        } catch {
            fputs("Error finalizing recording: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}

// MARK: - Recorder Engine
@available(macOS 14.0, *)
class Recorder: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    let display: SCDisplay
    let outputDirURL: URL
    
    private let displayURL: URL
    private let metadataURL: URL
    private let mouseTracker: MouseTracker
    
    private var stream: SCStream?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    
    private var isRecording = false
    private var hasWrittenFirstFrame = false
    private var hasPrintedError = false // Prevents stderr flooding at 60 FPS
    
    // Process stream buffers on a dedicated thread to ensure zero frame-dropping and memory safety
    private let queue = DispatchQueue(label: "com.screenrecorder.queue", qos: .userInteractive)
    
    init(display: SCDisplay, outputDirURL: URL) throws {
        self.display = display
        self.outputDirURL = outputDirURL
        
        self.displayURL = outputDirURL.appendingPathComponent("display.mp4")
        self.metadataURL = outputDirURL.appendingPathComponent("metadata.json")
        
        let movesURL = outputDirURL.appendingPathComponent("mouse-moves.json")
        let clicksURL = outputDirURL.appendingPathComponent("mouse-clicks.json")
        
        self.mouseTracker = try MouseTracker(movesURL: movesURL, clicksURL: clicksURL)
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
        let writer = try AVAssetWriter(outputURL: displayURL, fileType: .mp4)
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
        
        // Start Mouse Tracker asynchronously (drops events until `hasWrittenFirstFrame` precisely kicks in)
        try await mouseTracker.start()
        
        try await newStream.startCapture()
        
        // Safely mutate `isRecording` on the dedicated queue to prevent TSAN races
        queue.sync { self.isRecording = true }
    }
    
    func stop() async throws {
        // Immediately halt gathering inputs to cleanly tie-off arrays with the stream's close timestamp
        mouseTracker.isCapturing = false
        
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
                    writer.finishWriting { [weak self] in
                        if let error = self?.assetWriter?.error {
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
        
        await mouseTracker.stop()
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
                
                // Align the metadata initialization uniquely on the precise hardware timestamp of the absolute first frame
                if !hasWrittenFirstFrame {
                    hasWrittenFirstFrame = true

                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let baseHostTimeSeconds = pts.seconds
                    let baseUnixTimeMs = Date().timeIntervalSince1970 * 1000.0
                    
                    mouseTracker.setBaseTimes(hostTimeSeconds: baseHostTimeSeconds, unixTimeMs: baseUnixTimeMs)

                    mouseTracker.isCapturing = true // Pinpoint precisely synced mouse collection origin
                    
                    let metadataURL = self.metadataURL
                    
                    DispatchQueue.global(qos: .background).async {
                        let json = "{\n  \"unixTimeMs\": \(baseUnixTimeMs)\n}\n"
                        do {
                            try json.write(to: metadataURL, atomically: true, encoding: .utf8)
                        } catch {
                            fputs("Error writing metadata: \(error.localizedDescription)\n", stderr)
                        }
                    }
                }
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

// MARK: - Global Mouse Tracking Subsystem
@available(macOS 14.0, *)
final class MouseTracker: @unchecked Sendable {
    let movesWriter: JSONStreamWriter
    let clicksWriter: JSONStreamWriter

    private var baseHostTimeSeconds: Double = 0
    private var baseUnixTimeMs: Double = 0

    private var runLoop: CFRunLoop?
    private var tapPort: CFMachPort?
    private var trackerThread: Thread?
    
    private let capturingLock = NSLock()
    private var _isCapturing = false
    
    /// Thread-safe switch to definitively dictate alignment timing of inputs mapped against the video sequence
    var isCapturing: Bool {
        get {
            capturingLock.lock()
            defer { capturingLock.unlock() }
            return _isCapturing
        }
        set {
            capturingLock.lock()
            _isCapturing = newValue
            capturingLock.unlock()
        }
    }
    
    init(movesURL: URL, clicksURL: URL) throws {
        self.movesWriter = try JSONStreamWriter(url: movesURL, label: "com.recorder.movesWriter")
        self.clicksWriter = try JSONStreamWriter(url: clicksURL, label: "com.recorder.clicksWriter")
    }

    func setBaseTimes(hostTimeSeconds: Double, unixTimeMs: Double) {
        capturingLock.lock()
        defer { capturingLock.unlock() }
        self.baseHostTimeSeconds = hostTimeSeconds
        self.baseUnixTimeMs = unixTimeMs
    }
    
    func start() async throws {
        // Swift concurrency safe bridge
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let thread = Thread { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "MouseTracker", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tracker deallocated before thread initialization"]))
                    return
                }
                
                let mask: CGEventMask =
                    (UInt64(1) << CGEventType.mouseMoved.rawValue) |
                    (UInt64(1) << CGEventType.leftMouseDragged.rawValue) |
                    (UInt64(1) << CGEventType.rightMouseDragged.rawValue) |
                    (UInt64(1) << CGEventType.otherMouseDragged.rawValue) |
                    (UInt64(1) << CGEventType.leftMouseDown.rawValue) |
                    (UInt64(1) << CGEventType.leftMouseUp.rawValue) |
                    (UInt64(1) << CGEventType.rightMouseDown.rawValue) |
                    (UInt64(1) << CGEventType.rightMouseUp.rawValue) |
                    (UInt64(1) << CGEventType.otherMouseDown.rawValue) |
                    (UInt64(1) << CGEventType.otherMouseUp.rawValue)
                
                let userInfo = Unmanaged.passUnretained(self).toOpaque()
                
                let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    // Null return for '.listenOnly' eliminates retain count loops entirely and flawlessly preserves memory
                    guard let refcon = refcon else { return nil }
                    let tracker = Unmanaged<MouseTracker>.fromOpaque(refcon).takeUnretainedValue()
                    tracker.handle(event: event, type: type)
                    return nil
                }
                
                guard let tap = CGEvent.tapCreate(
                    tap: .cgSessionEventTap,
                    place: .headInsertEventTap,
                    options: .listenOnly,
                    eventsOfInterest: mask,
                    callback: callback,
                    userInfo: userInfo
                ) else {
                    continuation.resume(throwing: NSError(domain: "MouseTracker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create hardware event tap. Please ensure your Terminal (or executable) is granted 'Accessibility' permissions in System Settings -> Privacy & Security."]))
                    return
                }
                
                self.tapPort = tap
                let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                let currentRunLoop = CFRunLoopGetCurrent()
                self.runLoop = currentRunLoop
                
                CFRunLoopAddSource(currentRunLoop, runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                
                continuation.resume()
                CFRunLoopRun()
            }
            
            self.trackerThread = thread
            thread.start()
        }
    }
    
    func stop() async {
        // Completely invalidate kernel resources to prevent any port/runloop leakage
        if let tap = tapPort {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let rl = runLoop {
            CFRunLoopStop(rl)
        }
        
        await movesWriter.finish()
        await clicksWriter.finish()
    }
    
    private func handle(event: CGEvent, type: CGEventType) {
        guard isCapturing else { return }
        
        let loc = event.location
        
        // event.timestamp is Mach absolute time in nanoseconds
        let eventHostSeconds = Double(event.timestamp) / 1_000_000_000.0
        let processTimeMs = (eventHostSeconds - baseHostTimeSeconds) * 1000.0
        let unixTimeMs = baseUnixTimeMs + processTimeMs
        
        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let json = "{\"x\":\(loc.x),\"y\":\(loc.y),\"unixTimeMs\":\(unixTimeMs),\"processTimeMs\":\(processTimeMs)}"
            movesWriter.append(json)
            
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            let button: String
            let action: String
            
            switch type {
            case .leftMouseDown: button = "left"; action = "mouseDown"
            case .leftMouseUp: button = "left"; action = "mouseUp"
            case .rightMouseDown: button = "right"; action = "mouseDown"
            case .rightMouseUp: button = "right"; action = "mouseUp"
            case .otherMouseDown: button = "other"; action = "mouseDown"
            case .otherMouseUp: button = "other"; action = "mouseUp"
            default: return
            }
            
            let json = "{\"x\":\(loc.x),\"y\":\(loc.y),\"type\":\"\(action)\",\"button\":\"\(button)\",\"unixTimeMs\":\(unixTimeMs),\"processTimeMs\":\(processTimeMs)}"
            clicksWriter.append(json)
            
        default:
            break
        }
    }
}

// MARK: - Asynchronous Stream Writer
/// Efficiently buffers and formats continuous JSON objects natively avoiding exhaustive memory allocation
@available(macOS 14.0, *)
final class JSONStreamWriter: @unchecked Sendable {
    private let fileHandle: FileHandle
    private var isFirst = true
    private let queue: DispatchQueue
    
    init(url: URL, label: String) throws {
        FileManager.default.createFile(atPath: url.path, contents: Data("[\n".utf8), attributes: nil)
        self.fileHandle = try FileHandle(forWritingTo: url)
        try self.fileHandle.seekToEnd()
        self.queue = DispatchQueue(label: label, qos: .userInitiated)
    }
    
    func append(_ jsonString: String) {
        queue.async {
            let prefix = self.isFirst ? "  " : ",\n  "
            self.isFirst = false
            let entry = prefix + jsonString
            if let data = entry.data(using: .utf8) {
                try? self.fileHandle.write(contentsOf: data)
            }
        }
    }
    
    func finish() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                if let endData = "\n]\n".data(using: .utf8) {
                    try? self.fileHandle.write(contentsOf: endData)
                }
                try? self.fileHandle.close()
                continuation.resume()
            }
        }
    }
}