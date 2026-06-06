# API Plan

Last updated: May 28, 2026

## 1. Summary

Open Studio V1 uses three API layers:

- **Electron Preload API:** renderer-facing workflow API for permissions, displays, recording capture, project loading/saving, editor state, and export.
- **Electron Main Services:** trusted orchestration layer for filesystem access, project packages, window lifecycle, Swift CLI lifecycle, validation, output persistence, and event forwarding.
- **Swift Capture CLI Contract:** native-only executable boundary for selected-display screen capture, global mouse movement capture, and mouse click capture.

Recording capture runs in the Swift CLI spawned by Electron main. Final export rendering runs in renderer-side browser pipelines. Electron main writes all files to disk. The Swift CLI does not speak JSON-RPC and does not own project package layout or export rendering.

## 2. Process Boundary Principles

- The renderer talks only to the preload API.
- The renderer never receives Node.js, filesystem, process, or generic IPC access.
- Electron main owns project package layout, schema migrations, temporary workspaces, and final file writes.
- Electron main owns Swift CLI spawning, graceful shutdown, exit-code handling, stderr capture, and capture artifact validation.
- The Swift CLI owns selected-display screen capture, global mouse movement capture, and mouse click capture.
- Swift receives absolute output paths from Electron main but does not decide package layout.
- Preview and export rendering remain in renderer-side browser code and consume the same persisted project model.
- Export output defaults to the user's Desktop and is written by Electron main.

## 3. Swift Capture CLI Contract

Electron main starts the Swift CLI when a recording session starts.

```text
open-studio-capture \
  --recording-id <recordingId> \
  --display-id <displayId> \
  --display-origin-x <px> \
  --display-origin-y <px> \
  --display-width <px> \
  --display-height <px> \
  --display-scale-factor <scale> \
  --recording-started-at <isoTimestamp> \
  --video-output <absolute path to raw-recording.mp4> \
  --cursor-output <absolute path to cursor-movements.json> \
  --click-output <absolute path to mouse-clicks.json>
```

CLI behavior:

- Captures the selected display as a cursor-free H.264 MP4 at 60 FPS.
- Writes the raw recording to the `--video-output` MP4 file.
- Writes cursor samples to the `--cursor-output` JSON file.
- Writes mouse click events to the `--click-output` JSON file.
- Aligns timestamps to `--recording-started-at`.
- Converts global coordinates into selected display pixel coordinates.
- Writes diagnostics to stderr.
- Leaves stdout unused for V1.
- Exits `0` after clean finalization.
- Exits nonzero on failure.

Main treats the CLI as successful only when the process exits `0`, the MP4 exists and validates, and both JSON files exist and validate.

## 4. Electron Preload API

The preload layer exposes explicit app commands under `window.openStudio`.

```ts
type OpenStudioApi = {
  permissions: PermissionsApi;
  displays: DisplaysApi;
  recording: RecordingApi;
  projects: ProjectsApi;
  export: ExportApi;
  app: AppApi;
};
```

### 4.1 Permissions API

```ts
type PermissionsApi = {
  getScreenRecordingStatus(): Promise<PermissionStatus>;
  openScreenRecordingSettings(): Promise<void>;
  onChanged(handler: (status: PermissionStatus) => void): Unsubscribe;
};
```

```ts
type PermissionStatus = 'granted' | 'denied' | 'notDetermined' | 'restricted';
```

### 4.2 Displays API

```ts
type DisplaysApi = {
  list(): Promise<AppDisplay[]>;
};
```

```ts
type AppDisplay = {
  id: string;
  name: string;
  widthPx: number;
  heightPx: number;
  scaleFactor: number;
  originX: number;
  originY: number;
  isPrimary: boolean;
};
```

### 4.3 Recording API

The recording API coordinates a main-owned recording session. The renderer starts and stops recording through preload APIs, while Electron main spawns the Swift capture CLI, monitors progress, validates artifacts, and finalizes the project package.

