export interface RecorderAPI {
  type: 'recorder';
  closeCurrentWindow: () => void;
  listDisplaySources: () => Promise<void>;
}

export interface StopRecorderAPI {
  type: 'stop-recorder';
  stopRecording: () => void;
}
