# API Plan

Last updated: May 26, 2026

## 1. Summary

Open Studio V1 uses three API layers:

- **Electron Preload API:** renderer-facing workflow API for permissions, displays, recording, project loading/saving, editor state, and export.
- **Electron Main Services:** trusted orchestration layer for filesystem access, project packages, window lifecycle, helper process management, validation, and event forwarding.
- **Swift JSON-RPC API:** native-only boundary for macOS permissions, display enumeration, recording, event capture, and native export.

Export composition for V1 is orchestrated by Electron main and executed through the Swift helper using the persisted project package data model.

## 2. Process Boundary Principles

- The renderer talks only to the preload API.
- The renderer never receives Node.js, filesystem, process, or generic IPC access.
- Electron main owns project package layout and schema migrations.
- Electron main owns Swift helper lifecycle, JSON-RPC request correlation, timeout handling, cancellation, and event forwarding.
- Swift owns macOS-native APIs, raw recording, cursor and click capture, and native export execution.
- Swift receives absolute paths from Electron main but does not decide package layout.
- Preview rendering remains in the renderer and is separate from the native export backend.

## 3. JSON-RPC Transport

JSON-RPC messages are sent over stdio between Electron main and the Swift helper.

Requests use JSON-RPC 2.0-style request IDs for correlation.

```ts
type JsonRpcRequest<TParams = unknown> = {
  jsonrpc: '2.0';
  id: string;
  method: string;
  params?: TParams;
};
```

Successful responses return a result.

```ts
type JsonRpcSuccess<TResult = unknown> = {
  jsonrpc: '2.0';
  id: string;
  result: TResult;
};
```

Failed responses return a structured error.

```ts
type JsonRpcFailure = {
  jsonrpc: '2.0';
  id: string;
  error: {
    code: string;
    message: string;
    details?: unknown;
  };
};
```

Helper events are JSON-RPC notifications with no request ID.

```ts
type JsonRpcNotification<TParams = unknown> = {
  jsonrpc: '2.0';
  method: string;
  params?: TParams;
};
```

`stdout` is reserved for protocol messages. `stderr` is reserved for logs and diagnostics.

## 4. Swift JSON-RPC Methods

### 4.1 Health

```ts
health.ping() -> {
  ok: true;
  helperVersion: string;
}
```

### 4.2 Permissions

```ts
permissions.getScreenRecordingStatus() -> {
  status: "granted" | "denied" | "notDetermined" | "restricted";
}
```

```ts
permissions.openScreenRecordingSettings() -> {
  opened: boolean;
}
```

### 4.3 Displays

```ts
displays.list() -> {
  displays: NativeDisplay[];
}
```

```ts
type NativeDisplay = {
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

### 4.4 Recording

```ts
recording.start(params: {
  displayId: string;
  outputDirectory: string;
  recordingId: string;
  fps: 60;
  codec: "h264";
  excludeCursor: true;
}) -> {
  recordingId: string;
  startedAt: string;
}
```

```ts
recording.stop(params: {
  recordingId: string;
}) -> {
  recordingId: string;
  completedAt: string;
  rawVideoPath: string;
  cursorMovementsPath: string;
  mouseClicksPath: string;
  durationMs: number;
  widthPx: number;
  heightPx: number;
}
```

```ts
recording.cancel(params: {
  recordingId: string;
}) -> {
  recordingId: string;
  cancelledAt: string;
  recoverableArtifacts?: string[];
}
```

### 4.5 Export

```ts
export.start(params: {
  exportId: string;
  projectPackagePath: string;
  outputPath: string;
  settings: ExportSettings;
}) -> {
  exportId: string;
  startedAt: string;
}
```

```ts
export.cancel(params: {
  exportId: string;
}) -> {
  exportId: string;
  cancelledAt: string;
}
```

## 5. Swift JSON-RPC Events

The Swift helper emits long-running state changes as notifications.

```ts
helper.ready
helper.error
permissions.changed
recording.started
recording.progress
recording.completed
recording.failed
export.progress
export.completed
export.failed
```

Example event payloads:

```ts
type RecordingProgressEvent = {
  recordingId: string;
  elapsedMs: number;
  droppedFrames?: number;
};
```

```ts
type ExportProgressEvent = {
  exportId: string;
  progress: number;
  elapsedMs: number;
  estimatedRemainingMs?: number;
};
```

```ts
type ExportCompletedEvent = {
  exportId: string;
  outputPath: string;
  completedAt: string;
};
```

## 6. Electron Preload API

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

### 6.1 Permissions API

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

### 6.2 Displays API

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
  isPrimary: boolean;
};
```

### 6.3 Recording API

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

### 6.4 Projects API

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

### 6.5 Export API

```ts
type ExportApi = {
  start(projectId: string, settings: ExportSettings): Promise<ExportSession>;
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
};
```

### 6.6 App API

```ts
type AppApi = {
  getVersion(): Promise<string>;
  onError(handler: (error: AppError) => void): Unsubscribe;
};
```