```ts
type RecordingApi = {
  start(displayId: string): Promise<RecordingSession>;
  stop(recordingId: string): Promise<ProjectOpenResult>;
  cancel(recordingId: string): Promise<void>;
  onStateChanged(handler: (event: RecordingEvent) => void): Unsubscribe;
};
```

```ts
type RecordingSession = {
  recordingId: string;
  displayId: string;
  startedAt: string;
};
```

```ts
type RecordingEvent =
  | {
      type: 'recording.started';
      recordingId: string;
      startedAt: string;
    }
  | {
      type: 'recording.progress';
      recordingId: string;
      elapsedMs: number;
      capturedBytes?: number;
    }
  | {
      type: 'recording.completed';
      recordingId: string;
      projectId: string;
    }
  | {
      type: 'recording.failed';
      recordingId: string;
      error: AppError;
    };
```

### 4.4 Projects API

```ts
type ProjectsApi = {
  open(path: string): Promise<ProjectOpenResult>;
  save(project: OpenStudioProject): Promise<ProjectSaveResult>;
  updateTimeline(projectId: string, timeline: TimelineModel): Promise<ProjectSaveResult>;
  updateCursor(projectId: string, cursor: CursorRenderSettings): Promise<ProjectSaveResult>;
  updateMotion(projectId: string, motion: MotionSettings): Promise<ProjectSaveResult>;
  getAssetUrl(projectId: string, relativePath: string): Promise<string>;
};
```

```ts
type ProjectOpenResult = {
  projectId: string;
  packagePath: string;
  project: OpenStudioProject;
  assetUrls: {
    rawVideo: string;
    poster?: string;
  };
};
```

```ts
type ProjectSaveResult = {
  projectId: string;
  savedAt: string;
};
```

### 4.5 Export API

The export API coordinates renderer-side WebGL/WebCodecs rendering with main-owned output persistence.

```ts
type ExportApi = {
  start(projectId: string, settings: ExportSettings): Promise<ExportSession>;
  appendEncodedChunk(exportId: string, chunk: ArrayBuffer): Promise<void>;
  complete(exportId: string, artifact: ExportArtifact): Promise<ExportCompletedResult>;
  fail(exportId: string, error: AppError): Promise<void>;
  cancel(exportId: string): Promise<void>;
  onProgress(handler: (event: ExportEvent) => void): Unsubscribe;
};
```

```ts
type ExportSession = {
  exportId: string;
  projectId: string;
  startedAt: string;
  outputPath: string;
  settings: ExportSettings;
};
```

```ts
type ExportArtifact =
  | {
      mode: 'chunksComplete';
      codec: 'h264';
      container: 'mp4';
      durationMs: number;
      widthPx: number;
      heightPx: number;
      fps: 60;
    }
  | {
      mode: 'completeFile';
      data: ArrayBuffer;
      codec: 'h264';
      container: 'mp4';
      durationMs: number;
      widthPx: number;
      heightPx: number;
      fps: 60;
    };
```

```ts
type ExportEvent =
  | {
      type: 'export.progress';
      exportId: string;
      progress: number;
      elapsedMs: number;
      estimatedRemainingMs?: number;
    }
  | {
      type: 'export.completed';
      exportId: string;
      outputPath: string;
      completedAt: string;
    }
  | {
      type: 'export.failed';
      exportId: string;
      error: AppError;
    };
```

```ts
type ExportCompletedResult = {
  exportId: string;
  outputPath: string;
  completedAt: string;
};
```

### 4.6 App API

```ts
type AppApi = {
  getVersion(): Promise<string>;
  onError(handler: (error: AppError) => void): Unsubscribe;
};
```

```ts
type Unsubscribe = () => void;
```

## 5. Main Process Services

### 5.1 SwiftCaptureCliService

`SwiftCaptureCliService` owns:

