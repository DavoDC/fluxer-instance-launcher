# How it works

This page explains what the launcher does to your computer, why, and how each change is undone. For the trust question see [SECURITY.md](SECURITY.md); for the reasoning behind the design see [design-decisions.md](design-decisions.md); for contributing see [development.md](development.md).

## The one trick: a launch flag

The official Fluxer desktop app has no server picker. It does, however, understand a command-line flag:

```
Fluxer.exe --fluxer-app-url=https://chat.example.com
```

What the flag does, as read from Fluxer's public source code:

- The value must be an `http://` or `https://` address. It becomes a one-shot override for that run of the app.
- Fluxer never saves it. An older workaround (an `app_url` key in Fluxer's settings file) is deleted by current Fluxer on load, so it no longer works.
- Only the command line of the process that starts Fluxer can set it. A website or chat message cannot.
- If Fluxer is already running, a second launch hands its arguments to the running copy and exits, so the flag does nothing. That is why the launcher closes Fluxer when it is open on the wrong server.
- Fluxer treats whatever origin it was pointed at exactly like its own official site (same app features, same permissions). That is the reason for the trust advice in SECURITY.md.

Because the flag is never saved, everything that starts Fluxer has to carry it: the Start Menu icon, the Desktop icon, the taskbar pin and the start-at-login entry. That is the whole job of this tool.

## What Fluxer's own code does

These behaviours were read from Fluxer's source and observed on a real install (Windows, Velopack installer). They are why the launcher is shaped the way it is.

- Install layout: `%LOCALAPPDATA%\fluxer_desktop\` holds `Update.exe`, a small stable `Fluxer.exe` stub that forwards its arguments, and `current\` with the real app. The stub path does not change across updates.
- Start at login: Fluxer writes a value named `Fluxer.Fluxer` under `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`. Its data is the stable `Fluxer.exe` path plus `--autostart`. It writes it on first run, controlled by a marker file `autostart-initialized-v2` in Fluxer's data folder, and again whenever the Desktop settings toggle is switched on. A page on a trusted origin can also trigger it.
- Icons: Fluxer keeps `Fluxer.lnk` in the Start Menu (under a `Fluxer Platform AB` folder), on the Desktop and as a taskbar pin. It rewrites a shortcut's target if it points at the wrong place, but never touches its arguments.
- Update download: the in-app update downloads a `Fluxer-<version>-win-x64-full.nupkg` (about 160 MB) into `fluxer_desktop\packages\` (as a `.partial` file until complete), then shows a banner "Restart to finish installing". Nothing under `current\` or the icons changes until Restart is clicked.
- Updates: the Velopack updater recreates the icons without our flag, and then restarts Fluxer with an empty argument list. So after every in-app update Fluxer comes back on the official server and the icons have lost the flag. Observed on a real update: the Start Menu and taskbar icons lost the flag, status reported them as opening the official server, and the app restarted on the official server. The sign-in Run value of this tool is the one thing that survives, because Fluxer does not write it.
- The `fluxer://` link handler is rewritten by Fluxer on every launch, so any change to it is lost immediately. The launcher does not touch it.

## What Install changes (and how Uninstall reverses each item)

Install is the same logic as `apply`. It changes only the items in this table, and Uninstall reverses every row.

| Item | Install | Uninstall |
|---|---|---|
| Start Menu, Desktop and taskbar `Fluxer.lnk` (only those that exist) | Sets exactly one `--fluxer-app-url=<server>` in the icon's Arguments, replacing an existing one, dropping duplicates and keeping all other arguments. Only Arguments is written, so target, icon and Windows notification identity are kept. | Removes only the `--fluxer-app-url` argument, keeping any other arguments. |
| Run value `FluxerInstance` (under HKCU Run) | Created when `autostart` is true. Runs this script with no window (through `conhost.exe --headless`) with `launch` (or `watch` when the watcher is on) after `autostart_delay_seconds`. | Deleted. |
| Run value `Fluxer.Fluxer` (Fluxer's own) | Deleted, because it would open the official server at login. Before the first deletion its exact value and registry type are saved in `data/state.json`. An earlier saved original is never overwritten by a later "absent" reading. | Restored from `data/state.json` with its original type, then the saved copy is dropped. If nothing was saved nothing is invented. If Fluxer has meanwhile written the value again, it is left alone. |
| `watch_updates` in `config/config.json` | The menu Install asks once and saves the answer. | Reset to false (other keys stay). |
| The watcher process (opt-in) | Started with no window (headless) right after Install when `watch_updates` is true and none is running. | Stopped. Only watchers of this script are matched. |
| Legacy shortcuts `Fluxer (my instance).lnk` on Desktop and Start Menu, made by an earlier version | Deleted when they are recognised as ours (they run this script through PowerShell). A shortcut with that name that targets something else is never touched. | Same check and delete. |

The things Uninstall cannot undo, stated honestly:

- Deleting a legacy shortcut an earlier version made.
- Closing a Fluxer that was open on another server (Install and the watcher close Fluxer when it is not on your server).

The settings file `config/config.json`, the logs and `data/state.json` are the tool's own files and stay after Uninstall.

After Uninstall the status reads as it did before the first Install. This is checked by a round-trip test (see [development.md](development.md)).

## Actions

With no action the script shows the status and an arrow-key menu (Install, Uninstall, Quit). With an action it runs without any menu. The bat file only starts the script.

| Action | What it does |
|---|---|
| `launch` | Starts Fluxer with the flag. Refuses if Fluxer already runs on another server unless `-ForceRestart`. |
| `apply` | The Install logic: icons, Run values, legacy cleanup. Safe to repeat. |
| `watch` | The opt-in update watcher, described below. |
| `repair` | Same as `apply`, silent when nothing drifted. Runs 15 seconds after each `launch` (`repair_after_launch_seconds`; 0 turns it off). |
| `status` | A plain summary, then one line per item. Exit 0 when all is well, 1 otherwise. |
| `uninstall` | Reverses Install as in the table above. |

Options: `-DryRun` prints instead of changing; `-Yes` skips the menu confirmation; `-AllowInsecure` permits `http://`; `-ForceRestart`; `-NoLaunch`; `-ConfigPath`, `-Root` and `-RegistryBase` redirect the settings file, the icon folders and the registry writes (used by the tests). Exit codes: 0 ok, 1 status problem, 2 error, 3 settings file just created (or Fluxer running elsewhere on `launch`).

## The optional update watcher

Because an update strips the flag from the icons and restarts Fluxer on the official server, the only fix without the watcher is to run Install again. The watcher automates that.

- Opt-in: `watch_updates` is false by default. The menu Install asks once.
- Design: a `FileSystemWatcher` on the folders that hold Fluxer's icons, filtered to `*.lnk`. It uses no polling, so it sits idle until a shortcut changes.
- After a change it waits for the changes to settle (a 5 second debounce, because an update touches several files), then runs the `apply` logic, closes Fluxer if it is open on another server, and reopens it on yours.
- `-NoLaunch`: the helper that Install or `apply` starts does not open Fluxer when it starts, so Install never opens Fluxer by itself. The sign-in Run value does open Fluxer, because that is its purpose. A reopen after an update still happens.
- It makes no network connections and changes only Fluxer's own icons and Run values.
- Status: verified on a real Velopack update on 2026-10-05 (2026.1003.65535 to 2026.1004.13532). Timeline from that run: the updater swapped `current\` and rewrote the icons at 10:30:59 to 10:31:02; the watcher saw the icon change at 10:31:02; after the 5 second settle it restored the flag on the Start Menu and taskbar icons at 10:31:07, closed the Fluxer the updater had reopened on the official server, and reopened it on the chosen server at 10:31:09. About 7 seconds from the first icon change to Fluxer back on your server. The same watcher process survived the update, the sign-in Run value `FluxerInstance` was untouched, and Fluxer's own `Fluxer.Fluxer` Run value stayed absent. The user sees the updater window ("Installing Update"), Fluxer open briefly on the official server, close, and open again on the right server.
- Sign-in start verified on 2026-10-05 with a real Windows sign-out and sign-in (no reboot). Sign-in at 10:37:57; Windows started the `FluxerInstance` Run entry at 10:38:58 (about 60 seconds later, because Windows staggers sign-in items: Discord started at 10:38:35); the 15 second delay then ran and Fluxer opened on the chosen server at 10:39:14, about 77 seconds after sign-in in total. Fluxer was not touched by hand. The sign-out killed the old watcher without a log line, and the new watcher's log named it: `previous watcher (pid ..., log ...) ended without an exit line: killed, logoff or shutdown`. Expect about a minute and a quarter from sign-in to Fluxer appearing, not 20 seconds.

### No visible window

The sign-in entry and the helper start through `conhost.exe --headless powershell.exe ...`. The first version used `powershell -WindowStyle Hidden`, and on a PC where Windows Terminal is the default terminal host that flag is ignored: a terminal window stayed on screen for as long as the watcher ran, showing the watcher's own lines and Fluxer's log output (Fluxer inherits the watcher's console). Found on 2026-10-05 after the first real sign-in test. A probe that lists new visible windows (`EnumWindows`) showed the old form creating a Windows Terminal window and the headless form creating none. A headless console has no window, so Fluxer's inherited output has nowhere to show either. Verified on 2026-10-05: before the real sign-out and sign-in, a probe launched the exact Run value from three launchers with no console parent (`wscript`, WMI, a scheduled task) and the old form showed a window each time while the new form showed none. Then a real sign-out and sign-in: the watcher started at 11:18:03 as a child of a headless `conhost.exe`, Fluxer opened on the chosen server at 11:18:19, and no terminal window of the launcher was on screen.

## Settings

`config/config.json` is gitignored and created by the script from a template embedded in the script when missing (exit code 3 on that first creation). `config/config.example.json` is documentation only and no code reads it.

| Key | Default | Meaning |
|---|---|---|
| `instance_url` | `https://chat.codered.lol` | The server to open. Must be `https://` unless `-AllowInsecure`. |
| `autostart` | `true` | Open Fluxer on your server at login. |
| `autostart_delay_seconds` | `15` | Wait before the login launch, so it does not race the shell. |
| `repair_after_launch_seconds` | `15` | Run `repair` this long after `launch`; 0 turns it off. |
| `watch_updates` | `false` | Run the watcher instead of a plain launch at login. |

Old settings files that still contain a `shortcut_name` key keep working; the key is ignored. The URL is validated (host present, no spaces or quotes) before it is written anywhere, so quoting in registry values and shortcut arguments stays intact.

## Logging

Every run writes one file `logs/YYYY-MM-DD_HH-MM-SS_<action>.log` at the repo root, with every line timestamped. The folder is gitignored and created on first use. Logging is a side channel only: it never changes terminal output or the exit code, and a failure to write a log never breaks a run. Logs can contain the server address, so do not post them unredacted. The watcher also logs its process id at start and a `watch: stopped` line when its loop ends. A watcher killed by logoff, shutdown or Stop-Process cannot log its own end, so the next watcher to start reports any older watcher log with no exit line whose process is gone.

## Test seams (summary)

Environment variables and parameters let the tests run the real script without touching the real machine: `-Root`, `-RegistryBase`, `-ConfigPath`, `-LogDir`, `FLI_TEST_KEYS` (feeds menu keys), `FLI_TEST_NO_SPAWN=1` (log "would start watcher" instead of starting one) and `FLI_TEST_WATCH_ONCE=<seconds>` (handle one change or time out, then exit). Details in [development.md](development.md).

## Why there is no shortcut of its own

An earlier version made a custom-named shortcut. It was dropped: patching Fluxer's own icons means the icons people already know and click work, there is nothing new to find, and Uninstall can put them back instead of leaving clutter. See [design-decisions.md](design-decisions.md).

## Known limits and accepted exceptions

- Every Fluxer update undoes the icon patch and restarts Fluxer on the official server. Without the watcher, run Install again; the status at the top of the menu tells you.
- After an update there is a short flash: Fluxer reopens on the official server for a few seconds before the watcher closes it and reopens it on yours (observed live, see the watcher section). The first window cannot be avoided because the updater starts it before the watcher can act.
- Whether Fluxer's own sign-in value was on before Install cannot be known if Install ran before state saving existed; in that case Uninstall leaves it as it is and invents nothing.
- Windows only. The tool needs Windows PowerShell 5.1, which ships with Windows 10 and 11. No administrator rights are needed.
- Not tested: whether a crafted `fluxer://` link can inject extra launch options while Fluxer is closed. That would affect every Fluxer user with or without this tool, which is why the tool does not touch the handler.
