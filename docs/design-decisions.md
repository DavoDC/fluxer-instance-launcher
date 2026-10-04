# Design decisions

Each decision below lists what was chosen, what was rejected and why. For the mechanics see [how-it-works.md](how-it-works.md).

## Patch Fluxer's own icons, do not make our own shortcut

Chosen: set the `--fluxer-app-url` argument on Fluxer's existing Start Menu, Desktop and taskbar icons.

Rejected: a custom-named shortcut of our own. The first design relied on Fluxer's repair code only touching a shortcut named `Fluxer.lnk`, so a differently named one would survive. It was dropped because people click the icons they already have (the taskbar pin especially), a second icon is confusing, and Uninstall can cleanly restore an argument but would have to delete icons it made. Cost accepted: Fluxer's updater recreates its icons, so an update strips the flag (handled by re-running Install or the opt-in watcher).

## Opt-in watcher, not a scheduled task

Chosen: an optional hidden helper using `FileSystemWatcher`, started from the sign-in Run value, off by default.

Rejected: a scheduled task that runs `repair` at logon. A logon task runs once, but updates happen while the user is signed in, and the restart after an update happens at once. A watcher reacts when the icons change and can reopen Fluxer on your server. A task would also be another thing to install and remove, and it needs more trust from a cautious user. The watcher is opt-in because it is a background process, and the menu asks once. Polling was rejected: `FileSystemWatcher` is idle until something changes, and a 5 second debounce lets an update finish touching files before the tool acts.

## Do not patch the `fluxer://` handler

Chosen: leave the link handler alone.

Rejected: adding the flag to `HKCU\Software\Classes\fluxer\shell\open\command`. Fluxer rewrites that value on every launch, so the patch is lost immediately; it only matters when Fluxer is closed and a link is clicked; and writing launch arguments into a handler that receives untrusted link text raises an unproven argument-injection question. An earlier plan made it an opt-in switch, and it was removed entirely to keep the tool small and the safety claim simple.

## Remove Fluxer's own sign-in value, and save it first

Chosen: Install deletes Fluxer's own `Fluxer.Fluxer` Run value (it would open the official server at login and fight our own entry) after saving its exact value and type; Uninstall restores it.

Rejected: leaving both entries (they race), and deleting without saving. The deletion without saving was an actual early mistake: the original value could not be restored. The saved copy is never overwritten by a later "absent" reading, and Uninstall invents nothing when nothing was saved. Fluxer can re-enable its value (the settings toggle, or a page on a trusted origin), so `repair` deletes it again each run.

## Uninstall reverses everything, in the same commit

Chosen: Install and Uninstall are designed as a pair, guarded by a round-trip test. See the engineering rule in [development.md](development.md).

## No network code, no admin rights, no secrets

Chosen: the script makes no network calls, needs no administrator rights, stores no passwords or tokens, and installs no service. A test fails the build if network cmdlets appear in the script. This keeps "read it yourself" true: the script is one file a curious person can search for downloads or hidden code. The same reasoning applies to the size: it stays small enough to read.

Rejected: any update check or telemetry. The `http://` scheme is refused unless `-AllowInsecure` is given, because Fluxer accepts `http:` but a plain-text server address is a bad default.

## Settings in JSON, created from an embedded template

Chosen: `config/config.json` is gitignored and created by the script from a template embedded in the script when missing. `config/config.example.json` is documentation only and no code reads it, so the example file can never silently override a real setting or drift into being a second source of truth. Environment files were rejected in favour of JSON in a `config/` folder.

## PowerShell 5.1

Chosen: Windows PowerShell 5.1, which ships with Windows 10 and 11, so friends need to install nothing. The tests use Pester 3, which ships with the same Windows. Rejected: PowerShell 7 (an install), Python (an install and a heavier "what is this" for a non-technical user), a compiled binary (not readable by the user).

## Terminal design is fixed

The menu, status text and Install and Uninstall output are deliberately plain, short and stable, aimed at non-technical users. They change only on the repo owner's explicit decision, so docs and screenshots stay true.

## Licence and Fluxer's code

Chosen: MIT. Fluxer is AGPL-3.0-or-later; this tool only starts a locally installed Fluxer with a command-line flag and edits shortcut and registry entries. It copies no Fluxer code, ships no Fluxer binaries, assets or logos, and does not link against Fluxer, so the AGPL obligations that attach to distributing or serving Fluxer do not apply to this separate script. Naming the flag is documenting a public interface. "Fluxer" is used descriptively only, with a non-affiliation line, and no Fluxer logo is used. If this tool ever bundled a modified Fluxer the analysis would change completely, so that is out of scope.

## Default server

The tracked default is https://chat.codered.lol, a public instance whose owner links it publicly. Documentation about other instances uses a generic example address. Users replace the default in their own gitignored settings file.

## Prior art, in neutral terms

Other tools for pointing Fluxer at a custom server exist. In brief (README-level survey of public repositories, not audited, none endorsed):

- A Tauri launcher that stores several servers and starts Fluxer with the flag (no licence file at the time of the survey).
- An Electron wrapper with multi-account support (a different client, not the official app).
- A modified Fluxer client carrying a server picker (AGPL, tested against an older build).
- A minimal Electron shell and a couple of placeholder repositories.

None of the READMEs read described repairing the setup after a Fluxer update. This tool's niche is therefore narrow: keep the unmodified official app on one server, survive updates, undo itself cleanly, and explain the trust question in plain language. Anyone who wants a multi-server switcher or a modified client should look at the tools above.

## Relationship with Fluxer's own plans

Fluxer's developers have said a general "connect to any server" button would need a trust model, because the app gives the server it opens the same abilities as the official one, and that a new multi-account client architecture is in progress. This tool adds no such button, changes nothing inside Fluxer and is meant for servers the user already trusts. The public discussion is at https://github.com/fluxerapp/fluxer/issues/1088. If Fluxer ships official support, uninstall this tool.
