# Data Model

Last updated: May 28, 2026

## 1. Summary

Open Studio V1 stores each completed recording as a local `.openstudio` macOS package.

The V1 project model is intentionally narrow:

- One project contains one screen recording.
- The raw screen recording is stored as an H.264 MP4.
- Cursor movement events and mouse click events are stored as separate JSON files.
- User-editable project state, such as zoom segments and render settings, is stored as versioned structured JSON.
- All data remains local by default.

The persistence format should optimize for portability, debugging, deterministic preview/export behavior, and straightforward schema migrations.

## 2. Package Layout

Each project is a package directory with the `.openstudio` extension.

```text
My Recording.openstudio/
  manifest.json
  project.json
  media/
    raw-recording.mp4
  events/
    cursor-movements.json
    mouse-clicks.json
```

## 3. Manifest

`manifest.json` is the package entrypoint. It identifies the bundle as an Open Studio project and points to the canonical project file.

```ts
type ProjectManifest = {
  app: 'open-studio';
  packageVersion: 1;
  projectId: string;
  projectSchemaVersion: 1;
  createdAt: string;
  updatedAt: string;
  projectFile: 'project.json';
};
```

## 4. Core Project Schema

`project.json` stores the canonical editable project state.

```ts
type OpenStudioProject = {
  schemaVersion: 1;
  projectId: string;
  name: string;
  createdAt: string;
  updatedAt: string;

  recording: RecordingAsset;
  source: SourceMetadata;
  timeline: TimelineModel;
  cursor: CursorRenderSettings;
  motion: MotionSettings;
  exportDefaults: ExportSettings;
};
```

## 5. Recording Asset

```ts
type RecordingAsset = {
  id: string;
  relativePath: 'media/raw-recording.mp4';
  codec: 'h264';
  container: 'mp4';
  fps: 60;
  durationMs: number;
  widthPx: number;
  heightPx: number;
  hasCursor: false;
  capturedStartTimeAt: string;
  capturedEndTimeAt: string;
  byteSize?: number;
  contentHash?: string;
};
```

## 6. Source Metadata

Source metadata records the selected display and coordinate space used by cursor events.

```ts
type SourceMetadata = {
  captureMode: 'display';
  display: {
    id: string;
    name: string;
    widthPx: number;
    heightPx: number;
    scaleFactor: number;
    originX: number;
    originY: number;
  };
  coordinateSpace: {
    origin: 'top-left';
    unit: 'display-pixel';
  };
};
```

Coordinates are relative to the captured display, with `0,0` at the top-left of the captured frame.

## 7. Timeline Model

The V1 timeline contains the full clip and one editable zoom segment track.

```ts
type TimelineModel = {
  durationMs: number;
  zoomSegments: ZoomSegment[];
};
```

```ts
type ZoomSegment = {
  id: string;
  source: 'generated' | 'manual';
  triggerClickId?: string;
  startMs: number;
  endMs: number;
  scale: number;
  focalPoint: {
    mode: 'cursor';
  };
  createdAt: string;
  updatedAt: string;
};
```

Generated zooms default to `scale: 2`. The focal point remains cursor-based in V1 so preview and export can pan automatically to keep the cursor visible while zoomed.

## 8. Cursor Movement Events

Cursor movement events are stored separately in `events/cursor-movements.json`.

```ts
type CursorMovementsFile = {
  schemaVersion: 1;
  recordingId: string;
  sampleRateHintHz?: number;
  events: CursorMovementEvent[];
};
```

```ts
type CursorMovementEvent = {
  tMs: number;
  x: number;
  y: number;
};
```

## 9. Mouse Click Events

Mouse click events are stored separately in `events/mouse-clicks.json`.

```ts
type MouseClicksFile = {
  schemaVersion: 1;
  recordingId: string;
  events: MouseClickEvent[];
};
```

```ts
type MouseClickEvent = {
  id: string;
  tMs: number;
  x: number;
  y: number;
  button: 'left' | 'right' | 'middle' | 'other';
  phase: 'down' | 'up' | 'click';
  clickCount: number;
};
```

## 10. Cursor Render Settings

```ts
type CursorRenderSettings = {
  asset: 'system-default';
  sizePx: number;
  anchor: {
    x: number;
    y: number;
  };
  visible: true;
};
```

## 11. Motion Settings

```ts
type MotionSettings = {
  zoomSpring: SpringSettings;
  panSpring: SpringSettings;
  cursorSpring: SpringSettings;
  motionBlur: {
    screen: boolean;
    cursor: boolean;
  };
};
```

```ts
type SpringSettings = {
  tension: number;
  stiffness: number;
  damping: number;
};
```

## 12. Export Settings

```ts
type ExportSettings = {
  format: 'mp4';
  codec: 'h264';
  fps: 60;
  resolution: 'original' | '1080p';
  destination: 'desktop';
};
```

Export jobs are not required for canonical preview state, but a lightweight history file is useful for completion UI and debugging.

```ts
type ExportHistoryFile = {
  schemaVersion: 1;
  exports: ExportRecord[];
};
```

```ts
type ExportRecord = {
  id: string;
  startedAt: string;
  completedAt?: string;
  status: 'completed' | 'failed' | 'cancelled';
  outputPath?: string;
  settings: ExportSettings;
  errorCode?: string;
};
```

## 13. Versioning and Migration

The package uses two version fields:

- `packageVersion` in `manifest.json` versions the package layout.
- `schemaVersion` in each JSON file versions the data shape for that file.

Future migrations should be explicit and deterministic. The app should never silently reinterpret an old file shape without checking its version.

## 14. V1 Assumptions

- V1 projects contain exactly one raw recording.
- JSON files are the canonical persisted format.
- Event timestamps use integer milliseconds from recording start.
- Cursor and click coordinates use captured display pixels, not logical points.
- Zoom focal behavior is cursor-centered in V1.
- `project.json` owns editable state.
- Event files own immutable capture metadata.
- Future schema changes are handled through versioned migrations.
