# fluxer-instance-launcher

Small PowerShell launcher (`scripts/`) plus thin `.bat` that starts the official Fluxer desktop app with `--fluxer-app-url=<instance>`, adds its own shortcut and login autostart entry, and repairs them after Fluxer updates. Config: `config/config.json` (gitignored), example tracked. Default instance: https://chat.codered.lol (public, linked from codered.lol).

Safety: no secrets, no network calls, no admin rights, no Fluxer code or logos copied. Keep this repo free of private workspace paths and other people's names. Private until the update test passes and a scrub is done; publishing is David's decision.
