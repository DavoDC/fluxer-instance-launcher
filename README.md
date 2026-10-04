# fluxer-instance-launcher

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31WKOCN)

Makes the Fluxer desktop app open on a self-hosted server instead of the official one, and keeps it that way. Windows only. Unofficial, not affiliated with the Fluxer project. Is it safe? See [SECURITY.md](docs/SECURITY.md).

## Set up

1. Install Fluxer as normal.
2. Close Fluxer completely:
   - Right-click its tray icon (bottom right, near the clock).
   - Pick **Quit Fluxer**.
3. Open the `scripts` folder and double-click `Fluxer Instance Setup.bat`.
4. The first time, it makes a settings file and shows where it is:
   - Open that file.
   - Check the server address is the one you want. The default is https://chat.codered.lol.
   - Save the file, then double-click `Fluxer Instance Setup.bat` again.
5. Pick **Install**:
   - Use the arrow keys, then press Enter.
   - Press Y to confirm.
6. Open Fluxer from its normal Start Menu, Desktop or taskbar icon. It opens on your server, and also when you sign in to Windows.

## Check it

The top of the setup window always shows the status in plain words. If something is wrong, pick **Install** and it is put right.

## After a Fluxer update

Every Fluxer update undoes the setup, and Fluxer restarts on the official server. To fix it:

1. Close Fluxer completely (tray icon, **Quit Fluxer**).
2. Double-click `Fluxer Instance Setup.bat`.
3. Pick **Install**, then open Fluxer from its normal icon.

## Remove it

Double-click `Fluxer Instance Setup.bat` and pick **Uninstall**. Fluxer itself is never touched.

## Licence

Not yet chosen. The launcher copies no Fluxer code, binaries or logos.
