# fluxer-instance-launcher

A small PowerShell tool for non-technical Windows users: it makes the official Fluxer desktop app open on a chosen server and keeps it there. People double-click `scripts/Fluxer Instance Setup.bat` and see the status and pick Install, Uninstall or Quit from a menu. The logic is in `scripts/fluxer-instance-launcher.ps1`. Default server: https://chat.codered.lol.

How Claude verifies: run `Invoke-Pester tests` and `python -m pytest tests`, then do the dry run and the real apply yourself (`scripts\fluxer-instance-launcher.ps1 apply -DryRun`, then `apply -Yes`, then `status`). Never ask the user to run a dry run or pass arguments; the user only double-clicks the bat.

Rules: `config/config.json` is gitignored and created by the script from an embedded template when missing; `config/config.example.json` is documentation only and no code may read it. No secrets, no network calls, no admin rights, no Fluxer code or logos copied. Keep this repo free of private workspace paths and other people's names. Private until a scrub is done; publishing is David's decision.
