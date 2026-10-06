## What and why

<!-- One subject. Say why the change is needed, not how it works. -->

## Tested

<!-- Which check scripts you ran, and what you tried by hand. -->

- [ ] `./scripts/check-sessions.sh`
- [ ] `./scripts/check-sessions-server.sh`
- [ ] `./scripts/check-browser-bridge.sh`
- [ ] `./scripts/check-chrome-install.sh`
- [ ] `./Checks/hook/check-hook.sh`
- [ ] `./scripts/build-app.sh` builds

## Not tested

<!-- Be honest: what you could not check (other macOS versions, Chrome, Spotify...). -->

## Checklist

- [ ] No secret, personal path or private data in the diff
- [ ] A new behaviour has a check; a fix has a check that fails without it
- [ ] README or CHANGELOG updated if the behaviour changed
