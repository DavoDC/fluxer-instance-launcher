# Is this safe to use?

Short answer: yes, for a server run by someone you trust. This page says what the launcher does, what it cannot do, and the one decision that matters. It is unofficial and not affiliated with the Fluxer project.

## What the launcher does

It starts the official Fluxer app with one extra setting: which server to open. It does not change, patch or add code to Fluxer.

- It makes its own shortcut and its own start-at-login entry, named `FluxerInstance`.
- It switches off Fluxer's own start-at-login entry, so the two do not fight.
- It needs no administrator rights, makes no network connections, and never reads or stores passwords or tokens.
- It installs no background service. Pick Uninstall in the setup menu and everything it made is removed.
- The `fluxer://` link handler is only touched if you switch that on, and it is off by default.

You do not have to take my word for it. The script is short and readable, and you can check the result in a minute:

1. Open `scripts/fluxer-instance-launcher.ps1`. Search it for `Invoke-WebRequest`, `WebClient`, `iex` or `FromBase64String`. There are none.
2. Right-click the shortcut, choose Properties, and read the Target.
3. Run `Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` and look at the `FluxerInstance` line.
4. Double-click `scripts\Fluxer Instance Setup.bat` and pick Status any time to see every entry and whether it is in place.

## The one decision: do you trust the server's owner?

When the app opens a server, that server's web page runs inside the app with the same abilities Fluxer's own server gets. That means features like reading your clipboard, push-to-talk key detection, and camera, microphone and screen sharing work without a separate pop-up. A normal browser tab would ask first.

So using a friend's server instead of Fluxer's own just moves your trust from the Fluxer company to that friend. The app has no feature that lets a server run programs on your computer or browse your files.

- Pick a server whose owner you know. Public example: https://chat.codered.lol.
- Only use `https://` addresses. The launcher refuses plain `http://` unless you override it.
- For a server you do not know, use it in a normal browser tab instead. That is the safest option.

Fluxer's developers have said a general "connect to any server" button would be risky for exactly this reason (https://github.com/fluxerapp/fluxer/issues/1088#issuecomment-5562235766). This launcher is not that button: you choose the server yourself, on your own computer, before the app starts. A website or a chat message cannot change it, and Fluxer does not store it.

## Updates

Fluxer updates itself from its own update server. The server you connect to has no part in that. After an update Fluxer may reopen on the official server until you start it from the launcher's shortcut again. That only loses your custom server; it never moves you to a different one.

## Simple habits

1. Keep Fluxer and Windows up to date.
2. Do not copy passwords while the app is open on a server you do not fully trust.
3. Leave push-to-talk key bindings off unless you use them.
4. Leave the `fluxer://` handler option off unless you need it, and do not click `fluxer://` links from untrusted pages while Fluxer is closed.

## Honest limits

I read Fluxer's source code and checked an installed copy, but did not test everything:

- Whether a crafted `fluxer://` link can add extra options when Fluxer is closed. This would affect every Fluxer user with or without this tool, which is why the handler option is off by default.
- Whether the web client escapes all chat content.
- Whether the launcher's shortcut and start-up entry survive a real Fluxer update. The README's developer section says what is still to test.

## Reporting

Problems with this launcher: open an issue in this repository. Security problems in Fluxer itself: report them to the Fluxer project. The launcher receives and stores none of your data.