- Resolving the packaged Swift CLI executable path.
- Building CLI arguments from the active recording session.
- Starting and stopping the Swift CLI.
- Capturing stderr diagnostics.
- Detecting crashes and nonzero exits.
- Validating `raw-recording.mp4`, `cursor-movements.json`, and `mouse-clicks.json` after stop.
- Mapping native capture failures into renderer-safe app errors.

### 5.2 ProjectPackageService

`ProjectPackageService` owns:

- Creating `.openstudio` packages.
- Writing `manifest.json`.
- Writing and validating `project.json`.
- Importing raw media and event JSON files.
- Reading cursor movement and mouse click files.
- Managing schema version checks and migrations.
- Producing safe asset URLs for renderer preview and export.

### 5.3 RecordingService

`RecordingService` owns:

- Creating recording IDs.
- Creating temporary recording workspaces.
- Starting the Swift capture CLI.
- Stopping or cancelling Swift capture.
- Validating the Swift capture CLI exit code and output artifacts.
- Finalizing completed recordings into `.openstudio` packages.
- Generating default zoom segments from mouse click events.
- Opening the editor after recording completion.

### 5.4 ExportService

`ExportService` owns:

- Saving the latest project state before export.
- Choosing the Desktop output path.
- Creating export IDs.
- Starting renderer-side export sessions.
- Accepting encoded MP4 chunks or completed MP4 artifacts from the renderer.
- Writing the final exported MP4 to disk.
- Handling export cancellation.
- Updating export history after completion, failure, or cancellation.

`ExportService` must not render frames, call WebGL, call WebCodecs, or run native export.

### 5.5 WindowService

`WindowService` owns:

- Recording picker window lifecycle.
- Compact recording stop-control state.
- Editor window creation.
- Dedicated export renderer surface lifecycle, if export runs outside the visible editor renderer.
- Routing completed recordings into editor windows.

## 6. Recording Flow

1. Renderer calls `recording.start(displayId)`.
2. Main creates a `recordingId`, recording start timestamp, and temporary workspace.
3. Main starts the Swift capture CLI with display metadata plus absolute MP4 and event JSON output paths.
4. Main returns `RecordingSession` to the renderer.
5. Swift captures the selected display as cursor-free H.264 MP4 while recording cursor movement and click events.
6. Renderer calls `recording.stop(recordingId)`.
7. Main gracefully stops the Swift capture CLI and validates its exit code plus MP4 and event JSON files.
8. Main creates the `.openstudio` package.
9. Main writes canonical project JSON and imports media/event artifacts.
10. Main generates default zoom segments from click events.
11. Main opens the editor window.
12. Renderer receives `ProjectOpenResult`.

## 7. Export Flow

1. Renderer calls `export.start(projectId, settings)`.
2. Main saves the latest project state.
3. Main chooses an output path on the user's Desktop.
4. Main creates an `ExportSession` and returns it to the renderer.
5. A dedicated renderer-side export surface loads the project package assets.
6. Renderer demuxes the raw MP4 with MP4Box.js or equivalent.
7. Renderer decodes source frames with WebCodecs `VideoDecoder`.
8. Renderer renders each output frame through the WebGL composition pipeline.
9. Renderer creates `VideoFrame` objects from the export canvas and encodes them with `VideoEncoder`.
10. Renderer muxes encoded chunks into MP4.
11. Renderer sends encoded chunks or a completed MP4 artifact to main.
12. Main writes the exported MP4 to disk.
13. Main updates `exports/export-history.json`.
14. Renderer shows progress, completion, failure, or cancellation state.

## 8. Export Pipeline Requirements

