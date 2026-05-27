# Product Requirements Document (Open Studio)

Last updated: May 26, 2026

## 1. Product Context

Open Studio is a native macOS desktop application for creating polished screen recordings with minimal editing. V1 focuses on one narrow workflow: pick a display, record screen video without the cursor, capture cursor movement and clicks as metadata, automatically generate zoom segments, preview/edit those zooms, render a smooth high-resolution cursor overlay, and export an MP4.

V1 is not a full video editor. It should feel fast, focused, and intentionally limited.

Reference context:

- Screen Studio homepage: https://screenstudio.net/en/
- Recording modes and capture setup: https://preview.screen.studio/guide/new-recording
- Zoom editing: https://preview.screen.studio/guide/adding-editing-zooms
- Cursor settings: https://preview.screen.studio/guide/cursor
- Export settings: https://preview.screen.studio/guide/explanation-of-export-settings

## 2. Functional Requirements

### 2.1 App Launch and Permissions

| ID     | Requirement                                           | Priority | Acceptance Criteria                                                                                                     |
| ------ | ----------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------------------------- |
| FR-001 | Provide a native macOS desktop app named Open Studio. | P0       | App can be installed/launched on supported macOS versions and displays the Open Studio name/icon.                       |
| FR-002 | Check Screen Recording permission when the app opens. | P0       | On launch, the app detects whether Screen Recording permission has already been granted.                                |
| FR-003 | Request Screen Recording permission when missing.     | P0       | If permission is missing, the app prompts the user and provides a clear recovery state until permission is granted.     |
| FR-004 | Show the recording picker as the primary app surface. | P0       | After permission handling, the app shows the recording picker instead of a project dashboard or recent-projects screen. |

### 2.2 Recording Picker and Recording Flow

| ID     | Requirement                                                         | Priority | Acceptance Criteria                                                                                                    |
| ------ | ------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------- |
| FR-005 | Show a single Record button in the idle recording picker.           | P0       | The initial picker contains one primary button labeled "Record".                                                       |
| FR-006 | Show available displays after Record is clicked.                    | P0       | Clicking "Record" opens a dropdown list containing the names of all available displays.                                |
| FR-007 | Start recording when the user selects a display.                    | P0       | Selecting a display from the dropdown immediately starts recording that display.                                       |
| FR-008 | Convert the picker into a compact stop control while recording.     | P0       | During recording, the picker remains visually similar but becomes smaller and shows one primary button labeled "Stop". |
| FR-009 | Stop recording from the compact picker.                             | P0       | Clicking "Stop" ends the active recording.                                                                             |
| FR-010 | Open the editor/preview window automatically after recording stops. | P0       | After the recording stops, the app automatically opens the completed recording in the editor/preview window.           |

### 2.3 Raw Recording and Event Capture

| ID     | Requirement                                          | Priority | Acceptance Criteria                                                                                   |
| ------ | ---------------------------------------------------- | -------- | ----------------------------------------------------------------------------------------------------- |
| FR-011 | Record the selected display to MP4.                  | P0       | The raw screen recording is saved as an MP4 file.                                                     |
| FR-012 | Use H.264 for raw recording.                         | P0       | The raw recording video stream is encoded with H.264.                                                 |
| FR-013 | Record at 60 FPS.                                    | P0       | The raw recording is captured at 60 FPS.                                                              |
| FR-014 | Record at the selected display's resolution.         | P0       | The raw recording preserves the selected display's capture resolution.                                |
| FR-015 | Exclude the cursor from the raw video recording.     | P0       | The captured MP4 does not contain the system cursor.                                                  |
| FR-016 | Capture mouse movement events while recording.       | P0       | Cursor position samples are captured with timestamps and coordinates aligned to the selected display. |
| FR-017 | Capture mouse click events while recording.          | P0       | Mouse clicks are captured with timestamps, coordinates, and click metadata.                           |
| FR-018 | Store mouse movement events in JSON.                 | P0       | Each recording stores mouse movement events in a JSON file.                                           |
| FR-019 | Store mouse click events in JSON.                    | P0       | Each recording stores mouse click events in a separate JSON file.                                     |
| FR-020 | Keep screen pixels and cursor metadata synchronized. | P0       | Cursor movement and click timestamps align with the raw recording timeline.                           |

