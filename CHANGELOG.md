# Changelog

All notable changes to EucLink are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- After updating in place, macOS asked for the login keychain password so the new build could
  read the key that seals your settings. EucLink no longer triggers that prompt. It starts a
  new key instead, and asks you once to choose your button and approve your bindings again.

## [0.4.10] - 2026-11-22

### Fixed

- EucLink 0.4.8 and 0.4.9 crashed at launch when Bluetooth was allowed and a Bluetooth device
  was connected. Signing up for connection notices made macOS report each connected device at
  once, and each report signed up again, without end. EucLink now signs up exactly once and
  handles the reports afterwards.

## [0.4.9] - 2026-11-22

### Fixed

- Dragging the EucLink icon from the guide into a System Settings privacy list did nothing,
  while dragging the app from Finder worked. The tile now sends the app exactly as Finder
  does, and takes the first click even while System Settings is in front.

### Added

- A Permissions section in the README: why each permission is needed and on which step, an
  animation of dragging EucLink into the list, and what to do when a switch is on but ignored.

## [0.4.8] - 2026-11-22

### Fixed

- macOS asked for Bluetooth as soon as EucLink started, before the setup guide had explained
  why. EucLink now makes no Bluetooth calls until you click Allow Bluetooth on the guide's
  Bluetooth step.
- Choosing your button on step 3 could make macOS ask for Input Monitoring a step early.
  EucLink now waits to take hold of the button until you click Allow Input Monitoring, so
  each permission is asked for on its own screen.

## [0.4.7] - 2026-11-22

### Changed

- The drag-to-add picture is animated: the hand cursor grabs the EucLink icon, carries it to
  the empty slot in the System Settings list, and lets go.
- In that picture the System Settings list shows an empty Drop EucLink here slot instead of
  EucLink already in place.
- The README's steps 4 and 7 describe the drag-to-add and + routes.

## [0.4.6] - 2026-11-22

### Changed

- The Input Monitoring and Accessibility steps are more visual. If EucLink is missing from
  the list in System Settings, drag the EucLink icon from the guide straight into the list.
  The drawing also marks the + button as the other way in.

## [0.4.5] - 2026-11-22

### Fixed

- After a permission reset, System Settings kept showing EucLink switched on, because it
  does not refresh while open. Reset now quits System Settings first, so the list is current
  when EucLink reopens it.
- If macOS refuses a reset, EucLink says so and offers the Terminal command, instead of
  restarting as if it had worked.
- A reset cannot clear an Input Monitoring entry that was added by hand with +, because macOS
  stores it by the app's location. EucLink now notices when Input Monitoring stays on after a
  reset and says to remove the entry with − in System Settings.

## [0.4.4] - 2026-11-22

### Fixed

- Copy to Applications failed with "no such file" when EucLink was opened straight from the
  disk image. macOS runs such an app from a hidden temporary copy; EucLink now finds the
  original, copies that, and opens the copy without a second warning. If the disk image is
  already closed, it says how to drag EucLink into Applications instead.
- The welcome step explains this case in plain words instead of showing the temporary path.

### Changed

- The disk image window says to open EucLink from Applications, not from the window.

## [0.4.3] - 2026-11-22

### Fixed

- EucLink was sometimes missing from the Input Monitoring list, so people had to add it with +.
  Allow Input Monitoring now always asks macOS, in every way macOS records, then opens the list.
- The disk image window cut off its bottom row.

### Changed

- After Reset and Try Again, EucLink asks for the permission by itself after it restarts.
- Once Input Monitoring is on, the guide restarts EucLink by itself.
- The disk image window shows the three first-launch steps: Done, Privacy & Security,
  Open Anyway. The README shows the same picture.

## [0.4.2] - 2026-11-22

### Added

- Reset and Try Again on the guide's permission steps. When macOS shows EucLink as allowed
  but ignores it, because the switch belongs to another copy of the app, one click clears the
  entry and restarts EucLink so it can ask again.
- Permissions page: Reset Permissions and Relaunch replaces the three Terminal commands.

## [0.4.1] - 2026-11-22

### Added

- A disk image next to the zip on each release. It opens to a window that shows where to
  drag EucLink and how to get past the first-launch block.
- Every release page starts with the install steps.

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
