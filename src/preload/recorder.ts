import { contextBridge, ipcRenderer } from 'electron';

import { CLOSE_CURRENT_WINDOW, LIST_DISPLAY_SOURCES } from '../main/lib/constants';

import type { RecorderAPI } from '../main/lib/types';

if (process.contextIsolated) {
  try {
    contextBridge.exposeInMainWorld('electronAPI', {
      type: 'recorder',
      closeCurrentWindow: () => ipcRenderer.send(CLOSE_CURRENT_WINDOW),
      listDisplaySources: (): Promise<void> => ipcRenderer.invoke(LIST_DISPLAY_SOURCES),
    } satisfies RecorderAPI);
  } catch (error) {
    console.error(error);
  }
}
