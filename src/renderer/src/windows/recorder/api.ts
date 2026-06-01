import type { RecorderAPI } from 'src/main/lib/types';

export function getRecorderApi(): RecorderAPI {
  if (window.electronAPI.type !== 'recorder') {
    throw new Error('recorder window loaded with the wrong preload API');
  }

  return window.electronAPI;
}

export const recorderApi = getRecorderApi();
