import { optimizer } from '@electron-toolkit/utils';
import { app, dialog, systemPreferences, shell } from 'electron';

void app.whenReady().then(async () => {
  // Check if the platform is macOS
  if (process.platform !== 'darwin') {
    dialog.showErrorBox('Unsupported Platform', 'This application is only supported on macOS.');
    app.quit();
    process.exit();
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
    if (dialogResponse.response === 0) {
      await shell.openExternal(
        'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture',
      );
    }
    app.quit();
    process.exit();
  }
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