### 2.4 Project Package Format

| ID     | Requirement                                               | Priority | Acceptance Criteria                                                              |
| ------ | --------------------------------------------------------- | -------- | -------------------------------------------------------------------------------- |
| FR-021 | Save each recording as an Open Studio project.            | P0       | Each completed recording creates one local project.                              |
| FR-022 | Use the `.openstudio` extension for project packages.     | P0       | Project files appear as packages/bundles with the `.openstudio` extension.       |
| FR-023 | Store the raw recording inside the project package.       | P0       | The `.openstudio` package contains the raw MP4 recording.                        |
| FR-024 | Store cursor event JSON files inside the project package. | P0       | The `.openstudio` package contains separate mouse movement and click JSON files. |
| FR-025 | Store generated and edited zoom segments as project data. | P0       | Reopening a project preserves the current zoom segments and their edited values. |

### 2.5 Editor and Timeline

| ID     | Requirement                                                    | Priority | Acceptance Criteria                                                       |
| ------ | -------------------------------------------------------------- | -------- | ------------------------------------------------------------------------- |
| FR-026 | Provide an editor/preview window for each completed recording. | P0       | The editor shows the final edited video preview for the current project.  |
| FR-027 | Show a timeline at the bottom of the editor.                   | P0       | The bottom of the editor contains the timeline controls.                  |
| FR-028 | Show timestamp marks on the timeline.                          | P0       | The timeline displays visible timestamp markers.                          |
| FR-029 | Provide a scrubber.                                            | P0       | The user can scrub through the project timeline.                          |
| FR-030 | Provide play/pause control.                                    | P0       | The user can play and pause preview playback.                             |
| FR-031 | Show the full clip as the first timeline level.                | P0       | The timeline has a full-clip level representing the complete recording.   |
| FR-032 | Show zoom segments as the second timeline level.               | P0       | The timeline has a separate zoom-segment level showing all zoom segments. |
| FR-033 | Provide an Export button in the editor.                        | P0       | The export button appears at the top right of the editor window.          |

### 2.6 Zoom Generation and Editing

| ID     | Requirement                                                                | Priority | Acceptance Criteria                                                                                                              |
| ------ | -------------------------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------- |
| FR-034 | Generate zoom segments automatically after recording stops.                | P0       | When the editor opens, zoom segments are already generated from mouse click events.                                              |
| FR-035 | Define each zoom segment with start time, end time, and scale factor.      | P0       | Each zoom segment stores start time, end time, and scale factor.                                                                 |
| FR-036 | Default generated zoom segments to 2x scale.                               | P0       | Automatically generated zoom segments use a default scale factor of 2x.                                                          |
| FR-037 | Start each generated zoom before the triggering click.                     | P0       | A zoom segment begins a fixed lead time before the click that triggered it.                                                      |
| FR-038 | Extend active zoom segments when clicks happen close together.             | P0       | If another click occurs within the configured extension window, the active zoom segment remains active and its end timer resets. |
| FR-039 | End zoom segments after the extension window passes without another click. | P0       | If no additional click occurs within the configured extension window, the current zoom segment ends.                             |
| FR-040 | Keep the cursor visible while zoomed.                                      | P0       | During zoomed playback/export, the screen automatically pans so the rendered cursor remains visible and in frame.                |
| FR-041 | Allow users to add zoom segments.                                          | P0       | The user can create a new zoom segment on the zoom timeline.                                                                     |
| FR-042 | Allow users to remove zoom segments.                                       | P0       | The user can delete a zoom segment from the zoom timeline.                                                                       |
| FR-043 | Allow users to edit zoom segment timing.                                   | P0       | The user can move or edit zoom segment start and end times.                                                                      |
| FR-044 | Allow users to edit zoom segment scale factor.                             | P0       | The user can change the scale factor for a zoom segment.                                                                         |

