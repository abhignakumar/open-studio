import type { RecorderAPI, StopRecorderAPI } from '../main/lib/types';

export declare global {
  interface Window {
    electronAPI: RecorderAPI | StopRecorderAPI;
  }
}
