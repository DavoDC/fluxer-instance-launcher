# Development

How to work on the launcher safely. For behaviour see [how-it-works.md](how-it-works.md) and for the reasoning [design-decisions.md](design-decisions.md).

## Running the tests

Both suites must pass before a commit.

```
Invoke-Pester tests
python -m pytest tests
```

- `Invoke-Pester tests` runs `tests/fluxer-instance-launcher.Tests.ps1` on Windows PowerShell 5.1 with Pester 3 (the version that ships with Windows). It runs the real script against a throwaway folder and a throwaway registry key.
- `python -m pytest tests` runs `tests/test_no_absolute_user_paths.py`, which fails if any tracked file contains an absolute drive-letter user-folder path. Use `%LOCALAPPDATA%` style or repo-relative paths in docs.
- Passing output should stay quiet and a failure should name the file and line.

## Test seams

The script exposes seams so tests exercise real code without touching the machine:

| Seam | Effect |
|---|---|
| `-Root <folder>` | Redirects Desktop, Start Menu, taskbar and LocalAppData (and `data/state.json`) into the folder. |
| `-RegistryBase <key>` | Redirects registry writes to a throwaway key instead of the real HKCU Software key. |
| `-ConfigPath <file>` | Uses a test settings file. |
| `-LogDir <folder>` | Writes logs into a test folder, never the real `logs/`. |
| `-FluxerExe <file>` | Points at a stand-in Fluxer executable. |
| `-DryRun` | Prints what would change, changes nothing. |
| `FLI_TEST_KEYS=Down,Enter,Y` | Feeds the menu keys instead of the keyboard (Up, Down, Enter, Esc, Y, N). |
| `FLI_TEST_NO_SPAWN=1` | Logs `would start watcher` instead of starting a process. |
| `FLI_TEST_WATCH_ONCE=<seconds>` | The watcher skips the first launch, handles one change or times out, then exits. |

Add a seam when a new behaviour cannot be exercised otherwise, and keep it inert unless set.

## Sandbox rules

- A test never writes the real registry Run key, real icons, the real `config/config.json` or the real `logs/` folder. Use the seams above.
- Prove isolation, not only success: after a run compare the real state before and after where it matters.
- Real-machine checks (a dry run, then a real apply, then status) are done by the developer by hand, never inside the suite.

## Rule: Install and Uninstall are a pair

Uninstall must undo everything Install did, so after Uninstall the status reads as it did before the first Install. A change to Install changes Uninstall in the same commit.

- When writing Install, list every registry value, file, config key and process it touches. For each, write the save step, the Uninstall step and a test.
- Anything Install deletes or overwrites is saved first, with its exact value and type, in the gitignored `data/state.json`. An earlier saved original is never overwritten by a later "absent" reading. If nothing was saved Uninstall invents nothing.
- The round-trip test installs and uninstalls in a sandbox and compares registry values, every icon's Arguments and `watch_updates` before and after.
- Honest exceptions are written in the repo's orientation file and in how-it-works.md, never silent (today: deleting a legacy shortcut and closing a running Fluxer).
- A helper that Install starts does only the watching: it is started with `-NoLaunch`, and the sign-in value alone opens the app. Test both command lines.
- Real-machine proof comes from a before and after dump of the real state, not only the sandbox suite.

Why the rule exists: an early Install deleted Fluxer's own sign-in value without saving it, so Uninstall could not restore it, and Install left the watcher setting on so status after Uninstall did not match status before Install. A started helper also opened Fluxer at an unexpected moment.

## Rule: tests never touch real processes

Any code path that finds or stops processes (the watcher, a helper, Fluxer) must take its scope from the sandbox root in tests, so a test run cannot see or stop the real process.

- In a sandbox (`-Root` or `FLI_TEST_NO_SPAWN=1`) process matching is scoped to the sandbox root; with the no-spawn seam and no root it matches nothing.
- Prove it with a decoy: start a harmless process with the real script's command line and assert it survives a sandboxed Uninstall.
- Before running a suite that touches process matching, check the real process is out of scope, and record its process id before and after the run; it must not change.
- Never run a known-red test whose failure mode is destroying real state. Skip it and prove the fix another way.

Why the rule exists: an early Uninstall test matched processes by the real script path and stopped a real running watcher during a suite run.

## Other engineering rules

- Public repo: no workspace paths, private tool names, other people's names or personal details in any tracked file. Use `%LOCALAPPDATA%` style paths.
- No em or en dashes in docs. One paragraph per line in markdown.
- README, code and tests change in the same commit.
- Logging uses `Write-Log` only and never affects output or exit codes.
- No secrets, no network calls, no administrator rights, no copied Fluxer code or logos.
- The terminal design is locked: change it only with the repo owner's explicit approval.
