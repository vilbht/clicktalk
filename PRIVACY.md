# Privacy

EucLink is built privacy first. It runs on your Mac, keeps what it needs on your Mac, and
goes online for one optional thing that is off by default.

## The short version

- No accounts, no analytics, no telemetry, no advertising.
- It reads one device: the Bluetooth button you chose. It never reads your keyboard.
- It does not touch your microphone or your voice. Your dictation app does that.
- It goes online only to check for a new version, and only if you turn that on.

## What EucLink stores, and where

| What | Where | Why |
|---|---|---|
| Your bindings: which button press does what | `~/Library/Preferences/local.euclink.plist` | To run your actions |
| Your button's name and its device ID | The same file | To find your button again |
| A few switches: setup progress, open at login, update check | The same file | To remember your choices |
| The time and result of the last update check, if you use it | The same file | To avoid asking GitHub again too soon |
| A random key that seals your settings | Your login keychain, as "EucLink settings seal" | So another program cannot quietly change what your button runs |

Nothing else is written to disk. **Activity**, the list of connections and presses, is kept
in memory only, holds at most 60 lines, and is gone when you quit. You can empty it at any
time with **Clear**.

## What EucLink reads

| What | When | Kept? |
|---|---|---|
| Presses of the one Bluetooth button you chose | While EucLink runs | The last 60, in memory |
| The names of your paired Bluetooth devices | When you choose your button | Only the one you choose |
| Every key press | Only while you record a shortcut: until the first shortcut, for ten seconds at most, and only while EucLink is in front | Only the shortcut you recorded |
| The names of running programs | Only while EucLink cannot hold your button, to see whether Karabiner-Elements has it | No |
| Your list of Shortcuts | When you pick the "Run a Shortcut" action | Only the one you choose |

## When EucLink goes online

Never, unless you turn on **Check for updates when EucLink opens** or click **Check Now**.
Both are in General, and the switch is off by default.

When it checks, EucLink sends one request to GitHub asking for the latest release of this
project. The request carries no cookies, no identifier and nothing about you or your Mac.
GitHub sees your IP address, as it does for any visit, under
[GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).
EucLink never downloads or installs anything by itself. If a newer version exists, it shows
a message with a button that opens the release page in your browser.

This is enforced, not just promised: the project's build check fails if networking code
appears anywhere outside `Sources/Updates.swift`, or if that file names any address other
than this project on GitHub.

## What is outside EucLink's control

- **Your own actions.** A binding that opens a link or runs a command does what you set it
  to do, including going online.
- **Your dictation app.** EucLink presses its shortcut. What that app does with your voice
  is covered by its own privacy policy.
- **GitHub and Apple.** GitHub sees your visit when you download EucLink. macOS may send
  crash reports to Apple if you have turned that on in System Settings.

## Removing everything

**General > Uninstall** in the app, or `./uninstall.sh`, removes the settings file, the
keychain key, the login item and EucLink's permissions, and moves the app to the Trash.

## Checking this yourself

EucLink is open source and uses only Apple's frameworks. You can read the code, build it
with `./build.sh`, and compare a download with the checksums on its release page.

## Changes

Any change to this policy is made in this file and listed in [CHANGELOG.md](CHANGELOG.md).
Questions: open an [issue](../../issues), or for something sensitive use
[SECURITY.md](SECURITY.md).