```ts
type Unsubscribe = () => void;
```

## 7. Main Process Services

### 7.1 HelperService

`HelperService` owns:

- Starting and stopping the Swift helper.
- JSON-RPC request correlation.
- Request timeouts.
- Cancellation.
- Helper crash detection.
- Event forwarding.
- Mapping native errors into renderer-safe app errors.

### 7.2 ProjectPackageService

`ProjectPackageService` owns:

- Creating `.openstudio` packages.
- Writing `manifest.json`.
- Writing and validating `project.json`.
- Importing raw media and event JSON files.
- Reading cursor movement and mouse click files.
- Managing schema version checks and migrations.
- Producing safe asset URLs for renderer preview.

### 7.3 RecordingService

`RecordingService` owns:

- Creating recording IDs.
- Creating temporary recording workspaces.
- Starting native recording through `HelperService`.
- Stopping or cancelling native recording.
- Finalizing completed recordings into `.openstudio` packages.
- Generating default zoom segments from mouse click events.
- Opening the editor after recording completion.

### 7.4 ExportService

`ExportService` owns:

- Saving the latest project state before export.
- Choosing the Desktop output path.
- Starting native export through `HelperService`.
- Forwarding export progress to the renderer.
- Handling export cancellation.
- Updating export history after completion, failure, or cancellation.

### 7.5 WindowService

`WindowService` owns:

- Recording picker window lifecycle.
- Compact recording stop-control state.
- Editor window creation.
- Routing completed recordings into editor windows.

## 8. Recording Flow

1. Renderer calls `recording.start(displayId)`.
2. Main creates a `recordingId` and temporary workspace.
3. Main calls Swift `recording.start`.
4. Swift starts display capture and event capture.
5. Renderer calls `recording.stop(recordingId)`.
6. Main calls Swift `recording.stop`.
7. Swift finalizes the raw MP4 and event JSON files.
8. Main creates the `.openstudio` package.
9. Main writes canonical project JSON and imports media/event artifacts.
10. Main generates default zoom segments from click events.
11. Main opens the editor window.
12. Renderer receives `ProjectOpenResult`.

## 9. Export Flow

1. Renderer calls `export.start(projectId, settings)`.
2. Main saves the latest project state.
3. Main chooses an output path on the user's Desktop.
4. Main calls Swift `export.start`.
5. Swift reads the project package and renders the final H.264 MP4.
6. Swift emits `export.progress` events.
7. Swift emits `export.completed` or `export.failed`.
8. Main updates `exports/export-history.json`.
9. Renderer shows progress, completion, failure, or cancellation state.

## 10. Error Model

Renderer-facing errors use stable app error codes.

```ts
type AppError = {
  code:
    | 'PERMISSION_DENIED'
    | 'DISPLAY_UNAVAILABLE'
    | 'RECORDING_ALREADY_ACTIVE'
    | 'RECORDING_FAILED'
    | 'PROJECT_INVALID'
    | 'PROJECT_UNSUPPORTED_VERSION'
    | 'PROJECT_SAVE_FAILED'
    | 'EXPORT_FAILED'
    | 'HELPER_UNAVAILABLE'
    | 'OPERATION_CANCELLED';
  message: string;
  recoverable: boolean;
  details?: unknown;
};
```

Swift errors should use stable native error codes. Electron main maps them into renderer-safe `AppError` objects. User-facing copy belongs in Electron, not Swift.

## 11. Testing Strategy

### 11.1 JSON-RPC Tests

Test:

- Request correlation.
- Timeout behavior.
- Cancellation.
- Malformed helper output.
- Helper crash handling.
- Event forwarding.
- Native error mapping.

### 11.2 Preload Tests

Test:

- Method input validation.
- Renderer-safe return shapes.
- Subscription cleanup.
- Rejection of unknown or malformed commands.

### 11.3 Project API Tests

Test:

- Package creation.
- Package open/save.
- Schema version rejection.
- Missing asset handling.
- Cursor and click event parsing.
- Generated zoom persistence.

### 11.4 Workflow Integration Tests

Use a fake Swift helper for deterministic tests.

Test:

- Permission granted flow.
- Permission denied flow.
- Display listing.
- Recording start and stop.
- Package creation after recording.
- Editor open result.
- Export progress.
- Export completion.
- Export failure.
- Export cancellation.
- Export history updates.

### 11.5 Swift Tests

Test:

- JSON-RPC command decoding.
- JSON-RPC response encoding.
- Event encoding.
- Native error mapping.
- Recording state machine behavior.
- Export state machine behavior.

## 12. V1 Assumptions

- JSON-RPC is used only between Electron main and Swift.
- Renderer talks only to preload.
- Electron main owns all project package schema decisions.
- Swift owns native capture and native export.
- Export output defaults to Desktop.
- Export format is H.264 MP4 at 60 FPS.
- The renderer preview and export backend consume the same persisted project model.
