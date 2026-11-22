# Contributing to EucLink

Thank you for helping. EucLink is small on purpose: one menu bar app that turns a Bluetooth
button into a key. Contributions that keep it simple and reliable are the most welcome.

## Ways to help

- **Report your button.** Open a [Button report](../../issues/new?template=button_report.yml)
  saying whether your clicker works. This builds the list of buttons people can buy.
- **Report a bug.** Use the [Bug report](../../issues/new?template=bug_report.yml) form.
  The menu bar dot's label and the Activity log usually show what went wrong.
- **Test with other apps.** Tell us how EucLink works with dictation apps other than Handy.
- **Improve the docs.** Clearer steps and better screenshots help every new user.
- **Write code.** Pick an open issue, or open one first to discuss anything large.

Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Building

You need macOS 13 or later and the Xcode command line tools (`xcode-select --install`).
There is no Xcode project and no package manager: `build.sh` calls `swiftc` directly.

```bash
./make-cert.sh   # once, so permissions survive rebuilds
./build.sh       # build, install in /Applications and open
./build.sh ci    # build and run the tests, without installing; this is what CI runs
```

The tests are in `Tests/main.swift`. Add a check there when you change keystroke parsing
or naming. Code that needs the button or macOS permissions cannot run in CI, so describe
how you tested it in the pull request.

## Where things are

| File | What it holds |
|---|---|
| `Sources/Engine.swift` | Bluetooth state, the HID grab, the press handler and the diagnosis |
| `Sources/Keys.swift` | Keystroke parsing, naming and the shortcut recorder |
| `Sources/Seal.swift` | Sealing of settings against edits from outside the app |
| `Sources/AppState.swift` | State shared by the window and the guide |
| `Sources/MainWindow.swift`, `Sources/Guide.swift`, `Sources/Editors.swift` | The interface |
| `Sources/Theme.swift`, `Sources/AppIcon.swift` | Colours, components and the drawn icon |

## Pull requests

1. Fork the repository and make a branch from `main`.
2. Keep each pull request to one change.
3. Run `./build.sh ci` and try the change with a real button.
4. Write commit messages as plain sentences that say what changed and why.
5. Add a line under "Unreleased" in [CHANGELOG.md](CHANGELOG.md) if users will notice the change.

The maintainer reviews every pull request, usually within a week.

## Style

- Follow the code around your change: SwiftUI for views, AppKit for the menu bar item.
- Interface text is short, plain and tells the user what to do next.
- No new dependencies. EucLink uses only Apple's frameworks, which keeps it easy to audit.
- Never log key presses in release builds.

By contributing you agree that your work is released under the [MIT License](LICENSE), and
you agree to follow the [code of conduct](CODE_OF_CONDUCT.md).
