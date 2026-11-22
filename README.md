<p align="center"><img src="docs/images/icon.png" width="120" alt="Clicktalk icon"></p>

<h1 align="center">Clicktalk</h1>

<p align="center">Turn a cheap Bluetooth button into a key for your Mac.<br>
Hold it to talk to your dictation app, tap it to summon a chat, or run any Shortcut.</p>

<p align="center"><img src="docs/images/overview.png" width="640" alt="Clicktalk overview"></p>

Clicktalk is a small menu bar app. It grabs your Bluetooth clicker directly, so the key the
clicker sends (often Volume Up) never reaches other apps, and runs the action you choose.
No Karabiner, no drivers, no dependencies. A setup guide walks you through every macOS
permission and tells you the moment each one is on.

## Install

Needs macOS 13 or later and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/vilbht/clicktalk
cd clicktalk
./build.sh
```

`build.sh` compiles the app, installs it in `/Applications` and opens it. The setup guide
starts on first launch.

## The setup guide

Nine short steps. Each one checks itself live, so the Continue button lights up as soon as
macOS reports the step done.

| | |
|---|---|
| <img src="docs/images/guide-1-welcome.png" width="330"> | <img src="docs/images/guide-2-bluetooth.png" width="330"> |
| **Welcome.** What you need. Offers to copy the app to Applications first. | **Bluetooth.** Lets Clicktalk see whether the button is connected or asleep. |
| <img src="docs/images/guide-3-button.png" width="330"> | <img src="docs/images/guide-4-input-monitoring.png" width="330"> |
| **Button.** Pick your paired clicker. | **Input Monitoring.** Lets Clicktalk hold the button so its key stays private. |
| <img src="docs/images/guide-5-learn.png" width="330"> | <img src="docs/images/guide-6-action.png" width="330"> |
| **Learn.** Press the button; Clicktalk learns which key it sends. | **Action.** Pick a preset, then record the shortcut or choose the app. |
| <img src="docs/images/guide-7-accessibility.png" width="330"> | <img src="docs/images/guide-8-test.png" width="330"> |
| **Accessibility.** Only when the button presses keys. | **Test.** Press the button and see what happened. |

## What a press can do

| Action | You supply | Good for |
|---|---|---|
| Keystroke, hold | record the shortcut | push-to-talk: key down while the button is held |
| Keystroke, press | record the shortcut | an app's global hotkey, tap to toggle |
| Toggle app | pick an app | summon a chat app, press again to hide it |
| Open app | pick an app | always bring it forward |
| Run a Shortcut | pick from your Shortcuts | anything the Shortcuts app can do |
| URL | type it | web chats, `shortcuts://`, any app link |
| Command | type it | scripts |

The shortcut recorder also takes modifier-only shortcuts such as `fn` or Right Option, and
you can type a shortcut instead, for example `cmd+shift+space`.

### Recipes

| Goal | Binding |
|---|---|
| Handy, push-to-talk | Keystroke, hold, Handy's shortcut |
| Handy, toggle mode | Keystroke, press, Handy's shortcut |
| Superwhisper, MacWhisper, Wispr Flow | Keystroke, hold or press, the app's shortcut |
| Summon ChatGPT or Claude desktop | Toggle app, or the app's own hotkey |
| Open a chat and start dictation | Run a Shortcut that does both |

Any app with a hotkey, a URL scheme or a Shortcuts action works. There is no per-app code.

## The window

Open it from the menu bar dot. It has six pages:

- **Overview.** The current state, the one fix that matters, and the path a press takes.
- **Button.** Pick the device, mark it as one that sleeps between presses, reconnect.
- **Bindings.** One binding per physical button: learn a press, choose its action, test it.
- **Permissions.** Each permission with its state, an Allow button and the reset commands.
- **Activity.** Every connection, press and result, newest first.
- **General.** Launch at login, the setup guide, about.

## The menu bar dot

| Dot | Label | Meaning |
|---|---|---|
| green | | Ready |
| green | zz | Button asleep between presses; it wakes on a press |
| red | BT | Bluetooth off, button not paired, or disconnected |
| yellow | HID | Connected, but macOS has not registered it as an input device yet |
| red | PERM | A permission is missing |
| yellow | BIND | No binding, or a binding without an action |
| yellow | GRAB | Another app, often Karabiner, holds the button |
| grey | ? | Not set up |

Click the dot for the diagnosis, the fix, and the one action that resolves it.

## Uninstall, and a clean reinstall

`uninstall.sh` removes the app, its settings, its permission entries and its login item. The
source folder stays.

```bash
./uninstall.sh
```

To test the first-run experience from scratch, uninstall, then build again. The setup guide
opens as it would for a new user:

```bash
./uninstall.sh && ./build.sh
```

`./uninstall.sh --all` also deletes the signing certificate described below.

## Building often

macOS ties the Input Monitoring and Accessibility grants to the app's signature. An ad hoc
signature changes on every build, so each rebuild silently drops both grants. If you change
the code, run this once:

```bash
./make-cert.sh
```

It creates a self-signed code signing certificate in your login keychain and asks for your
login password once. `build.sh` uses it automatically, and the grants then survive rebuilds.

## Regenerating the README images

The images in `docs/images` are rendered from the app's own views with sample data, so they
always match the current design:

```bash
./build.sh docs
```

## If you use Karabiner-Elements

Clicktalk and Karabiner cannot both hold the same device. If the dot shows `GRAB`, open
Karabiner-Elements > Devices, turn off Modify events for the button, and Clicktalk takes it
within ten seconds. Everything else in Karabiner keeps working.

## How it works

- IOBluetooth for pairing and connection state; CoreBluetooth only to ask for permission.
- IOHIDManager opens each of the button's HID interfaces with the seize option, the same
  mechanism Karabiner uses. If the seize is refused it listens instead and says so.
- Bindings are learned from real input, so unusual clickers work without a device list.
- Keystrokes are posted with CGEvent at the HID level, modifiers as real key presses, which
  is what push-to-talk apps watch for. This is why Accessibility is needed.
- SwiftUI for the window and guide, AppKit for the menu bar item. Settings live in
  `~/Library/Preferences/local.clicktalk.plist`. Nothing leaves the Mac.

## Limits

- The first press after a long sleep may only wake the button. That is the button's firmware.
- Double press and long press are not told apart yet.
- The app is not notarized. Building it yourself avoids the Gatekeeper warning.

## License

MIT.