### 2.7 Preview Rendering, Motion, and Cursor Overlay

| ID     | Requirement                                             | Priority | Acceptance Criteria                                                                                                                |
| ------ | ------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| FR-045 | Render the edited video in preview.                     | P0       | Preview playback shows the raw video with zooms, pans, cursor overlay, animation, and motion blur applied.                         |
| FR-046 | Overlay a high-resolution cursor in preview and export. | P0       | Because the raw video excludes the cursor, preview and export render a high-resolution cursor overlay from captured cursor events. |
| FR-047 | Provide configurable cursor size.                       | P0       | The user can adjust the rendered cursor size.                                                                                      |
| FR-048 | Animate zoom in/out with spring physics.                | P0       | Zoom animation uses spring-physics based movement with configurable tension, stiffness, and damping.                               |
| FR-049 | Animate panning while zoomed with spring physics.       | P0       | Screen panning uses spring-physics based movement with configurable tension, stiffness, and damping.                               |
| FR-050 | Animate cursor movement with separate spring physics.   | P0       | Cursor movement uses its own spring-physics values for tension, stiffness, and damping.                                            |
| FR-051 | Apply motion blur to screen movement.                   | P0       | Zoom in/out and panning movement have visible motion blur in preview and export.                                                   |
| FR-052 | Apply motion blur to cursor movement.                   | P0       | Rendered cursor movement has visible motion blur in preview and export.                                                            |

### 2.8 Export

| ID     | Requirement                                | Priority | Acceptance Criteria                                                                  |
| ------ | ------------------------------------------ | -------- | ------------------------------------------------------------------------------------ |
| FR-053 | Export the edited video to MP4.            | P0       | The exported file is an MP4 containing all previewed edits.                          |
| FR-054 | Use H.264 for export.                      | P0       | The exported video stream is encoded with H.264.                                     |
| FR-055 | Export at 60 FPS.                          | P0       | The exported video is rendered at 60 FPS.                                            |
| FR-056 | Support original-resolution export.        | P0       | The user can export at the captured video's resolution.                              |
| FR-057 | Support 1080p export.                      | P0       | The user can export at 1080p.                                                        |
| FR-058 | Save exported videos to Desktop.           | P0       | Exported MP4 files are written to the user's Desktop.                                |
| FR-059 | Show export progress and completion state. | P0       | The user sees progress while rendering and a completion state after export finishes. |

## 3. Non-Functional Requirements

### 3.1 Platform and Compatibility

| ID      | Requirement                                        | Priority | Acceptance Criteria                                   |
| ------- | -------------------------------------------------- | -------- | ----------------------------------------------------- |
| NFR-001 | Support macOS 14 Sonoma and newer.                 | P0       | App launches and records on supported macOS versions. |
| NFR-002 | Support Apple Silicon as the primary architecture. | P0       | App runs natively on Apple Silicon.                   |
| NFR-003 | Intel Mac support is optional for V1.              | P2       | Product decision is documented before release.        |

### 3.2 Performance

| ID      | Requirement                                                            | Priority | Acceptance Criteria                                                                         |
| ------- | ---------------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------- |
| NFR-004 | Record at the selected display's native resolution at 60 FPS reliably. | P0       | No dropped-frame bursts during a 30-minute standard recording on target hardware.           |
| NFR-005 | Keep preview responsive.                                               | P0       | Scrubbing and playback controls respond within 150 ms under normal project sizes.           |
| NFR-006 | Export efficiently.                                                    | P1       | A 5-minute project exports in a reasonable time on target hardware, with progress feedback. |
| NFR-007 | Avoid excessive battery/CPU use while idle.                            | P1       | App does not continue capture/render loops after recording/export ends.                     |

### 3.3 Reliability

