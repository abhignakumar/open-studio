import type { RecorderAPI } from '../main/lib/types';

export declare global {
  interface Window {
    electronAPI: RecorderAPI;
  }
}
