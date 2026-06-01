import { contextBridge, ipcRenderer } from 'electron';

import { STOP_RECORDING } from '../main/lib/constants';

import type { StopRecorderAPI } from '../main/lib/types';

if (process.contextIsolated) {
  try {
    contextBridge.exposeInMainWorld('electronAPI', {
      type: 'stop-recorder',
      stopRecording: () => ipcRenderer.send(STOP_RECORDING),
    } satisfies StopRecorderAPI);
  } catch (error) {
    console.error(error);
  }
}
