# Clicktalk

Turn a cheap Bluetooth button into a key for your Mac. One menu bar app, one Swift file,
no Karabiner, no dependencies.

Press the button, something happens: your dictation app starts listening, your chat app
comes forward, a Shortcut runs. Clicktalk grabs the button exclusively, so the key it
sends never leaks into whatever app is in front.

## Install

Needs macOS 12 or later and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/vilbht/clicktalk
cd clicktalk
./build.sh
```

The script compiles, signs ad hoc, quits any running copy and launches the new one.
Move `Clicktalk.app` to `/Applications` when you are happy with it.

## Set up in two minutes

1. Pair the button in System Settings > Bluetooth. Any BLE clicker works: camera shutter
   remotes, presentation clickers, "AB Shutter" buttons, Flic-style buttons in HID mode.
2. Click the grey dot in the menu bar, open **Device**, pick the button.
3. Allow **Bluetooth** and **Input Monitoring** when macOS asks. Input Monitoring is what
   lets Clicktalk read the button instead of the system.
4. Open **Bindings > Add button binding**, press the button once. Clicktalk learns the key
   it sends, for example Volume Up or Enter.
5. Choose the action. Done. The dot turns green.

A clicker with several buttons gets one binding per button.

## Actions

| Action | You supply | Good for |
|---|---|---|
| Toggle app | pick an app | summon a chat app, press again to hide it |
| Open app | pick an app | always bring it forward |
| Run macOS Shortcut | pick from your Shortcuts list | anything the Shortcuts app can do, no code |
| Press keystroke | press the combo once | an app's own global hotkey |
| Hold keystroke | same, choose Hold | push-to-talk: key down while the button is held |
| Open URL | type it | web chats, `shortcuts://`, any app scheme |
| Run shell command | type it | scripts |

Keystroke actions need the **Accessibility** permission. Clicktalk asks for it the first
time you save one.

### If you rebuild often

An ad hoc signature changes on every build, and macOS silently drops both permissions when
the signature changes, even though the privacy panes still show Clicktalk as on. Users who
build once never see this. If you are changing the code, run this once:

```bash
./make-cert.sh
```

It creates a self-signed code signing certificate in your login keychain, asks for your
login password once to trust it, and build.sh picks it up automatically. Grant the
permissions one more time after the next build; they then stick.

To recover a stuck grant without the certificate: quit Clicktalk, turn its entry off and on
in the pane, then relaunch with `open Clicktalk.app`, not with build.sh, which re-signs.
If that still fails, clear the records and grant again from the menu:

```bash
tccutil reset ListenEvent local.clicktalk
tccutil reset Accessibility local.clicktalk
```

## Recipes

| Goal | Binding |
|---|---|
| Talk to Handy (push-to-talk) | Hold keystroke, set to Handy's shortcut |
| Talk to Handy (toggle mode) | Press keystroke, Handy's shortcut |
| Superwhisper, MacWhisper, Wispr Flow | Press or Hold keystroke, the app's hotkey |
| Summon ChatGPT desktop | Press keystroke ⌥ Space, or Toggle app |
| Summon Claude desktop | Toggle app, or its hotkey if you set one |
| Start a Shortcut that opens a chat and starts dictation | Run macOS Shortcut |

Any app that exposes a hotkey, a URL scheme or a Shortcuts action works unchanged. There is
no per-app integration code and none is needed.

## What the dot means

| Dot | Label | Meaning |
|---|---|---|
| green | | Ready. Button grabbed, bindings set |
| green | zz | Button asleep between presses, wakes on press |
| red | BT | Bluetooth off, button not paired, or disconnected |
| yellow | HID | Connected but macOS has not registered it as an input device yet |
| red | PERM | Input Monitoring or Accessibility permission missing |
| yellow | BIND | Grabbed, no binding yet |
| yellow | GRAB | Listening only: another app, often Karabiner, holds the button |
| grey | ? | No button selected |

The first menu line is the diagnosis, the second is the fix. **Recent events** keeps a
timestamped log: connects, disconnects with their duration, every press and what it fired.

## Buttons that sleep

Most BLE clickers disconnect after a minute idle and reconnect when pressed. Turn on
**Button sleeps between presses** and Clicktalk shows this as a calm green `zz` instead of a
red disconnect. The first press after a long sleep may only wake the button; the second
fires the action. That is the button's firmware, not something software can skip.

## If you already use Karabiner-Elements

Clicktalk and Karabiner cannot both hold the same device. If the dot shows `GRAB` and the
menu says Karabiner claims the button, open Karabiner-Elements > Devices, untick **Modify
events** for the button, and relaunch Clicktalk. Everything else in Karabiner keeps working.

## How it works

- IOBluetooth for pairing and connection state, with connect and disconnect notifications.
- IOHIDManager to find the button's HID interfaces and open them with the seize option,
  the same mechanism Karabiner's grabber uses. Falls back to a non-exclusive open if the
  seize is refused, and says so.
- Bindings are learned from real HID input, so unusual clickers work without a device list.
- Keystrokes are posted with CGEvent at the HID tap, which is why Accessibility is needed.
- Settings live in `~/Library/Preferences/local.clicktalk.plist`. Nothing leaves the Mac.

## Limits

- Return and Escape cannot be recorded as keystroke actions; the recorder dialog eats them.
  Use "Type it instead" and write `return` or `escape`.
- Recording a shortcut another app owns fires that app once. Harmless, but expect it.
- Double-press and long-press are not distinguished yet.
- The exclusive grab can be refused for some devices. Bindings still fire in listening mode,
  but the button's original key also reaches macOS.

## License

MIT.
