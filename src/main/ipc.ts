import { ipcMain, screen, BrowserWindow, Menu } from 'electron';

import { displaySources } from '.';
import { CLOSE_CURRENT_WINDOW, LIST_DISPLAY_SOURCES, STOP_RECORDING } from './lib/constants';
import { createStopRecorderWindow } from './windows';

export function setupRecorderIpc(): void {
  ipcMain.on(CLOSE_CURRENT_WINDOW, (event) => {
    const window = BrowserWindow.fromWebContents(event.sender);
    window?.close();
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
          await createStopRecorderWindow();
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
  ipcMain.on(STOP_RECORDING, () => {
    console.log('Stopping recording');
  });
}
