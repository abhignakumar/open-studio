import { ipcMain, screen, BrowserWindow, Menu } from 'electron';

import { displaySources } from '.';
import { CLOSE_CURRENT_WINDOW, LIST_DISPLAY_SOURCES, STOP_RECORDING } from './lib/constants';
import { createRecorderWindow, createStopRecorderWindow } from './windows';

export function setupRecorderIpc(): void {
  ipcMain.on(CLOSE_CURRENT_WINDOW, (event) => {
    const recorderWindow = BrowserWindow.fromWebContents(event.sender);
    recorderWindow?.close();
  });

  ipcMain.handle(LIST_DISPLAY_SOURCES, (event) => {
    const displays = screen.getAllDisplays();
    const recorderWindow = BrowserWindow.fromWebContents(event.sender);

    const mappedSources = displaySources.map((source) => {
      const display = displays.find((display) => display.id === Number(source.display_id));
      return {
        displayId: source.display_id,
        id: source.id,
        displayName: display?.label,
      };
    });

    const menu = Menu.buildFromTemplate(
      mappedSources.map((source) => ({
        label: source.displayName ?? 'Unknown display',
        click: async () => {
          // Start recording
          recorderWindow?.close();
          try {
            await createStopRecorderWindow();
          } catch (error) {
            console.error('Failed to open stop recorder window', error);
            await createRecorderWindow();
          }
        },
      })),
    );

    menu.popup({
      window: recorderWindow ?? undefined,
    });
    return;
  });
}

export function setupStopRecorderIpc(): void {
  ipcMain.on(STOP_RECORDING, (event) => {
    const stopRecorderWindow = BrowserWindow.fromWebContents(event.sender);
    stopRecorderWindow?.close();
    console.log('Stopping recording');
  });
}
