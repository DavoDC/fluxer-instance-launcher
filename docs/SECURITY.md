# Is this safe to use?

Yes. The launcher is small, does one job, and leaves Fluxer itself untouched. It is unofficial and not affiliated with the Fluxer project.

## Why it is safe

- It starts the official Fluxer app with one extra setting: which server to open. It never changes, patches or adds code to Fluxer.
- It needs no administrator rights.
- It makes no network connections.
- It never reads or stores your passwords or tokens.
- It installs no background service.
- It adds only a shortcut and a start-at-login entry, both named after the launcher. Pick Uninstall in the setup menu and they are gone.
- Its status check shows every item it manages, so you can see exactly what is in place.

## You choose the server

You pick the server on your own computer before the app starts. A website or a chat message cannot change it, and Fluxer does not store it. Use a server run by someone you know and trust, and use an `https://` address (the launcher refuses plain `http://`). A public example is https://chat.codered.lol.

## After a Fluxer update

Fluxer updates itself from its own update server, which the server you connect to has no part in. After an update, run `Fluxer Instance Setup.bat` and pick Install again, then open Fluxer from the launcher's shortcut. Until you do, Fluxer may open on the official server.
