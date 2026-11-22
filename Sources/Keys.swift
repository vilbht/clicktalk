// Keystrokes: naming, parsing, recording, and the macOS Shortcuts list.

import AppKit

/// Virtual key codes of the modifier keys, with their display name and flag.
let modifierKeys: [UInt16: (name: String, flag: NSEvent.ModifierFlags)] = [
    54: ("Right ⌘", .command), 55: ("⌘", .command),
    56: ("⇧", .shift), 60: ("Right ⇧", .shift),
    58: ("⌥", .option), 61: ("Right ⌥", .option),
    59: ("⌃", .control), 62: ("Right ⌃", .control),
    63: ("fn", .function),
]

/// The flag a modifier key sets, or nil when the key is not a modifier.
func modifierFlag(forKeyCode code: Int) -> CGEventFlags? {
    switch code {
    case 54, 55: return .maskCommand
    case 56, 60: return .maskShift
    case 58, 61: return .maskAlternate
    case 59, 62: return .maskControl
    case 63: return .maskSecondaryFn
    default: return nil
    }
}

func keystrokeName(keyCode: UInt16, flags: NSEvent.ModifierFlags, chars: String?) -> String {
    var f = flags
    if let m = modifierKeys[keyCode] { f.remove(m.flag) }
    var s = ""
    if f.contains(.control) { s += "⌃" }
    if f.contains(.option) { s += "⌥" }
    if f.contains(.shift) { s += "⇧" }
    if f.contains(.command) { s += "⌘" }
    if f.contains(.function) { s += "fn " }
    if let m = modifierKeys[keyCode] { return s + m.name }
    let special: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Escape", 51: "Delete", 117: "Forward Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    if let n = special[keyCode] { return s + n }
    if let c = chars, !c.isEmpty, !c.unicodeScalars.contains(where: { $0.value < 32 }) {
        return s + c.uppercased()
    }
    return s + "key \(keyCode)"
}

func cgFlags(_ m: NSEvent.ModifierFlags) -> CGEventFlags {
    var f: CGEventFlags = []
    if m.contains(.command) { f.insert(.maskCommand) }
    if m.contains(.option) { f.insert(.maskAlternate) }
    if m.contains(.control) { f.insert(.maskControl) }
    if m.contains(.shift) { f.insert(.maskShift) }
    if m.contains(.function) { f.insert(.maskSecondaryFn) }
    return f
}

func nsFlags(_ f: CGEventFlags) -> NSEvent.ModifierFlags {
    var m: NSEvent.ModifierFlags = []
    if f.contains(.maskCommand) { m.insert(.command) }
    if f.contains(.maskAlternate) { m.insert(.option) }
    if f.contains(.maskControl) { m.insert(.control) }
    if f.contains(.maskShift) { m.insert(.shift) }
    if f.contains(.maskSecondaryFn) { m.insert(.function) }
    return m
}

/// Parses "cmd+shift+space", "option+k", "ctrl+alt+f5", "right option" into a key
/// code and flags. US layout key codes.
func parseKeystroke(_ text: String) -> (keyCode: Int, flags: CGEventFlags, name: String)? {
    let codes: [String: Int] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39,
        "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48,
        "space": 49, "`": 50, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "home": 115, "end": 119, "pageup": 116,
        "pagedown": 121, "left": 123, "right": 124, "down": 125, "up": 126, "forwarddelete": 117,
    ]
    let rightModifiers: [String: Int] = [
        "rightcmd": 54, "rightcommand": 54, "rightshift": 60, "rightoption": 61, "rightopt": 61,
        "rightalt": 61, "rightctrl": 62, "rightcontrol": 62,
    ]
    var flags: CGEventFlags = []
    var key: String?
    var lastModifier: Int?
    let normalized = text.lowercased()
        .replacingOccurrences(of: "right ", with: "right")
        .replacingOccurrences(of: "right-", with: "right")
    for raw in normalized.split(whereSeparator: { $0 == "+" || $0 == " " }) {
        let part = String(raw).trimmingCharacters(in: .whitespaces)
        switch part {
        case "cmd", "command", "⌘": flags.insert(.maskCommand); lastModifier = 55
        case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate); lastModifier = 58
        case "ctrl", "control", "⌃": flags.insert(.maskControl); lastModifier = 59
        case "shift", "⇧": flags.insert(.maskShift); lastModifier = 56
        case "fn", "function", "globe": flags.insert(.maskSecondaryFn); lastModifier = 63
        case "": break
        default:
            if let code = rightModifiers[part], let flag = modifierFlag(forKeyCode: code) {
                flags.insert(flag)
                lastModifier = code
            } else {
                key = part
            }
        }
    }
    let code: Int
    if let k = key {
        guard let c = codes[k] else { return nil }
        code = c
    } else if let m = lastModifier {
        code = m // modifier-only shortcut, such as "fn" or "right option"
    } else {
        return nil
    }
    let chars = key.flatMap { $0.count == 1 ? $0 : nil }
    let name = keystrokeName(keyCode: UInt16(code), flags: nsFlags(flags), chars: chars)
    return (code, flags, name)
}

/// Records the next shortcut through a listen-only session event tap. Unlike a view's
/// keyDown, the tap sees a key even when another app owns it as a global hotkey, which
/// is exactly the case when recording a dictation app's shortcut. It also records
/// modifier-only shortcuts: a modifier pressed and released with no key in between.
/// Needs Input Monitoring.
final class KeyRecorder {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var pendingModifier: (code: Int, flags: CGEventFlags)?
    private var lastFlags: CGEventFlags = []
    /// keyCode, flags, display name
    var onKey: ((Int, CGEventFlags, String) -> Void)?

    private static let modifierMask: CGEventFlags =
        [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn]

    func start() -> Bool {
        stop()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, ctx in
                if let ctx = ctx {
                    Unmanaged<KeyRecorder>.fromOpaque(ctx).takeUnretainedValue().handle(type, event)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: ctx) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        pendingModifier = nil
        lastFlags = []
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return
        }
        let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection(KeyRecorder.modifierMask)
        if type == .keyDown {
            pendingModifier = nil
            let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers
            deliver(code, flags, chars)
        } else if type == .flagsChanged {
            if flags.rawValue & ~lastFlags.rawValue != 0, modifierFlag(forKeyCode: code) != nil {
                pendingModifier = (code, flags) // a modifier went down
            } else if flags.isEmpty, let p = pendingModifier {
                pendingModifier = nil // all released with no key in between
                deliver(p.code, p.flags, nil)
            }
            lastFlags = flags
        }
    }

    private func deliver(_ code: Int, _ flags: CGEventFlags, _ chars: String?) {
        let name = keystrokeName(keyCode: UInt16(code), flags: nsFlags(flags), chars: chars)
        DispatchQueue.main.async { [weak self] in self?.onKey?(code, flags, name) }
    }

    func stop() {
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    deinit { stop() }
}

/// Names of the user's macOS Shortcuts. Slow, so call it off the main thread.
func listShortcuts() -> [String] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
    p.arguments = ["list"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
        .split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
}
