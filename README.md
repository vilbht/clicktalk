# Clicktalk

A macOS menu bar app that watches one Bluetooth button and tells you which layer broke
when Karabiner stops reacting to it. Single Swift file, no dependencies, no Xcode project.

## Build and run

```bash
./build.sh
open Clicktalk.app
```

First launch: macOS asks for Bluetooth permission. Allow it. Then pick your button under
**Device** in the menu. Clicktalk remembers the choice.

## What the dot means

| Dot | Label | Meaning |
|---|---|---|
| green | | Connected, registered as an input device, Karabiner running and modifying its events |
| red | BT | Bluetooth off, button not paired, or button disconnected |
| yellow | HID | Connected over Bluetooth but macOS has not registered it as an input device |
| red or yellow | KE | Karabiner problem: grabber not running, user agent not running, or Modify events off |
| grey | ? | No button selected yet |

The first menu line is the diagnosis. The second is the fix.

## Checks, in order

1. Bluetooth radio on. Button in the paired list. Button connected. Live via IOBluetooth
   connect and disconnect notifications plus a 3 second poll.
2. macOS sees the button as an HID device over Bluetooth, matched by product name or by
   serial equal to the Bluetooth address. Shows kind (keyboard, pointer) and vendor:product.
3. Karabiner's core service and console user server are in the process list. Both the
   Karabiner 15 names (`Karabiner-Core-Service`, `Karabiner-Console-User-Server`) and the
   older ones (`karabiner_grabber`, `karabiner_console_user_server`) are recognised.
4. `~/.config/karabiner/karabiner.json`, selected profile, has a `devices` entry for the
   button's vendor and product ID with `ignore: false`. A missing entry on a pointer-only
   device is flagged, since Karabiner ignores pointing devices by default.
5. Last line of `/var/log/karabiner/grabber.log` that mentions the button, if readable.

## Actions

- **Reconnect now**: asks macOS to open a connection. Works for classic Bluetooth.
  A BLE button has to be pressed to wake it; Clicktalk says so when the request is refused.
- **Auto-reconnect**: retries every 20 seconds while disconnected.
- **Enable Modify events**: sets `ignore: false` for the button in karabiner.json, adding
  entries if missing. Backs up to `karabiner.json.clicktalk.bak` first. Karabiner reloads on
  its own.
- **Restart Karabiner daemons**: finds Karabiner's launchd labels with `launchctl list`
  (they differ between versions) and kickstarts them. Admin prompt for the system daemons.
- **Open**: Karabiner-Elements, EventViewer, Input Monitoring pane, Bluetooth settings,
  karabiner.json, grabber.log.
- **Recent events**: timestamped log of every transition, including how long a disconnect
  lasted.
- **Launch at login**: macOS 13 and later.

## Not checked

Input Monitoring permission for Karabiner. Apple does not expose another app's TCC grant.
If everything is green and a rule still does not fire, open the Input Monitoring pane from
the menu and confirm Karabiner's core service is allowed.
