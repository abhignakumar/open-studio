import type { ElectronAPI } from '../main/lib/types';

export declare global {
  interface Window {
    electronAPI: ElectronAPI;
  }
}