- Preview may use `HTMLVideoElement` and may tolerate dropped frames.
- Export must be deterministic and frame-by-frame.
- Export must not rely on realtime video playback.
- Export should use decoded `VideoFrame` objects directly as GPU-friendly inputs.
- Export should create `VideoFrame` objects directly from the canvas for encoding.
- Export should bound encoder queue size and close frames promptly.
- Export must avoid `canvas.readPixels`, PNG frame dumps, and raw pixel transfer through JavaScript memory.
- Export cancellation must stop demuxing, decoding, rendering, encoding, muxing, and main-process file writes.

## 9. Error Model

Renderer-facing errors use stable app error codes.

```ts
type AppError = {
  code:
    | 'PERMISSION_DENIED'
    | 'DISPLAY_UNAVAILABLE'
    | 'RECORDING_ALREADY_ACTIVE'
    | 'RECORDING_FAILED'
    | 'CAPTURE_FAILED'
    | 'PROJECT_INVALID'
    | 'PROJECT_UNSUPPORTED_VERSION'
    | 'PROJECT_SAVE_FAILED'
    | 'EXPORT_FAILED'
    | 'EXPORT_CANCELLED'
    | 'CLI_UNAVAILABLE'
    | 'OPERATION_CANCELLED';
  message: string;
  recoverable: boolean;
  details?: unknown;
};
```

Swift capture failures, renderer export failures, and filesystem failures should all be mapped into renderer-safe `AppError` objects. User-facing copy belongs in Electron, not Swift.

## 10. Testing Strategy

### 10.1 Swift CLI Lifecycle Tests

Test:

- Argument construction.
- CLI launch and graceful shutdown.
- Nonzero exit handling.
- stderr diagnostic capture.
- Missing raw MP4 or event file handling.
- Invalid raw MP4 handling.
- Invalid event JSON handling.
- Native error mapping.

### 10.2 Preload Tests

Test:

- Method input validation.
- Renderer-safe return shapes.
- Export chunk/artifact transfer validation.
- Subscription cleanup.
- Rejection of unknown or malformed commands.

### 10.3 Project API Tests

Test:

- Package creation.
- Package open/save.
- Schema version rejection.
- Missing asset handling.
- Cursor and click event parsing.
- Generated zoom persistence.
- Importing raw MP4 plus `cursor-movements.json` and `mouse-clicks.json`.

### 10.4 Recording UI Tests

Test:

- Recording picker start/stop state transitions.
- Stop/cancel behavior.
- Progress event reporting.
- Failure mapping when Swift capture fails.

### 10.5 Renderer Export Tests

Test:

- Deterministic frame selection.
- MP4 demux/decode integration with fixtures.
- WebGL render-state parity with preview.
- `VideoEncoder` progress handling.
- Encoder queue backpressure.
- Cancellation.
- Completed output handoff to main.

### 10.6 Workflow Integration Tests

Use fake Swift capture and mocked renderer export for deterministic tests.

Test:

- Permission granted flow.
- Permission denied flow.
- Display listing.
- Recording start and stop.
- Package creation after recording.
- Capture failure.
- Editor open result.
- Export progress.
- Export completion.
- Export failure.
- Export cancellation.
- Export history updates.

### 10.7 Swift Tests

Test:

- CLI argument parsing.
- Screen capture adapter behavior.
- Event capture adapter behavior.
- Timestamp alignment across video, cursor movement, and click events.
- Coordinate mapping.
- Event JSON encoding.
- Graceful stop and flush behavior for MP4 and JSON outputs.
- Nonzero failure exits.

## 11. V1 Assumptions

- Raw recording remains H.264 MP4 at 60 FPS.
- Renderer talks only to preload.
- Electron main owns all project package schema decisions and disk writes.
- Swift owns selected-display screen capture, global mouse movement capture, and mouse click capture.
- Swift capture uses args, file outputs, stderr diagnostics, and exit codes.
- Final export runs in a dedicated renderer-side export surface using browser media APIs.
- Export output defaults to Desktop.
- Export format is H.264 MP4 at 60 FPS.
- The renderer preview and export pipeline consume the same persisted project model.
