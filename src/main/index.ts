import { optimizer } from '@electron-toolkit/utils';
import { app, dialog, systemPreferences, shell, BrowserWindow, desktopCapturer } from 'electron';

import { setupRecorderIpc, setupStopRecorderIpc } from './ipc';
import { createRecorderWindow } from './windows';

import type { DesktopCapturerSource } from 'electron';

export const displaySources: DesktopCapturerSource[] = [];

void app.whenReady().then(async () => {
  // Check if the platform is macOS
  if (process.platform !== 'darwin') {
    dialog.showErrorBox('Unsupported Platform', 'This application is only supported on macOS.');
    app.quit();
    return;
  }

  app.on('browser-window-created', (_, window) => {
    optimizer.watchWindowShortcuts(window);
  });

  // Check if screen recording permission is granted
  const screenRecordingPermissionStatus = systemPreferences.getMediaAccessStatus('screen');
  if (screenRecordingPermissionStatus !== 'granted') {
    const dialogResponse = await dialog.showMessageBox({
      title: 'Permission Required',
      message:
        'This application requires screen recording permission to function. Please grant the permission in the System Settings and restart the application.',
      buttons: ['Open System Settings', 'Cancel'],
    });
    try {
      if (dialogResponse.response === 0) {
        await shell.openExternal(
          'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
        );
      }
    } finally {
      app.quit();
    }
    return;
  }

  displaySources.push(
    ...(await desktopCapturer.getSources({
      types: ['screen'],
      thumbnailSize: { width: 0, height: 0 },
    })),
  );

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      void createRecorderWindow();
    }
  });

  setupRecorderIpc();
  setupStopRecorderIpc();

  // Create and show the recorder window
  await createRecorderWindow();
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
