# fluxer-instance-launcher

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31WKOCN)

Makes the Fluxer desktop app open on a self-hosted server instead of the official one, and keeps it that way. Windows only. Unofficial, not affiliated with the Fluxer project. Is it safe? See [SECURITY.md](docs/SECURITY.md).

## How to use it

1. Install Fluxer as normal, then close it completely (the tray icon too).
2. Double-click `Fluxer Instance Setup.bat` (in the `scripts` folder). The first time, it creates a settings file and tells you where it is. Open that file, check the server address (the default is https://chat.codered.lol), save it, then double-click the setup file again. Use the arrow keys to pick **Install** and press Enter, then press Y.
3. Open Fluxer from its normal Start Menu, Desktop or taskbar icon. The setup has told those icons to use your server. It also opens on your server when you sign in to Windows.

To remove everything, double-click `Fluxer Instance Setup.bat` and pick **Uninstall**. Fluxer itself is never touched.

The setup window shows the current status at the top in plain words: what is in place and what is not. If something looks wrong, pick **Install** and it puts it right.

**After every Fluxer update you must run setup again.** Tested 2026-10-04: the update replaced the Start Menu and taskbar icons, and Fluxer then restarted itself on the official server (not yours). To fix it, close Fluxer fully (right-click its tray icon, Quit Fluxer), double-click `Fluxer Instance Setup.bat`, pick **Install**, then open Fluxer from its normal icon. The status at the top of the setup window tells you if it is needed.

## Licence

Not yet chosen. The launcher copies no Fluxer code, binaries or logos.
