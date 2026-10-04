# fluxer-instance-launcher

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31WKOCN)

Makes the Fluxer desktop app open on a self-hosted server instead of the official one, and keeps it that way.

- Windows only.
- Unofficial, not affiliated with the Fluxer project.
- Is it safe? See [SECURITY.md](docs/SECURITY.md).

## Set up

1. Install the Fluxer desktop app from [fluxer.app/download](https://fluxer.app/download).
2. Close Fluxer completely: right-click its tray icon and pick **Quit Fluxer**.
3. Download this repo (green **<> Code** button, then **Download ZIP**) and unzip it.
4. Open the `scripts` folder and double-click `Fluxer Instance Setup.bat`.
5. The first time, it makes a settings file and shows where it is.
   - Check the file has the server you want.
   - The default is https://chat.codered.lol.
6. Double-click `Fluxer Instance Setup.bat` again.
   - Pick **Install** with the arrow keys.
   - Press Enter, then press Y.
7. Open Fluxer from its normal Start Menu or taskbar icon.
   - It opens on your server.
   - It also opens on your server when you sign in to Windows.
   - The setup adds no icons. It only changes the ones Fluxer already has.

## Check it

- The top of the setup window always shows the status in plain words.
- If something is wrong, pick **Install** and it is put right.
- Each run writes a log of what it did in the `logs` folder.

## After a Fluxer update

Every Fluxer update undoes the setup, and Fluxer restarts on the official server. To fix it:

1. Close Fluxer completely: right-click its tray icon and pick **Quit Fluxer**.
2. Double-click `Fluxer Instance Setup.bat`.
3. Pick **Install**, then open Fluxer from its normal icon.

## Remove it

Double-click `Fluxer Instance Setup.bat` and pick **Uninstall**. Fluxer itself is never touched.

## Licence

[MIT](LICENSE). The launcher copies no Fluxer code, binaries or logos.
