export interface RecorderAPI {
  type: 'recorder';
  closeCurrentWindow: () => void;
  listDisplaySources: () => Promise<void>;
}
