# fluxer-instance-launcher

A small PowerShell tool for non-technical Windows users: it makes the official Fluxer desktop app open on a chosen server and keeps it there. It makes no shortcut of its own: it patches Fluxer's existing icons (Start Menu, Desktop, taskbar) to pass `--fluxer-app-url`. People double-click `scripts/Fluxer Instance Setup.bat` and see the status and pick Install, Uninstall or Quit from a menu. The logic is in `scripts/fluxer-instance-launcher.ps1`. Default server: https://chat.codered.lol.

How Claude verifies: run `Invoke-Pester tests` and `python -m pytest tests`, then do the dry run and the real apply yourself (`scripts\fluxer-instance-launcher.ps1 apply -DryRun`, then `apply -Yes`, then `status`). Never ask the user to run a dry run or pass arguments; the user only double-clicks the bat.

Logs: every run writes one file `logs/YYYY-MM-DD_HH-MM-SS_<action>.log` at the repo root (gitignored, created on first use) with every line timestamped. Logging is a side channel only (`Write-Log`) and never changes the terminal output or the exit code. Tests pass a sandbox `-LogDir` so they never write the real folder.

Owner rule: Uninstall must undo absolutely everything Install did, so after Uninstall the status reads as it did before the first Install. When Install changes, Uninstall changes in the same commit; the round-trip test in `tests` (Install then Uninstall compares registry values, every icon's Arguments and `watch_updates`) guards it. Install saves what it overwrites (Fluxer's own `Fluxer.Fluxer` Run value: exact value and type) in the gitignored `data/state.json`, never overwriting an earlier saved original, and Uninstall puts it back. The only things Uninstall cannot undo: deleting a legacy shortcut an earlier version made, and closing a Fluxer that was open on another server. The settings file and logs are the tool's own files and stay.

The terminal design (menu, status, Install and Uninstall output, bat banner) is locked: change it only with the repo owner's explicit approval in that session.

Rules: `config/config.json` is gitignored and created by the script from an embedded template when missing; `config/config.example.json` is documentation only and no code may read it. No secrets, no network calls, no admin rights, no Fluxer code or logos copied. Keep this repo free of private workspace paths and other people's names. MIT licensed.

## Developer reference

PowerShell 5.1 script `scripts/fluxer-instance-launcher.ps1`, started by the thin `scripts/Fluxer Instance Setup.bat`. Fluxer has no instance picker; the only way is the launch flag `--fluxer-app-url=<instance>`, which it never saves. Similar tools exist (see `docs/design-decisions.md`); this one keeps the unmodified official app and focuses on surviving updates.

Key docs: `docs/how-it-works.md` (flag, Fluxer's own behaviour, every change Install makes and its Uninstall, watcher, limits), `docs/design-decisions.md` (choices and rejected alternatives), `docs/development.md` (tests, seams, engineering rules), `docs/SECURITY.md` (trust).

With no action the script shows the status, then a menu (Install, Uninstall, Quit). With an action it runs without any menu, which is what tests and Claude use:

| Action | What it does |
|---|---|
| `launch` | Starts Fluxer with the flag. Refuses if Fluxer already runs on another instance unless `-ForceRestart`. Used by the login entry. |
| `apply` | Makes each existing Fluxer icon (Start Menu, Desktop, taskbar) pass `--fluxer-app-url=<server>` (replacing any existing one, keeping other arguments), removes shortcuts an earlier version made, sets the `FluxerInstance` Run value, removes Fluxer's own `Fluxer.Fluxer` Run value. Safe to repeat. |
| `watch` | Opt-in (`watch_updates`). Launches like `launch`, then waits (`FileSystemWatcher`, no polling) on the folders holding Fluxer's icons; after a change settles (5 s) it runs the `apply` logic, closes Fluxer if open on another server and reopens it on yours. With `-NoLaunch` it does not open Fluxer at start (the helper that Install and `apply` start uses it, so Install never opens Fluxer by itself; the sign-in Run value does not, so login still opens Fluxer); a reopen after an update still happens. Test hook: env `FLI_TEST_WATCH_ONCE=<seconds>` skips the first launch (logs `would open Fluxer at start`, or `not opening Fluxer at start` with `-NoLaunch`), handles one change or times out, then exits. |
| `repair` | Same as `apply`, silent when nothing drifted. Runs 15 seconds after each `launch`. |
| `status` | Prints a plain summary, then dot points. Exit 0 if all is well, 1 otherwise. |
| `uninstall` | Takes only the `--fluxer-app-url` argument off the Fluxer icons removes the Run value, restores Fluxer's own `Fluxer.Fluxer` Run value from `data/state.json` and resets `watch_updates` to false. |

Options: `-DryRun` prints instead of changing; `-Yes` skips the menu's confirmation; `-AllowInsecure` permits `http://`; `-ConfigPath`, `-Root` and `-RegistryBase` redirect config, icons and registry writes (the tests use these on a throwaway key and folder). Exit codes: 0 ok, 1 status problem, 2 error, 3 settings file just created (or Fluxer running elsewhere on `launch`).

Settings live in `config/config.json` (gitignored). If it is missing the script creates it from a template built into the script; `config/config.example.json` is documentation only and no code reads it.

| Key | Default | Meaning |
|---|---|---|
| `instance_url` | `https://chat.codered.lol` | The server to open. Must be `https://`. |
| `autostart` | `true` | Open Fluxer on your instance at login. |
| `autostart_delay_seconds` | `15` | Wait before the login launch. |
| `repair_after_launch_seconds` | `15` | Run `repair` this long after `launch`; `0` turns it off. |
| `watch_updates` | `false` | When true the sign-in Run value runs `watch` (hidden) instead of `launch`. The menu Install asks once (not with `-Yes` or `apply`) and saves the answer here. Uninstall also stops a running watcher of this script. Install and `apply` also start the watcher right away (hidden) when this is true and none of this script is running; env `FLI_TEST_NO_SPAWN=1` logs `would start watcher` instead of starting it. |

Tests: `Invoke-Pester tests` (Windows PowerShell 5.1, Pester 3) and `python -m pytest tests`. The menu tests feed keys through the `FLI_TEST_KEYS` environment variable. Tests must never match or stop real processes: process matching in a sandbox (`-Root` or `FLI_TEST_NO_SPAWN=1`) is scoped to the sandbox root, so the user's real watcher is never seen or stopped.

Update test result (2026-10-04, build 2026.1003.155758): after Fluxer's in-app update, the Start Menu and taskbar icons had lost `--fluxer-app-url` (the updater recreates them), status reported both as opening the official server, and the app auto-restarted on the official server. So an update always needs a re-Install; the opt-in `watch` action is the automatic re-apply; its behaviour against a real Velopack rewrite is unverified. Old settings files that still contain `shortcut_name` keep working; the key is ignored.
