# Security Policy

Encoche runs on your Mac, receives events from other programs through a local socket, and (optionally) works with a Chrome extension. A security problem here matters, and reports are welcome.

## Supported versions

Only the latest version on the `main` branch is supported. There are no maintained older releases.

## Reporting a vulnerability

**Please do not open a public issue.** Use GitHub's private reporting: on the repository page, open **Security → Report a vulnerability**.

Include:

- what you found and where (file, function or script);
- how to reproduce it, with the macOS and Chrome versions;
- what an attacker could do with it.

This is a personal project maintained in spare time, so there is no guaranteed response time. You will get an answer, and credit in the changelog if you want it.

## What is in scope

- The Unix socket in `~/Library/Application Support/Encoche/` and the parsing of what arrives on it.
- The hook script `scripts/encoche-claude-hook.sh` and the reply channel (`replies/`).
- The native messaging host `scripts/encoche-chrome-host.py`, its installer, and the Chrome extension in `extension-chrome/`.
- The download of album artwork (only `https` addresses on `scdn.co` should be followed).
- Anything that makes the app run, read or write something you did not expect.

## Known design limits (not vulnerabilities)

- Any process running as your user can write to the local socket. The app limits message size to 64 KB and cleans displayed text, and it only displays or answers; it never executes what it receives.
- The Chrome extension needs broad permissions (`<all_urls>`, `tabs`, `scripting`) to read audible tabs and set their volume. It talks only to the local app through native messaging.
- Builds are signed ad hoc and are not notarised.

## Out of scope

Problems in macOS, Chrome, Claude Code, Spotify or Music themselves, and in the libraries listed in [NOTICE.md](NOTICE.md) (report those upstream; tell me too if Encoche is affected).
