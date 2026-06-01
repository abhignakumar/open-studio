import type { StopRecorderAPI } from 'src/main/lib/types';

export function getStopRecorderApi(): StopRecorderAPI {
  if (window.electronAPI.type !== 'stop-recorder') {
    throw new Error('stop-recorder window loaded with the wrong preload API');
  }

  return window.electronAPI;
}

export const stopRecorderApi = getStopRecorderApi();
