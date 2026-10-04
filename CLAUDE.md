# fluxer-instance-launcher

A small PowerShell tool for non-technical Windows users: it makes the official Fluxer desktop app open on a chosen server and keeps it there. It makes no shortcut of its own: it patches Fluxer's existing icons (Start Menu, Desktop, taskbar) to pass `--fluxer-app-url`. People double-click `scripts/Fluxer Instance Setup.bat` and see the status and pick Install, Uninstall or Quit from a menu. The logic is in `scripts/fluxer-instance-launcher.ps1`. Default server: https://chat.codered.lol.

How Claude verifies: run `Invoke-Pester tests` and `python -m pytest tests`, then do the dry run and the real apply yourself (`scripts\fluxer-instance-launcher.ps1 apply -DryRun`, then `apply -Yes`, then `status`). Never ask the user to run a dry run or pass arguments; the user only double-clicks the bat.

Rules: `config/config.json` is gitignored and created by the script from an embedded template when missing; `config/config.example.json` is documentation only and no code may read it. No secrets, no network calls, no admin rights, no Fluxer code or logos copied. Keep this repo free of private workspace paths and other people's names. Private until a scrub is done; publishing is David's decision.

## Developer reference

PowerShell 5.1 script `scripts/fluxer-instance-launcher.ps1`, started by the thin `scripts/Fluxer Instance Setup.bat`. Fluxer has no instance picker; the only way is the launch flag `--fluxer-app-url=<instance>`, which it never saves. Similar tools exist (`omgitsyasir/fluxer-desktop-instance-swapper`, `gogy-no-one/gogys-fluxer`, `nfb04/fluxer-desktop-app-multi-instance`); this one keeps the unmodified official app and focuses on surviving updates.

With no action the script shows the status, then a menu (Install, Uninstall, Quit). With an action it runs without any menu, which is what tests and Claude use:

| Action | What it does |
|---|---|
| `launch` | Starts Fluxer with the flag. Refuses if Fluxer already runs on another instance unless `-ForceRestart`. Used by the login entry. |
| `apply` | Makes each existing Fluxer icon (Start Menu, Desktop, taskbar) pass `--fluxer-app-url=<server>` (replacing any existing one, keeping other arguments), removes shortcuts an earlier version made, sets the `FluxerInstance` Run value, removes Fluxer's own `Fluxer.Fluxer` Run value. Safe to repeat. |
| `repair` | Same as `apply`, silent when nothing drifted. Runs 15 seconds after each `launch`. |
| `status` | Prints a plain summary, then dot points. Exit 0 if all is well, 1 otherwise. |
| `uninstall` | Takes only the `--fluxer-app-url` argument off the Fluxer icons, removes the Run value and restores the stock `fluxer://` handler if it was patched. |

Options: `-DryRun` prints instead of changing; `-Yes` skips the menu's confirmation; `-AllowInsecure` permits `http://`; `-ConfigPath`, `-Root` and `-RegistryBase` redirect config, icons and registry writes (the tests use these on a throwaway key and folder). Exit codes: 0 ok, 1 status problem, 2 error, 3 settings file just created (or Fluxer running elsewhere on `launch`).

Settings live in `config/config.json` (gitignored). If it is missing the script creates it from a template built into the script; `config/config.example.json` is documentation only and no code reads it.

| Key | Default | Meaning |
|---|---|---|
| `instance_url` | `https://chat.codered.lol` | The server to open. Must be `https://`. |
| `autostart` | `true` | Open Fluxer on your instance at login. |
| `autostart_delay_seconds` | `15` | Wait before the login launch. |
| `handler_patch` | `false` | Opt in to rewriting the `fluxer://` handler (Fluxer rewrites it back on every launch). |
| `repair_after_launch_seconds` | `15` | Run `repair` this long after `launch`; `0` turns it off. |

Tests: `Invoke-Pester tests` (Windows PowerShell 5.1, Pester 3) and `python -m pytest tests`. The menu tests feed keys through the `FLI_TEST_KEYS` environment variable.

Update test result (2026-10-04, build 2026.1003.155758): after Fluxer's in-app update, the Start Menu and taskbar icons had lost `--fluxer-app-url` (the updater recreates them), status reported both as opening the official server, and the app auto-restarted on the official server. So an update always needs a re-Install; an automatic re-apply is a backlog item. Old settings files that still contain `shortcut_name` keep working; the key is ignored.
