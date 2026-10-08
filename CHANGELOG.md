# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

First public release of Encoche, a fork of [NotchDrop](https://github.com/Lakr233/NotchDrop) 2.16.

### Added

- **Sessions** screen: Claude Code sessions (working, waiting, done) fed by hooks over a local Unix socket, with permission answers (allow or deny) from the notch and a jump to the session.
- **Player** screen: current track from Music and Spotify with previous, pause and next; Mac volume; album artwork from Spotify's image network (`scdn.co`, HTTPS only).
- Optional Chrome extension and native messaging host to set the volume of audible tabs.
- Notification card, with `--demo-notifications` to preview it.
- Optional `NextSteps` event to offer steps from another tool.
- Build without Xcode: `scripts/build-app.sh` (Swift Package Manager and the Command Line Tools only).
- Check scripts for the sessions model, the socket server, the Chrome bridge, its installer and the hook script.
- `NOTICE.md` with the licenses of the libraries, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`.

### Changed

- Bundle identifier is now `io.github.yanmwisa.encoche` (NotchDrop's own identifier belongs to its App Store app).
- The README describes Encoche. The App Store badge, the sponsor link and the screenshot of the original app were removed.

### Fixed

- The app built by `scripts/build-app.sh` crashed at launch once its `.build` folder was moved or deleted: Pow's poof transition loads images from `Pow_Pow.bundle`, which Pow only looks for at the root of the app, a place code signing refuses. A tray item now leaves with a fade and scale, and `scripts/check-library-resources.sh` fails the CI if a Pow effect that loads that bundle (poof, anvil, smoke) comes back.

### Removed

- Unused links to NotchDrop's product and sponsor pages in `NotchDrop/main.swift`.
