# fluxer-instance-launcher

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31WKOCN)

Makes the Fluxer desktop app open on a self-hosted server instead of the official one, and keeps it that way.

- Windows only.
- Unofficial, not affiliated with the Fluxer project.
- Is it safe? See [SECURITY.md](docs/SECURITY.md).

## Setup

1. Install the Fluxer desktop app from [fluxer.app/download](https://fluxer.app/download).
2. Close Fluxer completely: right-click its tray icon and pick **Quit Fluxer**.
3. Download this repo (green **<> Code** button, then **Download ZIP**) and unzip it.
4. Open the `scripts` folder and double-click `Fluxer Instance Setup.bat`.
5. The first run makes a settings file. Check it has the server you want.
   - The default is https://chat.codered.lol.
6. Double-click `Fluxer Instance Setup.bat` again, then pick **Install**.
7. Open Fluxer from its normal Start Menu or taskbar icon.
   - It opens on your server, also when you sign in to Windows.
   - The setup adds no icons. It only changes Fluxer's own.

## Check that it works

- The top of the setup window always shows the status in plain words.
- If something is wrong, pick **Install** and it is put right.
- Each run writes a log of what it did in the `logs` folder.

## After a Fluxer update

Every Fluxer update undoes the setup, and Fluxer restarts on the official server. To fix it:

1. Double-click `Fluxer Instance Setup.bat`.
2. Pick **Install**. It closes Fluxer for you.
3. Open Fluxer from its normal Start Menu or taskbar icon.

## Optional update watcher

When you pick **Install**, the setup asks whether to keep Fluxer on your server after updates. Say yes and a small hidden helper starts right after Install and runs whenever you are signed in. It sits idle, and when a Fluxer update changes its icons it puts your server back and reopens Fluxer. It is off by default. Uninstall stops it.

## Uninstall

Double-click `Fluxer Instance Setup.bat` and pick **Uninstall**. Fluxer itself is never touched.

## Licence

[MIT](LICENSE). The launcher copies no Fluxer code, binaries or logos.
