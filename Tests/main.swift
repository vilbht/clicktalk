// Tests for keystroke parsing and naming, and for what the uninstaller removes. Built and
// run by `./build.sh ci`, which compiles this file with Sources/Keys.swift and
// Sources/Leftovers.swift. No Xcode project needed.

import AppKit

var failures = 0
var count = 0

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    count += 1
    if !ok {
        failures += 1
        print("FAIL line \(line): \(what)")
    }
}

func expect(_ text: String, code: Int, flags: CGEventFlags, name: String, line: Int = #line) {
    guard let k = parseKeystroke(text) else {
        check(false, "\"\(text)\" did not parse", line: line)
        return
    }
    check(k.keyCode == code, "\"\(text)\" key code \(k.keyCode), expected \(code)", line: line)
    check(k.flags == flags, "\"\(text)\" flags \(k.flags.rawValue), expected \(flags.rawValue)", line: line)
    check(k.name == name, "\"\(text)\" name \"\(k.name)\", expected \"\(name)\"", line: line)
}

// Shortcuts that dictation apps use.
expect("fn+space", code: 49, flags: .maskSecondaryFn, name: "fn Space")
expect("cmd+shift+k", code: 40, flags: [.maskCommand, .maskShift], name: "⇧⌘K")
expect("ctrl+alt+f5", code: 96, flags: [.maskControl, .maskAlternate], name: "⌃⌥F5")
expect("Option+Space", code: 49, flags: .maskAlternate, name: "⌥Space")

// Modifier-only shortcuts.
expect("right option", code: 61, flags: .maskAlternate, name: "Right ⌥")
expect("right-cmd", code: 54, flags: .maskCommand, name: "Right ⌘")
expect("fn", code: 63, flags: .maskSecondaryFn, name: "fn")

// Input that must be refused.
check(parseKeystroke("") == nil, "an empty shortcut is refused")
check(parseKeystroke("cmd+notakey") == nil, "an unknown key is refused")

// Modifier key codes.
check(modifierFlag(forKeyCode: 55) == .maskCommand, "55 is Command")
check(modifierFlag(forKeyCode: 61) == .maskAlternate, "61 is right Option")
check(modifierFlag(forKeyCode: 63) == .maskSecondaryFn, "63 is fn")
check(modifierFlag(forKeyCode: 49) == nil, "Space is not a modifier")

// Names for recorded keys.
check(keystrokeName(keyCode: 0, flags: .command, chars: "a") == "⌘A", "⌘A")
check(keystrokeName(keyCode: 7, flags: [], chars: "\u{1}") == "key 7", "control characters fall back to the key code")
check(keystrokeName(keyCode: 58, flags: .option, chars: nil) == "⌥", "a lone Option key is not named twice")

// Flag conversion round trip.
let all: NSEvent.ModifierFlags = [.command, .option, .control, .shift, .function]
check(nsFlags(cgFlags(all)) == all, "flags survive a round trip")

// The uninstaller deletes only EucLink's own files.
let home = URL(fileURLWithPath: "/Users/someone")
let paths = Uninstaller.leftoverPaths(home: home, bundleID: "local.euclink").map(\.path)
check(paths.contains("/Users/someone/Library/Preferences/local.euclink.plist"), "the settings file is removed")
check(paths.allSatisfy { $0.hasPrefix("/Users/someone/Library/") && $0.contains("local.euclink") },
      "every removed path is EucLink's own")
for bad in ["", "..", "../Documents", "a/b", ".hidden"] {
    check(Uninstaller.leftoverPaths(home: home, bundleID: bad).isEmpty, "bundle id \"\(bad)\" removes nothing")
}
check(Uninstaller.permissions == ["ListenEvent", "Accessibility", "BluetoothAlways"], "all three permissions are reset")

print("\(count - failures) of \(count) checks passed")
exit(failures == 0 ? 0 : 1)
