# Contributing to Encoche

Thanks for helping. Issues and pull requests are welcome, in English or French.

## Before you start

- For a bug, search the existing issues first, then open one with the template.
- For a new feature, open an issue to talk about it before writing code. Encoche is deliberately small: the notch panel shows things and answers simple questions, it does not run what it receives.
- By contributing, you agree that your contribution is released under the [MIT License](LICENSE).

## Set up

You need macOS 14 or later and Swift 6.2 or later (Xcode 26 or its Command Line Tools; check with `swift --version`).

```bash
git clone https://github.com/yanmwisa/encoche.git
cd encoche
./scripts/build-app.sh
open build/NotchDrop.app
```

To work in Xcode instead: `open NotchDrop.xcodeproj`.

## Check your change

Run the check scripts that cover what you touched. They need only the Command Line Tools and write to a throwaway `HOME`:

```bash
./scripts/check-sessions.sh          # the model of sessions and requests
./scripts/check-sessions-server.sh   # the Unix socket server
./scripts/check-browser-bridge.sh    # the Chrome bridge
./scripts/check-chrome-install.sh    # the bridge installer
./Checks/hook/check-hook.sh          # the Claude Code hook script
```

A new behaviour comes with a check in the matching `Checks/` file. A bug fix comes with a check that fails without the fix.

## Code style

- Swift follows [AGENTS.md](AGENTS.md) (inherited from NotchDrop): early returns, `guard` for optionals, value types, `@Observable`, Swift concurrency.
- Keep the decision logic in plain functions that import only Foundation (like `SessionModel.swift`), so the check scripts can test it without the app.
- Do not log message contents, file names or anything a session sent you.
- Comments in French or English are both fine.

## Decisions that last

A choice that is hard to undo (a new channel, a new permission, a new dependency) gets a short note in `docs/adr/`, numbered after the last one. Say what you chose, what you rejected, and why.

## Pull requests

- One subject per pull request.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat(sessions): …`, `fix(player): …`. The body says why, not how.
- Fill in the pull request template, and say what you tested and what you could not.
- Keep the Spotify, Apple, Google and GitHub names and logos for nominative use only.

## Credits

Encoche is built on [NotchDrop](https://github.com/Lakr233/NotchDrop). Changes that are not specific to Encoche (the notch window, the file shelf) are best sent to NotchDrop first.