| ID      | Requirement                                             | Priority | Acceptance Criteria                                                                          |
| ------- | ------------------------------------------------------- | -------- | -------------------------------------------------------------------------------------------- |
| NFR-008 | Protect recordings from data loss.                      | P0       | A recording interrupted by app crash or forced quit can be recovered when feasible.          |
| NFR-009 | Handle permission denial gracefully.                    | P0       | App never crashes or enters a dead-end state when permissions are missing.                   |
| NFR-010 | Handle unavailable displays gracefully.                 | P0       | Disconnected or unavailable displays are reflected in UI and do not crash recording.         |
| NFR-011 | Keep project packages portable within the same machine. | P1       | Moving a `.openstudio` package preserves its raw recording, event JSON files, and edit data. |

### 3.4 Privacy and Security

| ID      | Requirement                                               | Priority | Acceptance Criteria                                                                                           |
| ------- | --------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------- |
| NFR-012 | Keep all V1 data local by default.                        | P0       | App does not upload recordings, event data, or metadata.                                                      |
| NFR-013 | Make capture state obvious.                               | P0       | User can always tell when recording is active.                                                                |
| NFR-014 | Request only necessary macOS permissions.                 | P0       | App asks for screen recording permission only when needed.                                                    |
| NFR-015 | Avoid collecting analytics that include captured content. | P0       | Any future telemetry excludes pixels, cursor traces, click events, and file paths unless explicitly opted in. |

### 3.5 Usability and Accessibility

| ID      | Requirement                                        | Priority | Acceptance Criteria                                                                                                         |
| ------- | -------------------------------------------------- | -------- | --------------------------------------------------------------------------------------------------------------------------- |
| NFR-016 | Optimize for fast first recording.                 | P0       | A new user can complete a basic recording/export without reading documentation.                                             |
| NFR-017 | Keep the editor focused.                           | P1       | The editor stays focused on preview, timeline playback, zoom editing, cursor size, and export.                              |
| NFR-018 | Use native macOS interaction patterns.             | P1       | Menus, dropdowns, file behavior, permission recovery, and window behavior feel familiar on macOS.                           |
| NFR-019 | Provide clear error messages.                      | P0       | Errors explain what happened and the next action the user can take.                                                         |
| NFR-020 | Support keyboard navigation for core controls.     | P1       | Recording picker, editor playback, timeline scrubber, zoom segments, cursor size, and export can be operated from keyboard. |
| NFR-021 | Provide VoiceOver labels for interactive controls. | P1       | Primary controls are announced clearly.                                                                                     |
| NFR-022 | Maintain sufficient contrast.                      | P1       | UI meets WCAG AA contrast for text and important controls.                                                                  |

### 3.6 Maintainability

| ID      | Requirement                                                                                                   | Priority | Acceptance Criteria                                                                                                                                        |
| ------- | ------------------------------------------------------------------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| NFR-023 | Keep capture, event recording, project package, editor state, preview rendering, and export pipeline modular. | P0       | Each subsystem can be tested and evolved independently.                                                                                                    |
| NFR-024 | Store project data as structured data.                                                                        | P0       | Raw media, cursor movement events, click events, zoom segments, cursor settings, and source metadata are represented as versioned structured project data. |
| NFR-025 | Include automated tests for critical project logic.                                                           | P1       | Project package load/save, event parsing, zoom generation, timeline transforms, and coordinate mapping have regression tests.                              |

## 4. Out of Scope for V1

- Project dashboard, recent-projects screen, cloud hosting, share links, team workspaces, comments, or accounts.
- Window or custom-area capture.
- Microphone, webcam/camera, system audio, or iPhone/iPad capture.
- Captions or transcription.
- Multi-clip project editing.
- Full timeline editing with arbitrary tracks, transitions, text overlays, stickers, annotations, or B-roll.
- Trim editing unless added later.
- AI voice, background music, or noise removal.
- Visual styling controls such as backgrounds, padding, rounded corners, shadows, or camera picture-in-picture.
- GIF or MOV export.
- Windows or Linux support.
- Plugin system.
