// The saved setting types: which button press runs which action. Foundation only, so the
// tests can check that settings saved by earlier versions still load and still match their
// seals.

import Foundation

struct Trigger: Codable, Equatable, Hashable {
    var usagePage: Int
    var usage: Int
    var name: String { triggerName(usagePage: usagePage, usage: usage) }
}

enum ActionKind: String, Codable, CaseIterable {
    case none, toggleApp, openApp, shortcut, keystroke, url, shell
    var label: String {
        switch self {
        case .none: return "No action"
        case .toggleApp: return "Toggle app (show or hide)"
        case .openApp: return "Open app"
        case .shortcut: return "Run macOS Shortcut"
        case .keystroke: return "Press keystroke"
        case .url: return "Open URL"
        case .shell: return "Run shell command"
        }
    }
}

struct Action: Codable, Equatable {
    var kind: ActionKind = .none
    var value: String = ""        // app path, shortcut name, URL, command, or keystroke label
    var keyCode: Int = 0
    var flags: UInt64 = 0
    /// Keystroke only: key down while the button is held, key up on release.
    /// Needed for push-to-talk dictation apps such as Handy.
    var hold: Bool = false
    var name: String {
        switch kind {
        case .none: return "no action"
        case .toggleApp: return "toggle \(appName)"
        case .openApp: return "open \(appName)"
        case .shortcut: return "shortcut “\(value)”"
        case .keystroke: return "\(hold ? "hold" : "press") \(value)"
        case .url: return "open \(value)"
        case .shell: return "run “\(value)”"
        }
    }
    var appName: String { URL(fileURLWithPath: value).deletingPathExtension().lastPathComponent }
}

struct ButtonBinding: Codable, Equatable {
    var id: UUID = UUID()
    var trigger: Trigger
    var action: Action = Action()
    /// Which gesture on the button runs this binding. One binding per button and gesture.
    var gesture: Gesture = .press

    init(id: UUID = UUID(), trigger: Trigger, action: Action = Action(), gesture: Gesture = .press) {
        self.id = id; self.trigger = trigger; self.action = action; self.gesture = gesture
    }

    private enum CodingKeys: String, CodingKey { case id, trigger, action, gesture }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        trigger = try c.decode(Trigger.self, forKey: .trigger)
        action = try c.decode(Action.self, forKey: .action)
        gesture = try c.decodeIfPresent(Gesture.self, forKey: .gesture) ?? .press
    }

    /// A press binding is written exactly as before gestures existed, so bindings saved and
    /// sealed by an earlier version still match their seals.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(action, forKey: .action)
        if gesture != .press { try c.encode(gesture, forKey: .gesture) }
    }
}

func triggerName(usagePage: Int, usage: Int) -> String {
    switch usagePage {
    case 0x0C:
        let consumer: [Int: String] = [
            0xE9: "Volume Up", 0xEA: "Volume Down", 0xE2: "Mute", 0xCD: "Play/Pause",
            0xB5: "Next Track", 0xB6: "Previous Track", 0xB7: "Stop", 0xB0: "Play", 0xB1: "Pause",
            0x221: "Search", 0x223: "Home", 0x224: "Back", 0x225: "Forward", 0x40: "Menu",
            0x30: "Power", 0x6F: "Brightness Up", 0x70: "Brightness Down", 0xCF: "Voice Command",
        ]
        return consumer[usage] ?? "Consumer \(usage)"
    case 0x07:
        if (0x04...0x1D).contains(usage) {
            return String(UnicodeScalar(UInt8(65 + usage - 0x04)))
        }
        if (0x1E...0x26).contains(usage) { return String(usage - 0x1D) }
        let keys: [Int: String] = [
            0x27: "0", 0x28: "Return", 0x29: "Escape", 0x2A: "Delete", 0x2B: "Tab", 0x2C: "Space",
            0x4F: "Right Arrow", 0x50: "Left Arrow", 0x51: "Down Arrow", 0x52: "Up Arrow",
            0x4A: "Home", 0x4D: "End", 0x4B: "Page Up", 0x4E: "Page Down",
            0x3A: "F1", 0x3B: "F2", 0x3C: "F3", 0x3D: "F4", 0x3E: "F5", 0x3F: "F6",
            0x40: "F7", 0x41: "F8", 0x42: "F9", 0x43: "F10", 0x44: "F11", 0x45: "F12",
            0xE0: "Left Control", 0xE1: "Left Shift", 0xE2: "Left Option", 0xE3: "Left Command",
            0xE4: "Right Control", 0xE5: "Right Shift", 0xE6: "Right Option", 0xE7: "Right Command",
        ]
        return keys[usage] ?? "Key \(usage)"
    case 0x09:
        return "Button \(usage)"
    case 0x01:
        let desktop: [Int: String] = [0x81: "System Power", 0x82: "System Sleep", 0x83: "System Wake"]
        return desktop[usage] ?? "Desktop \(usage)"
    default:
        return "Page \(usagePage) usage \(usage)"
    }
}
