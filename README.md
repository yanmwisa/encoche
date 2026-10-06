# Encoche

**Your MacBook's notch, put to work: Claude Code sessions, a music player and a file shelf, one hover away.**

Encoche is a macOS app that lives in the notch. Open it and you get a small panel with three screens:

| Screen | What it does |
| --- | --- |
| **Sessions** | Shows every running [Claude Code](https://claude.com/product/claude-code) session: working, waiting for an answer, or done. Answer a permission request (allow or deny) without leaving what you are doing, and jump to the session (it opens in the Claude desktop app when it can). |
| **Player** | The track playing in Music or Spotify with previous, pause and next. Mac volume, and the volume of each audible Chrome tab (with the optional extension). |
| **Files** | A drop shelf: drag a file to the notch, take it out later, open AirDrop from the notch. Files are removed after one day by default. |

Encoche is a fork of [NotchDrop](https://github.com/Lakr233/NotchDrop) by Lakr233, which provides the notch window and the file shelf. The Sessions and Player screens, the Chrome bridge and the notification card are added here. See [Credits](#credits).

<!-- TODO before publishing: add a screenshot or a short GIF of each screen in docs/images/ and show them here. -->

## Requirements

- macOS 14 (Sonoma) or later
- A MacBook with a notch is what it is designed for. Behaviour on other Macs has not been tested.
- To build: Swift 6.2 or later, that is Xcode 26 or the Command Line Tools for Xcode 26 (`xcode-select --install`). Check with `swift --version`. Full Xcode is optional. One library, swift-collections 1.3.0, refuses older versions.

## Install

There are no pre-built releases yet: a downloadable app needs an Apple Developer ID and notarisation, which this project does not have. Build it yourself; it takes about a minute.

```bash
git clone https://github.com/yanmwisa/encoche.git
cd encoche
./scripts/build-app.sh
open build/NotchDrop.app
```

The binary is still named `NotchDrop` while the project is called Encoche. The app is signed ad hoc, which is enough to run on the Mac that built it. macOS will ask for the permissions it needs the first time (see [Privacy and security](#privacy-and-security)).

To build with Xcode instead: `open NotchDrop.xcodeproj`, then run (⌘R). A build with Xcode also includes the translations (English, French, German, Japanese, Simplified and Traditional Chinese); the command-line build is English only.

To see the notification card with fake data: `open build/NotchDrop.app --args --demo-notifications`.

## Connect Claude Code (optional)

The Sessions screen is fed by [Claude Code hooks](https://docs.claude.com/en/docs/claude-code/hooks). A small shell script receives each event and passes it to the app over a local Unix socket. It never makes a Claude Code event fail: it always exits with 0, and returns at once when the app is closed. It only waits when the app is open and Claude Code asks for a permission: up to 60 seconds for your answer (10 minutes for offered steps), after which Claude Code asks you as usual.

1. Copy the script where the hook configuration below expects it:

   ```bash
   mkdir -p "$HOME/Library/Application Support/Encoche"
   cp scripts/encoche-claude-hook.sh "$HOME/Library/Application Support/Encoche/"
   ```

2. Add the hooks to `~/.claude/settings.json`. **Back the file up first**, and merge these entries with your existing `hooks` rather than replacing them:

   ```json
   {
     "hooks": {
       "SessionStart": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "/bin/sh -c 'F=\"$HOME/Library/Application Support/Encoche/encoche-claude-hook.sh\"; [ -f \"$F\" ] && exec /bin/sh \"$F\"; exit 0'",
               "timeout": 5
             }
           ]
         }
       ],
       "UserPromptSubmit": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "/bin/sh -c 'F=\"$HOME/Library/Application Support/Encoche/encoche-claude-hook.sh\"; [ -f \"$F\" ] && exec /bin/sh \"$F\"; exit 0'",
               "timeout": 5
             }
           ]
         }
       ],
       "PermissionRequest": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "/bin/sh -c 'F=\"$HOME/Library/Application Support/Encoche/encoche-claude-hook.sh\"; [ -f \"$F\" ] && exec /bin/sh \"$F\"; exit 0'",
               "timeout": 65
             }
           ]
         }
       ],
       "Notification": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "/bin/sh -c 'F=\"$HOME/Library/Application Support/Encoche/encoche-claude-hook.sh\"; [ -f \"$F\" ] && exec /bin/sh \"$F\"; exit 0'",
               "timeout": 5
             }
           ]
         }
       ],
       "PostToolUse": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "/bin/sh -c 'F=\"$HOME/Library/Application Support/Encoche/encoche-claude-hook.sh\"; [ -f \"$F\" ] && exec /bin/sh \"$F\"; exit 0'",
               "timeout": 5
             }
           ]
         }
       ],
       "Stop": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "/bin/sh -c 'F=\"$HOME/Library/Application Support/Encoche/encoche-claude-hook.sh\"; [ -f \"$F\" ] && exec /bin/sh \"$F\"; exit 0'",
               "timeout": 5
             }
           ]
         }
       ],
       "SessionEnd": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "/bin/sh -c 'F=\"$HOME/Library/Application Support/Encoche/encoche-claude-hook.sh\"; [ -f \"$F\" ] && exec /bin/sh \"$F\"; exit 0'",
               "timeout": 5
             }
           ]
         }
       ]
     }
   }
   ```

3. Start a new Claude Code session. It shows up in the Sessions screen.

Hooks run commands on your machine with your permissions. Read `scripts/encoche-claude-hook.sh` before you install it; it is about 70 lines.

### Offering next steps from your own tool

A tool can send the event `NextSteps` to the same hook, with a list of `items` (each with a `label`). Encoche shows them in the Sessions screen, and the hook prints the numbers you picked (for example `2,0`) on its standard output. The tool then decides what to do with them; Encoche never sees or runs the text of a step. The event format is exercised in `Checks/Sessions/main.swift` and `Checks/hook/check-hook.sh`.

The published [next-steps-sequence](https://github.com/yanmwisa/claude-code-plugins) plugin does **not** send this event.

## Volume of Chrome tabs (optional)

A Chrome extension reports which tabs are playing sound, and applies the volume you set in the Player screen. It talks to the app through Chrome's native messaging, on your Mac only.

```bash
./scripts/install-chrome-bridge.sh
```

Then, in Chrome: Extensions → turn on Developer mode → *Load unpacked* → choose the `extension-chrome` folder.

The extension asks for broad permissions: it reads tab information, and its script runs in every page (`<all_urls>`) to change the media volume. It sends nothing over the network. Read it before you load it: it is three small files in `extension-chrome/` (about 170 lines in total).

## Privacy and security

- **No telemetry, no account.** The app's only network request is the download of album artwork from Spotify's image network (`scdn.co`, HTTPS only, 5 MB at most) when Spotify is playing. Any other address is refused.
- **Local channels.** Events arrive on a Unix socket in `~/Library/Application Support/Encoche/` (folder `0700`, socket `0600`); each message is limited to 64 KB and the displayed text is cleaned. Any process running as you can write to that socket, which is why the app only displays and never executes what it receives.
- **Read-only access to Claude sessions.** To open the right session, the app reads the list in `~/Library/Application Support/Claude/claude-code-sessions` and never writes to it.
- **Automation.** macOS will ask whether Encoche may control Music and Spotify, to read the current track and send previous, pause and next.
- Found a security problem? See [SECURITY.md](SECURITY.md).

## Tests

The model of sessions, the socket server, the hook script, the Chrome bridge and the installer each have a check script that needs only the Command Line Tools:

```bash
./scripts/check-sessions.sh
./scripts/check-sessions-server.sh
./scripts/check-browser-bridge.sh
./scripts/check-chrome-install.sh
./Checks/hook/check-hook.sh
```

They use a throwaway `HOME` where they write, so they do not touch your real configuration. Run them with `HOME=$(mktemp -d)` in front to be sure.

## Known limitations

- Sessions: only Claude Code is detected. ChatGPT and other assistants do not send readable events.
- The code comments and the architecture notes in `docs/adr/` are written in French.
- The app and binary keep the name NotchDrop.
- No pre-built releases and no auto-update.

## Contributing

Issues and pull requests are welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). Please read the [Code of Conduct](CODE_OF_CONDUCT.md).

## Credits

- [NotchDrop](https://github.com/Lakr233/NotchDrop) by Lakr Aream (MIT): the notch window, the file shelf and the foundation of this app. Encoche would not exist without it. Encoche is **not** affiliated with it or with its App Store app.
- NotchDrop itself credits [NotchNook](https://lo.cafe/notchnook) as its initial inspiration.
- Libraries: see [NOTICE.md](NOTICE.md).
- Spotify, Apple Music and Chrome are trademarks of their owners. Encoche is not affiliated with them.

## License

[MIT](LICENSE). Copyright © 2024 Lakr Aream, © 2026 Yannick (yanmwisa). Third-party licenses: [NOTICE.md](NOTICE.md).
