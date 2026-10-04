# fluxer-instance-launcher

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31WKOCN)

Makes the Fluxer desktop app open on a self-hosted server instead of the official one, and keeps it that way. Windows only. Unofficial, not affiliated with the Fluxer project. Is it safe? See [SECURITY.md](docs/SECURITY.md).

## How to use it

1. Install Fluxer as normal, then close it completely (the tray icon too).
2. Double-click `Fluxer Instance Setup.bat` (in the `scripts` folder). The first time, it creates a settings file and tells you where it is. Open that file, check the server address (the default is https://chat.codered.lol), save it, then double-click the setup file again. Use the arrow keys to pick **Install** and press Enter, then press Y.
3. Open Fluxer from the new **Fluxer (my instance)** shortcut on your Desktop or in the Start Menu. It also opens that way when you sign in to Windows.

To remove everything, double-click `Fluxer Instance Setup.bat` and pick **Uninstall**. Fluxer itself is never touched.

The setup window shows the current status at the top in plain words: what is in place and what is not. If something looks wrong, pick **Install** and it puts it right.

After a Fluxer update the app may open on the official server once. Close it and use the shortcut again.

## For developers

PowerShell 5.1 script `scripts/fluxer-instance-launcher.ps1`, started by the thin `scripts/Fluxer Instance Setup.bat`. Fluxer has no instance picker; the only way is the launch flag `--fluxer-app-url=<instance>`, which it never saves. Similar tools exist (`omgitsyasir/fluxer-desktop-instance-swapper`, `gogy-no-one/gogys-fluxer`, `nfb04/fluxer-desktop-app-multi-instance`); this one keeps the unmodified official app and focuses on surviving updates.

With no action the script shows the status, then a menu (Install, Uninstall, Quit). With an action it runs without any menu, which is what tests and Claude use:

| Action | What it does |
|---|---|
| `launch` | Starts Fluxer with the flag. Refuses if Fluxer already runs on another instance unless `-ForceRestart`. Used by the shortcut and the login entry. |
| `apply` | Creates or fixes the shortcuts and the `FluxerInstance` Run value, removes Fluxer's own `Fluxer.Fluxer` Run value. Safe to repeat. |
| `repair` | Same as `apply`, silent when nothing drifted. Runs 15 seconds after each `launch`. |
| `status` | Lists each entry as OK, MISSING or DRIFT. Exit 0 if all is well, 1 otherwise. |
| `uninstall` | Removes everything the launcher made and restores the stock `fluxer://` handler if it was patched. |

Options: `-DryRun` prints instead of changing; `-Yes` skips the menu's confirmation; `-AllowInsecure` permits `http://`; `-ConfigPath`, `-Root` and `-RegistryBase` redirect config, shortcuts and registry writes (the tests use these on a throwaway key and folder). Exit codes: 0 ok, 1 status problem, 2 error, 3 settings file just created (or Fluxer running elsewhere on `launch`).

Settings live in `config/config.json` (gitignored). If it is missing the script creates it from a template built into the script; `config/config.example.json` is documentation only and no code reads it.

| Key | Default | Meaning |
|---|---|---|
| `instance_url` | `https://chat.codered.lol` | The server to open. Must be `https://`. |
| `autostart` | `true` | Open Fluxer on your instance at login. |
| `autostart_delay_seconds` | `15` | Wait before the login launch. |
| `handler_patch` | `false` | Opt in to rewriting the `fluxer://` handler (Fluxer rewrites it back on every launch). |
| `shortcut_name` | `Fluxer (my instance)` | Name of the shortcut the launcher owns. |
| `repair_after_launch_seconds` | `15` | Run `repair` this long after `launch`; `0` turns it off. |

Tests: `Invoke-Pester tests` (Windows PowerShell 5.1, Pester 3) and `python -m pytest tests`. The menu tests feed keys through the `FLI_TEST_KEYS` environment variable.

Still to do: a real before and after Fluxer update test (apply, status, reboot, let Fluxer update, status again, and record which entries survived).

## Licence

Not yet chosen. The launcher copies no Fluxer code, binaries or logos.
