# fluxer-instance-launcher

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/G2G31WKOCN)

Starts the official Fluxer desktop app on a self-hosted instance, and keeps it there after updates and restarts. A small PowerShell script, no extra app to install. Windows only. Unofficial, not affiliated with the Fluxer project.

Status: built and tested against a throwaway registry key and folder; the real before and after Fluxer update test is still to do (steps below).

## Why

The official Fluxer app has no instance picker. The only way to open it on another server is the launch flag `--fluxer-app-url=<instance>`, which Fluxer never saves, so every restart and update puts you back on the official server. This launcher uses that flag for you and re-creates its own entries when they drift. Similar tools exist (`omgitsyasir/fluxer-desktop-instance-swapper`, a Tauri app; `gogy-no-one/gogys-fluxer`, an Electron wrapper; `nfb04/fluxer-desktop-app-multi-instance`, a modified client); this one keeps the unmodified official app and focuses on surviving updates. Is it safe? See [SECURITY.md](SECURITY.md).

## Quick start

1. Install Fluxer as normal, then quit it fully (tray icon too).
2. Copy `config/config.example.json` to `config/config.json` and set `instance_url` (default: the public instance https://chat.codered.lol).
3. Run `scripts\run.bat apply`. It creates a shortcut called "Fluxer (my instance)" on your Desktop and in the Start Menu, and a start-at-login entry.
4. From now on open Fluxer from that shortcut, or let it start at login.

## Actions

Run `scripts\run.bat <action>` (add `--no-pause` to close the window when done), or call `scripts\fluxer-instance-launcher.ps1 <action>` directly.

| Action | What it does |
|---|---|
| `launch` | Starts Fluxer with the flag (default). If Fluxer is already running on another instance it says so; quit it first, or add `-ForceRestart`. |
| `apply` | Creates or fixes the shortcuts and the `FluxerInstance` start-at-login entry, and removes Fluxer's own `Fluxer.Fluxer` entry. Safe to run repeatedly. |
| `repair` | Same as `apply`, silent when nothing has drifted. Runs by itself 15 seconds after each `launch`. |
| `status` | Lists every entry as OK, MISSING or DRIFT. Exit code 0 if all is well, 1 otherwise. |
| `uninstall` | Removes everything the launcher created and restores the stock `fluxer://` handler if it was patched. |

Options: `-DryRun` prints what would change and changes nothing; `-AllowInsecure` permits an `http://` address (refused otherwise); `-ConfigPath`, `-Root` and `-RegistryBase` redirect config, shortcuts and registry writes elsewhere (the tests use these so they never touch your real setup).

## Config

`config/config.json` (gitignored), falling back to `config/config.example.json`.

| Key | Default | Meaning |
|---|---|---|
| `instance_url` | `https://chat.codered.lol` | The server to open. Must be `https://`. |
| `autostart` | `true` | Start Fluxer on your instance at login. |
| `autostart_delay_seconds` | `15` | Wait before the login launch, so it does not race the desktop. |
| `handler_patch` | `false` | Opt in to also rewrite the `fluxer://` link handler. Fluxer rewrites it back on every launch, so it only helps until then. |
| `shortcut_name` | `Fluxer (my instance)` | Name of the shortcut the launcher owns. |
| `repair_after_launch_seconds` | `15` | Run `repair` this long after `launch`; `0` turns it off. |

## Limits

- After a Fluxer update restarts the app, it opens on the official server (Fluxer restarts without the flag). Close it and use the shortcut.
- No administrator rights, no network access, no stored secrets. `uninstall` removes everything.

## Tests

`Invoke-Pester tests` (Windows PowerShell 5.1, built-in Pester 3) and `python -m pytest tests` (repo guard test). All Pester tests run against a throwaway folder and registry key.

## Update test (still to do on a real install)

1. `scripts\run.bat --no-pause apply`, then `status`: expect all OK.
2. Reboot, check Fluxer opened on your instance, `status` again.
3. Let Fluxer apply a pending update (or accept its update prompt), then run `status`.
4. Note which entries survived. Entries reported DRIFT or MISSING are fixed by `repair`; record the result here.

## Licence

Not yet chosen. The launcher copies no Fluxer code, binaries or logos.
