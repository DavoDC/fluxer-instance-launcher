# Is this safe to use?

Yes. The launcher is small, does one job, and leaves Fluxer itself untouched. It is unofficial and not affiliated with the Fluxer project.

## Why it is safe

- It starts the official Fluxer app with one extra setting: which server to open. It never changes, patches or adds code to Fluxer.
- It needs no administrator rights.
- It makes no network connections.
- It never reads or stores your passwords or tokens.
- It installs no background service.
- It changes only the server setting on Fluxer's own icons (Start Menu, Desktop, taskbar) and adds one start-at-login entry named after the launcher. It creates no shortcut of its own. Pick Uninstall in the setup menu and it takes the setting off the icons and removes the entry.
- Its status check shows every item it manages, so you can see exactly what is in place.

## You choose the server

You pick the server on your own computer before the app starts. A website or a chat message cannot change it, and Fluxer does not store it. Use a server run by someone you know and trust, and use an `https://` address (the launcher refuses plain `http://`). A public example is https://chat.codered.lol.

## How this fits with Fluxer's plans

Fluxer's developers have said that a built-in "connect to any server" button would need careful design, because the app trusts whichever server it opens ([the discussion](https://github.com/fluxerapp/fluxer/issues/1088#issuecomment-5562235766)). This launcher respects that. It adds no such button and changes nothing inside Fluxer. You choose the server yourself, on your own computer, before the app starts, and only servers you know and trust belong there. If Fluxer adds official support for custom servers later, you can uninstall the launcher and switch over.

## After a Fluxer update

Fluxer updates itself from its own update server, which the server you connect to has no part in. After an update, run `Fluxer Instance Setup.bat` and pick Install again, then open Fluxer from its normal icon. Until you do, Fluxer may open on the official server instead.
