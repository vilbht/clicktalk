# Changelog

All notable changes to EucLink are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The download steps explain why macOS blocks the first launch, and add the Open Anyway
  route for people who do not use Terminal.

## [0.4.0] - 2026-11-22

### Added

- Uninstall from inside the app: General > Uninstall… removes the login item, settings, seal
  key and permissions, and moves the app to the Trash.
- `uninstall.sh` also deletes the seal key and any saved window state or caches.

### Changed

- The three README animations run together at full brightness, joined by arrows.
- The download steps say how to open Terminal for the one-time quarantine command.

## [0.3.0] - 2026-11-22

### Changed

- New name: EucLink. The bundle identifier is now `local.euclink` and the signing
  certificate is "EucLink Dev". macOS treats it as a new app, so run the setup guide once more.
- The README shows the EucLink logo and three animations in a row: Pair, Tap, Talk.

### Added

- A pre-built app for Apple silicon on each GitHub Release.
- Tests for keystroke parsing and naming, run by `./build.sh ci`.
- Continuous integration that builds the app and runs the tests on every push and pull request.
- Contributing guide, code of conduct, security policy, and issue and pull request templates.

## [0.2.0] - 2026-11-22

### Added

- EucLink holds the Bluetooth button itself and runs actions directly, so Karabiner-Elements
  is no longer needed.
- Actions: keystroke (press or hold for push-to-talk), toggle or open an app, run a Shortcut,
  open a link, run a command.
- A settings window and a nine-step setup guide that checks each permission.
- Settings sealed with a keychain key, so bindings changed outside the app do not run.
- Only the chosen Bluetooth button is opened.
- Hardened runtime signing and `make-cert.sh` for a stable signing identity.
- `uninstall.sh`.

## [0.1.0] - 2026-11-22

### Added

- A menu bar app that watched a Bluetooth button and its Karabiner-Elements path, and
  showed which part failed.
