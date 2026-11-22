// Clicktalk: turn a Bluetooth button into an action, in one menu bar app.
//
// Layers, top to bottom. The first failing layer becomes the dot colour and the
// first line of the menu.
//   1. Bluetooth radio on, button paired, button connected.
//   2. macOS registered the button as an HID input device.
//   3. Input Monitoring permission granted to Clicktalk.
//   4. Clicktalk holds the device exclusively (seized), so its key never reaches macOS.
//      Falls back to listening, where the original key also passes through.
//   5. At least one binding: a learned button press mapped to an action.
//
// Karabiner-Elements is not needed. If it is installed and holds the same device,
// the seize fails and the menu says what to untick.

import AppKit
import IOBluetooth
import IOKit.hid
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Model

enum Health {
    case good, warn, bad, unknown
    var color: NSColor {
        switch self {
        case .good: return .systemGreen
        case .warn: return .systemYellow
        case .bad: return .systemRed
        case .unknown: return .systemGray
        }
    }
}

struct HIDInfo: Equatable {
    var vendorID: Int
    var productID: Int
    var isKeyboard: Bool
    var isPointing: Bool
    var transport: String
    var product: String
    var serial: String
    var idString: String { String(format: "%04lx:%04lx", vendorID, productID) }
    var kind: String {
        switch (isKeyboard, isPointing) {
        case (true, true): return "keyboard+pointer"
        case (true, false): return "keyboard"
        case (false, true): return "pointer"
        default: return "other"
        }
    }
}

/// What we remember about the button's HID identity so it can be grabbed even
/// while it is asleep.
struct HIDIdent: Codable, Equatable {
    var vendorID: Int
    var productID: Int
    var product: String
    var isEmpty: Bool { vendorID == 0 && productID == 0 && product.isEmpty }
}

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

struct Binding: Codable, Equatable {
    var id: UUID = UUID()
    var trigger: Trigger
    var action: Action = Action()
}

enum GrabState: Equatable {
    case idle, noPermission, seized, listening(Int32), failed(Int32)
}

struct Snapshot: Equatable {
    var deviceName: String?
    var btPowerOn = true
    var paired = false
    var connected = false
    var hid: [HIDInfo] = []
    var inputMonitoring = false
    var accessibility = true
    var grab: GrabState = .idle
    var bindings: [Binding] = []
    var karabinerRunning = false
    var karabinerModifies = false
    var lastPress: (Date, Trigger)?
    var health: Health = .unknown
    var diagnosis = ""
    var hint: String?

    static func == (a: Snapshot, b: Snapshot) -> Bool {
        a.deviceName == b.deviceName && a.btPowerOn == b.btPowerOn && a.paired == b.paired
            && a.connected == b.connected && a.hid == b.hid && a.inputMonitoring == b.inputMonitoring
            && a.accessibility == b.accessibility && a.grab == b.grab && a.bindings == b.bindings
            && a.karabinerRunning == b.karabinerRunning && a.karabinerModifies == b.karabinerModifies
            && a.lastPress?.0 == b.lastPress?.0 && a.health == b.health && a.diagnosis == b.diagnosis
            && a.hint == b.hint
    }
}

struct Event {
    let date: Date
    let text: String
}

let timeFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

func ago(_ d: Date) -> String {
    let s = Int(Date().timeIntervalSince(d))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \((s % 3600) / 60)m"
}

func hexDigits(_ s: String) -> String {
    s.lowercased().filter { "0123456789abcdef".contains($0) }
}

func hex(_ r: Int32) -> String { "0x" + String(UInt32(bitPattern: r), radix: 16) }

let kReturnExclusiveAccess: IOReturn = Int32(bitPattern: 0xE00002C5)
let kReturnNotPermitted: IOReturn = Int32(bitPattern: 0xE00002E2)

// MARK: - Names

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

/// True for HID elements that behave like a button or key, false for axes, wheels,
/// vendor pages and report padding.
func isButtonLike(usagePage: Int, usage: Int) -> Bool {
    guard usage != 0, usagePage < 0xFF00 else { return false }
    switch usagePage {
    case 0x07: return usage >= 0x04
    case 0x09: return true
    case 0x0C: return usage != 0x238 && usage != 0x239 // AC Pan, scroll
    case 0x01: return (0x81...0x83).contains(usage)
    default: return false
    }
}

func keystrokeName(keyCode: UInt16, flags: NSEvent.ModifierFlags, chars: String?) -> String {
    var s = ""
    if flags.contains(.control) { s += "⌃" }
    if flags.contains(.option) { s += "⌥" }
    if flags.contains(.shift) { s += "⇧" }
    if flags.contains(.command) { s += "⌘" }
    if flags.contains(.function) { s += "fn " }
    let special: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 53: "Escape", 51: "Delete", 117: "Forward Delete",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]
    if let n = special[keyCode] { return s + n }
    if let c = chars, !c.isEmpty { return s + c.uppercased() }
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

// MARK: - Monitor

final class Monitor: NSObject {
    var onChange: ((Snapshot) -> Void)?
    private(set) var snapshot = Snapshot()
    private(set) var events: [Event] = []
    private(set) var connectedSince: Date?
    private(set) var disconnectedSince: Date?
    private(set) var lastPress: (Date, Trigger)?

    /// Set while the "press your button" dialog is open. The next press lands in `learned`.
    var learning = false
    private(set) var learned: Trigger?

    private var enumManager: IOHIDManager!
    private var grabManager: IOHIDManager?
    private(set) var grab: GrabState = .idle
    private var pressed = Set<Trigger>()
    private var lastFire: [UUID: Date] = [:]
    /// Hold-mode keystrokes whose key-up is still owed, by trigger.
    private var heldKeys: [Trigger: Action] = [:]

    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNote: IOBluetoothUserNotification?
    private var timer: Timer?
    private var lastReconnectAttempt = Date.distantPast
    private var procCache: (at: Date, names: [String]) = (.distantPast, [])
    private var hasBaseline = false

    private let defaults = UserDefaults.standard

    // MARK: settings

    var deviceName: String? {
        get { defaults.string(forKey: "deviceName") }
        set {
            defaults.set(newValue, forKey: "deviceName")
            deviceIdents = []
            hasBaseline = false
            connectedSince = nil
            disconnectedSince = nil
            log("Now watching \(newValue ?? "nothing")")
            refresh()
        }
    }

    var autoReconnect: Bool {
        get { defaults.bool(forKey: "autoReconnect") }
        set { defaults.set(newValue, forKey: "autoReconnect"); refresh() }
    }

    /// The button disconnects between presses to save battery and wakes on press.
    var sleeps: Bool {
        get { defaults.bool(forKey: "sleeps") }
        set { defaults.set(newValue, forKey: "sleeps"); refresh() }
    }

    private(set) var deviceIdents: [HIDIdent] {
        get {
            guard let d = defaults.data(forKey: "deviceHID") else { return [] }
            return (try? JSONDecoder().decode([HIDIdent].self, from: d)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "deviceHID")
            rebuildGrab()
        }
    }

    var bindings: [Binding] {
        get {
            guard let d = defaults.data(forKey: "bindings") else { return [] }
            return (try? JSONDecoder().decode([Binding].self, from: d)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "bindings")
            refresh()
        }
    }

    static let karabinerConfig = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/karabiner/karabiner.json")

    // MARK: lifecycle

    func start() {
        enumManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(enumManager, nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(enumManager, { p, _, _, _ in
            guard let p = p else { return }
            Unmanaged<Monitor>.fromOpaque(p).takeUnretainedValue().refreshSoon()
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(enumManager, { p, _, _, _ in
            guard let p = p else { return }
            Unmanaged<Monitor>.fromOpaque(p).takeUnretainedValue().refreshSoon()
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(enumManager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // Enumeration only; never opened, so it needs no permission.

        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(btConnected(_:device:)))
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer!, forMode: .common)
        log("Clicktalk started")
        rebuildGrab()
        refresh()
    }

    func log(_ text: String) {
        events.insert(Event(date: Date(), text: text), at: 0)
        if events.count > 60 { events.removeLast(events.count - 60) }
        print("[\(timeFmt.string(from: Date()))] \(text)")
    }

    func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    @objc func btConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        if let d = selectedDevice(), d.addressString == device.addressString {
            disconnectNote?.unregister()
            disconnectNote = device.register(forDisconnectNotification: self,
                                             selector: #selector(btDisconnected(_:device:)))
        }
        refresh()
    }

    @objc func btDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        refresh()
    }

    // MARK: data sources

    func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    }

    func selectedDevice() -> IOBluetoothDevice? {
        guard let name = deviceName else { return nil }
        return pairedDevices().first { ($0.name ?? "") == name }
    }

    private func hidDevices() -> [HIDInfo] {
        guard let set = IOHIDManagerCopyDevices(enumManager) as? Set<IOHIDDevice> else { return [] }
        var out: [HIDInfo] = []
        for dev in set {
            func prop<T>(_ key: String) -> T? {
                IOHIDDeviceGetProperty(dev, key as CFString) as? T
            }
            let transport: String = prop(kIOHIDTransportKey) ?? ""
            guard transport.localizedCaseInsensitiveContains("bluetooth") else { continue }
            var kb = false, pt = false
            if let pairs: [[String: Int]] = prop(kIOHIDDeviceUsagePairsKey) {
                for p in pairs {
                    let page = p[kIOHIDDeviceUsagePageKey] ?? 0
                    let usage = p[kIOHIDDeviceUsageKey] ?? 0
                    if page == 1 && (usage == 6 || usage == 7) { kb = true }
                    if page == 1 && (usage == 1 || usage == 2) { pt = true }
                    if page == 0x0C && usage == 1 { kb = true }
                }
            } else {
                let page: Int = prop(kIOHIDPrimaryUsagePageKey) ?? 0
                let usage: Int = prop(kIOHIDPrimaryUsageKey) ?? 0
                kb = page == 1 && (usage == 6 || usage == 7)
                pt = page == 1 && (usage == 1 || usage == 2)
            }
            let info = HIDInfo(vendorID: prop(kIOHIDVendorIDKey) ?? 0,
                               productID: prop(kIOHIDProductIDKey) ?? 0,
                               isKeyboard: kb, isPointing: pt,
                               transport: transport,
                               product: prop(kIOHIDProductKey) ?? "",
                               serial: prop(kIOHIDSerialNumberKey) ?? "")
            if !out.contains(info) { out.append(info) }
        }
        return out
    }

    private func matches(_ h: HIDInfo, device: IOBluetoothDevice?, name: String?) -> Bool {
        if let name = name, !name.isEmpty, h.product.caseInsensitiveCompare(name) == .orderedSame { return true }
        if let addr = device?.addressString {
            let a = hexDigits(addr), s = hexDigits(h.serial)
            if a.count == 12 && a == s { return true }
        }
        return false
    }

    private func processNames() -> [String] {
        if Date().timeIntervalSince(procCache.at) < 5 { return procCache.names }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "comm="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        var names: [String] = []
        if (try? p.run()) != nil {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            names = String(decoding: data, as: UTF8.self)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        procCache = (Date(), names)
        return names
    }

    /// Does Karabiner's config claim this device (Modify events on)? Used only to
    /// explain a failed seize.
    private func karabinerModifies(hid: [HIDInfo]) -> Bool {
        guard !hid.isEmpty,
              let data = try? Data(contentsOf: Monitor.karabinerConfig),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]] else { return false }
        let profile = profiles.first { ($0["selected"] as? Bool) == true } ?? profiles.first
        let devices = profile?["devices"] as? [[String: Any]] ?? []
        for h in hid {
            let entries = devices.filter { d in
                let id = d["identifiers"] as? [String: Any] ?? [:]
                return id["vendor_id"] as? Int == h.vendorID && id["product_id"] as? Int == h.productID
            }
            if entries.isEmpty { if h.isKeyboard { return true } else { continue } }
            if entries.contains(where: { ($0["ignore"] as? Bool ?? false) == false }) { return true }
        }
        return false
    }

    // MARK: grab

    /// Raw TCC answer. "unknown" means macOS has no decision recorded for this exact
    /// binary, which is what every rebuild of an ad hoc signed app looks like.
    var inputMonitoringState: String {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return "granted"
        case kIOHIDAccessTypeDenied: return "denied"
        default: return "unknown"
        }
    }

    /// Only an explicit denial stops us from trying. On "unknown" the open itself is
    /// attempted; macOS then prompts, or refuses with kIOReturnNotPermitted.
    var inputMonitoringGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeDenied
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        log("Input Monitoring requested")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.rebuildGrab()
            self?.refresh()
        }
    }

    /// Per-interface result. A Bluetooth button usually exposes two or three HID
    /// interfaces (keyboard, consumer, pointer); each is opened on its own.
    enum DeviceGrab: Equatable { case seized, listening(IOReturn), failed(IOReturn) }
    private var opened: [IOHIDDevice: DeviceGrab] = [:]
    private var failedAt: [IOHIDDevice: Date] = [:]
    private(set) var grabDetail = ""

    /// Tears down and recreates the matching manager for the current device identity.
    /// The manager is never opened itself; it only reports arrivals and removals, and
    /// each matching interface is opened individually in `openDevice`.
    func rebuildGrab() {
        closeAll()
        if let m = grabManager {
            IOHIDManagerUnscheduleFromRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            grabManager = nil
        }
        let idents = deviceIdents.filter { !$0.isEmpty }
        guard !idents.isEmpty else { grab = .idle; grabDetail = ""; return }
        guard inputMonitoringGranted else { grab = .noPermission; grabDetail = ""; return }

        let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let dicts: [[String: Any]] = idents.map { i in
            var d: [String: Any] = [:]
            if i.vendorID != 0 { d[kIOHIDVendorIDKey] = i.vendorID }
            if i.productID != 0 { d[kIOHIDProductIDKey] = i.productID }
            if !i.product.isEmpty { d[kIOHIDProductKey] = i.product }
            return d
        }
        IOHIDManagerSetDeviceMatchingMultiple(m, dicts as CFArray)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(m, { p, _, _, dev in
            guard let p = p else { return }
            Unmanaged<Monitor>.fromOpaque(p).takeUnretainedValue().deviceArrived(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(m, { p, _, _, dev in
            guard let p = p else { return }
            Unmanaged<Monitor>.fromOpaque(p).takeUnretainedValue().deviceRemoved(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(m, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        grabManager = m
        sweep()
    }

    private func closeAll() {
        for (dev, state) in opened {
            if case .failed = state { continue }
            IOHIDDeviceUnscheduleFromRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        opened.removeAll()
        failedAt.removeAll()
        pressed.removeAll()
        heldKeys.removeAll()
    }

    /// Opens any matching interface not yet opened and forgets ones that left. Called
    /// from the arrival callback and from every refresh, so a missed callback costs at
    /// most three seconds.
    func sweep() {
        guard let m = grabManager, inputMonitoringGranted else { return }
        let present = (IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice>) ?? []
        for d in present {
            if opened[d] == nil {
                openDevice(d)
            } else if case .failed = opened[d]!, Date().timeIntervalSince(failedAt[d] ?? .distantPast) > 10 {
                // Retry refused interfaces every 10s: the other holder may have let go.
                openDevice(d)
            }
        }
        for d in Array(opened.keys) where !present.contains(d) {
            opened.removeValue(forKey: d)
            failedAt.removeValue(forKey: d)
        }
        summarise()
    }

    private func deviceArrived(_ dev: IOHIDDevice) {
        guard inputMonitoringGranted, opened[dev] == nil else { return }
        openDevice(dev)
        summarise()
        refreshSoon()
    }

    private func deviceRemoved(_ dev: IOHIDDevice) {
        if opened.removeValue(forKey: dev) != nil {
            log("Button interface went away")
            summarise()
            refreshSoon()
        }
    }

    private func openDevice(_ dev: IOHIDDevice) {
        let usagePage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsagePageKey as CFString) as? Int) ?? 0
        let usage = (IOHIDDeviceGetProperty(dev, kIOHIDPrimaryUsageKey as CFString) as? Int) ?? 0
        let label = interfaceLabel(usagePage: usagePage, usage: usage)
        var state: DeviceGrab
        var r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if r == 0 {
            state = .seized
        } else {
            let seizeErr = r
            r = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            state = r == 0 ? .listening(seizeErr) : .failed(r)
        }
        if case .failed = state {} else {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            IOHIDDeviceRegisterInputValueCallback(dev, { p, _, _, value in
                guard let p = p else { return }
                Unmanaged<Monitor>.fromOpaque(p).takeUnretainedValue().handleInput(value)
            }, ctx)
            IOHIDDeviceScheduleWithRunLoop(dev, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
        let previous = opened[dev]
        opened[dev] = state
        if case .failed = state { failedAt[dev] = Date() } else { failedAt.removeValue(forKey: dev) }
        guard previous != state else { return } // retry with the same result: stay quiet
        switch state {
        case .seized: log("\(label) interface: exclusive")
        case .listening(let e): log("\(label) interface: listening, seize refused \(hex(e))")
        case .failed(let e):
            log("\(label) interface: could not open \(hex(e))"
                + (e == kReturnExclusiveAccess ? ", another app holds it" : ""))
        }
    }

    private func interfaceLabel(usagePage: Int, usage: Int) -> String {
        switch (usagePage, usage) {
        case (1, 6), (1, 7): return "keyboard"
        case (1, 2): return "mouse"
        case (1, 1): return "pointer"
        case (0x0C, 1): return "consumer"
        case (1, 0x80): return "system control"
        default: return "page \(usagePage) usage \(usage)"
        }
    }

    private func summarise() {
        let states = Array(opened.values)
        var seized = 0, listening = 0, failed = 0
        var listenErr: IOReturn = 0, failErr: IOReturn = 0
        for s in states {
            switch s {
            case .seized: seized += 1
            case .listening(let e): listening += 1; listenErr = e
            case .failed(let e): failed += 1; failErr = e
            }
        }
        if states.isEmpty {
            grab = .idle
            grabDetail = "no interface present"
        } else if seized > 0 {
            grab = .seized
            grabDetail = "\(seized) of \(states.count) interface\(states.count == 1 ? "" : "s") exclusive"
                + (listening > 0 ? ", \(listening) listening" : "") + (failed > 0 ? ", \(failed) refused" : "")
        } else if listening > 0 {
            grab = .listening(listenErr)
            grabDetail = "\(listening) listening" + (failed > 0 ? ", \(failed) refused" : "")
        } else if failErr == kReturnNotPermitted {
            grab = .noPermission
            grabDetail = "macOS refused: Input Monitoring not granted to this build"
        } else {
            grab = .failed(failErr)
            grabDetail = "all \(failed) refused"
        }
    }

    private func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        guard isButtonLike(usagePage: page, usage: usage) else { return }
        let t = Trigger(usagePage: page, usage: usage)
        if IOHIDValueGetIntegerValue(value) == 0 {
            pressed.remove(t)
            if let a = heldKeys.removeValue(forKey: t) {
                postKey(a, down: false)
                log("\(t.name) released → key up \(a.value)")
            }
            return
        }
        guard !pressed.contains(t) else { return } // key repeat
        pressed.insert(t)
        lastPress = (Date(), t)
        if learning {
            learned = t
            learning = false
            log("Learned press: \(t.name)")
            NSApp.stopModal(withCode: .OK)
            return
        }
        if let b = bindings.first(where: { $0.trigger == t }) {
            if let last = lastFire[b.id], Date().timeIntervalSince(last) < 0.25 { return }
            lastFire[b.id] = Date()
            if b.action.kind == .keystroke && b.action.hold {
                if AXIsProcessTrusted() {
                    heldKeys[t] = b.action
                    postKey(b.action, down: true)
                    log("\(t.name) held → key down \(b.action.value)")
                } else {
                    requestAccessibility()
                    log("\(t.name): Accessibility permission missing")
                }
            } else if let err = run(b.action) {
                log("\(t.name): \(err)")
            } else {
                log("\(t.name) → \(b.action.name)")
            }
        } else {
            log("Unbound press: \(t.name)")
        }
        refreshSoon()
    }

    // MARK: actions

    /// Runs an action. Returns an error message, or nil on success.
    @discardableResult
    func run(_ a: Action) -> String? {
        switch a.kind {
        case .none:
            return "no action set"
        case .openApp, .toggleApp:
            let url = URL(fileURLWithPath: a.value)
            guard FileManager.default.fileExists(atPath: a.value) else { return "app not found at \(a.value)" }
            let running = NSRunningApplication.runningApplications(withBundleIdentifier:
                Bundle(url: url)?.bundleIdentifier ?? "").first
            if a.kind == .toggleApp, let app = running, app.isActive {
                app.hide()
                return nil
            }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
            return nil
        case .shortcut:
            return shell("/usr/bin/shortcuts", ["run", a.value])
        case .keystroke:
            guard AXIsProcessTrusted() else {
                requestAccessibility()
                return "Accessibility permission missing"
            }
            postKey(a, down: true)
            postKey(a, down: false)
            return nil
        case .url:
            guard let u = URL(string: a.value), u.scheme != nil else { return "not a valid URL" }
            NSWorkspace.shared.open(u)
            return nil
        case .shell:
            return shell("/bin/sh", ["-c", a.value])
        }
    }

    /// Posts the keystroke the way a keyboard would: each modifier as its own key
    /// event, then the key, in reverse on release. Apps that watch raw events for a
    /// hotkey (push-to-talk tools do) need to see the modifier keys themselves, not
    /// just a flag on the main key. fn in particular is only ever seen as its own key.
    private func postKey(_ a: Action, down: Bool) {
        let src = CGEventSource(stateID: .hidSystemState)
        let wanted = CGEventFlags(rawValue: a.flags)
        let modifiers: [(CGEventFlags, CGKeyCode)] = [
            (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55), (.maskSecondaryFn, 63),
        ].filter { wanted.contains($0.0) }

        func post(_ code: CGKeyCode, _ isDown: Bool, _ flags: CGEventFlags) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: isDown) else { return }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }

        if down {
            var flags: CGEventFlags = []
            for (flag, code) in modifiers {
                flags.insert(flag)
                post(code, true, flags)
            }
            post(CGKeyCode(a.keyCode), true, flags)
        } else {
            var flags = wanted
            post(CGKeyCode(a.keyCode), false, flags)
            for (flag, code) in modifiers.reversed() {
                flags.remove(flag)
                post(code, false, flags)
            }
        }
    }

    private func shell(_ path: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let err = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = err
        do { try p.run() } catch { return error.localizedDescription }
        DispatchQueue.global().async { [weak self] in
            let data = err.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus != 0 {
                let msg = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async { self?.log("Command exited \(p.terminationStatus): \(msg)") }
            }
        }
        return nil
    }

    func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func installedShortcuts() -> [String] {
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

    // MARK: refresh

    func refresh() {
        var s = Snapshot()
        s.deviceName = deviceName
        if let hc = IOBluetoothHostController.default() {
            s.btPowerOn = hc.powerState == kBluetoothHCIPowerStateON
        }
        let device = selectedDevice()
        s.paired = device != nil
        s.connected = device?.isConnected() ?? false
        s.hid = hidDevices().filter { matches($0, device: device, name: s.deviceName) }

        // Remember the HID identity the first time we see it so the grab survives sleep.
        if !s.hid.isEmpty {
            let idents = s.hid.map { HIDIdent(vendorID: $0.vendorID, productID: $0.productID, product: $0.product) }
            var merged = deviceIdents
            for i in idents where !merged.contains(i) { merged.append(i) }
            if merged != deviceIdents { deviceIdents = merged }
        }

        if grab == .noPermission && inputMonitoringState == "granted" { rebuildGrab() } else { sweep() }
        // Permission counts as present when TCC says granted, or when an open went through.
        s.inputMonitoring = inputMonitoringState == "granted" || (grab != .noPermission && !opened.isEmpty)
            || (inputMonitoringGranted && opened.isEmpty)
        s.grab = grab
        s.bindings = bindings
        s.accessibility = !s.bindings.contains { $0.action.kind == .keystroke } || AXIsProcessTrusted()
        let procs = processNames()
        s.karabinerRunning = procs.contains {
            $0.hasSuffix("/karabiner_grabber") || $0.hasSuffix("/Karabiner-Core-Service")
        }
        s.karabinerModifies = s.karabinerRunning && karabinerModifies(hid: s.hid)
        s.lastPress = lastPress
        diagnose(&s)
        recordTransitions(from: snapshot, to: s)
        let changed = s != snapshot
        snapshot = s
        hasBaseline = true
        maybeAutoReconnect()
        if changed { onChange?(s) }
    }

    private func diagnose(_ s: inout Snapshot) {
        guard s.deviceName != nil else {
            s.health = .unknown; s.diagnosis = "No button selected"
            s.hint = "Pick it under Device."
            return
        }
        if !s.btPowerOn {
            s.health = .bad; s.diagnosis = "Bluetooth is off"; s.hint = "Turn Bluetooth on."
            return
        }
        if !s.paired {
            s.health = .bad; s.diagnosis = "Button is not paired with this Mac"
            s.hint = "Pair it in Bluetooth settings, then pick it again under Device."
            return
        }
        if !s.connected && !(sleeps && !deviceIdents.isEmpty) {
            s.health = .bad; s.diagnosis = "Button is disconnected"
            s.hint = "Press it once to wake it. If it always sleeps between presses, turn on "
                + "“Button sleeps between presses”."
            return
        }
        if s.connected && s.hid.isEmpty {
            s.health = .warn; s.diagnosis = "Connected, but macOS has not registered it as an input device"
            s.hint = "Usually clears within seconds. If it stays, remove the pairing and pair again."
            return
        }
        if !s.inputMonitoring || s.grab == .noPermission {
            s.health = .bad; s.diagnosis = "Input Monitoring permission missing"
            s.hint = "Use Grant Input Monitoring and allow Clicktalk. Already listed and on? Each rebuild "
                + "changes the app's signature: turn it off and on again, then relaunch."
            return
        }
        switch s.grab {
        case .failed(let e):
            s.health = .bad; s.diagnosis = "Could not open the button (\(hex(e)))"
            if e == kReturnNotPermitted {
                s.hint = "macOS refused this process. Quit Clicktalk and relaunch; Input Monitoring "
                    + "applies at launch. If it persists: tccutil reset ListenEvent local.clicktalk"
            } else if e == kReturnExclusiveAccess {
                s.hint = "Another app holds every interface. Quit Karabiner or the other app and relaunch."
            } else {
                s.hint = "Unexpected error. Remove the pairing, pair again, and check Recent events."
            }
            return
        case .listening(let e):
            s.health = .warn; s.diagnosis = "Listening, but the button's original key also reaches macOS"
            if s.karabinerModifies {
                s.hint = "Karabiner holds this button. In Karabiner-Elements > Devices untick Modify events "
                    + "for it, then relaunch Clicktalk."
            } else if e == kReturnExclusiveAccess {
                s.hint = "Another app holds the button exclusively. Quit it and relaunch Clicktalk."
            } else {
                s.hint = "Exclusive grab refused (\(hex(e))). Bindings still fire."
            }
        case .idle:
            if !s.connected {
                s.health = .good; s.diagnosis = "Sleeping; wakes on press"; s.hint = nil
                return
            }
            s.health = .warn; s.diagnosis = "Waiting to grab the button"; s.hint = "Should clear in a moment."
            return
        case .noPermission:
            return // handled above
        case .seized:
            break
        }
        if s.bindings.isEmpty {
            s.health = .warn; s.diagnosis = "Button grabbed, no action bound yet"
            s.hint = "Use Add button binding and press the button."
            return
        }
        if s.bindings.contains(where: { $0.action.kind == .none }) {
            s.health = .warn; s.diagnosis = "A binding has no action"
            s.hint = "Open Bindings and set one."
            return
        }
        if !s.accessibility {
            s.health = .warn; s.diagnosis = "Accessibility permission missing for keystrokes"
            s.hint = "Use Grant Accessibility, then allow Clicktalk in the privacy pane."
            return
        }
        if s.grab == .seized {
            s.health = .good
            s.diagnosis = s.connected ? "Ready: \(s.bindings.count) binding\(s.bindings.count == 1 ? "" : "s")"
                                      : "Sleeping; wakes on press"
            s.hint = nil
        }
    }

    private func recordTransitions(from old: Snapshot, to new: Snapshot) {
        let now = Date()
        if !hasBaseline {
            if new.connected { connectedSince = now } else { disconnectedSince = now }
            return
        }
        if old.connected != new.connected {
            if new.connected {
                let gap = disconnectedSince.map { " after \(ago($0))" } ?? ""
                log("Bluetooth connected\(gap)")
                connectedSince = now
                disconnectedSince = nil
            } else {
                log(sleeps ? "Button went to sleep" : "Bluetooth disconnected")
                disconnectedSince = now
                connectedSince = nil
            }
        }
        if old.hid.isEmpty != new.hid.isEmpty {
            if let h = new.hid.first {
                log("macOS registered input device \(h.idString) (\(h.kind), \(h.transport))")
            } else {
                log("Input device gone")
            }
        }
        if old.inputMonitoring != new.inputMonitoring {
            log(new.inputMonitoring ? "Input Monitoring granted" : "Input Monitoring revoked")
        }
        if old.btPowerOn != new.btPowerOn {
            log(new.btPowerOn ? "Bluetooth radio on" : "Bluetooth radio off")
        }
    }

    // MARK: reconnect

    private func maybeAutoReconnect() {
        guard autoReconnect, snapshot.deviceName != nil, snapshot.paired, !snapshot.connected,
              snapshot.btPowerOn, Date().timeIntervalSince(lastReconnectAttempt) > 20 else { return }
        reconnect(manual: false)
    }

    func reconnect(manual: Bool) {
        guard let d = selectedDevice() else { log("Reconnect: button is not paired"); return }
        lastReconnectAttempt = Date()
        let r = d.openConnection(self)
        if r == 0 {
            log(manual ? "Reconnect requested" : "Auto-reconnect requested")
        } else {
            log("Reconnect request refused (\(hex(r))). A BLE button must be pressed to wake it.")
        }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        log(status == 0 ? "Reconnect succeeded" : "Reconnect failed (\(hex(status))). Press the button to wake it.")
        refresh()
    }
}

// MARK: - Keystroke recording

/// Records the next key press through a listen-only session event tap. Unlike a view's
/// keyDown, the tap sees a key even when another app owns it as a global hotkey, which
/// is exactly the case when recording a dictation app's shortcut. Needs Input Monitoring,
/// which Clicktalk already has by this point.
final class KeyRecorder {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var onKey: ((Int, CGEventFlags, String?) -> Void)?

    func start() -> Bool {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, ctx in
                if type == .keyDown, let ctx = ctx {
                    let r = Unmanaged<KeyRecorder>.fromOpaque(ctx).takeUnretainedValue()
                    let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
                    let flags = event.flags.intersection(
                        [.maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn])
                    let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers
                    DispatchQueue.main.async { r.onKey?(code, flags, chars) }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: ctx) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
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

/// Parses "cmd+shift+space", "option+k", "ctrl+alt+f5" into a key code and flags.
/// US layout key codes; letters, digits, punctuation, function keys and navigation keys.
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
    var flags: CGEventFlags = []
    var key: String?
    for raw in text.lowercased().split(whereSeparator: { $0 == "+" || $0 == " " }) {
        let part = String(raw).trimmingCharacters(in: .whitespaces)
        switch part {
        case "cmd", "command", "⌘": flags.insert(.maskCommand)
        case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
        case "ctrl", "control", "⌃": flags.insert(.maskControl)
        case "shift", "⇧": flags.insert(.maskShift)
        case "fn", "function": flags.insert(.maskSecondaryFn)
        case "": break
        default: key = part
        }
    }
    guard let k = key, let code = codes[k] else { return nil }
    let name = keystrokeName(keyCode: UInt16(code), flags: nsFlags(flags), chars: k.count == 1 ? k : nil)
    return (code, flags, name)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let monitor = Monitor()
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    private var shortcutsMenus: [NSMenu: UUID] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        monitor.onChange = { [weak self] s in
            self?.updateIcon(s)
            self?.rebuildMenu()
        }
        monitor.start()
        updateIcon(monitor.snapshot)
        rebuildMenu()
    }

    func menuWillOpen(_ m: NSMenu) {
        if m === menu {
            monitor.refresh()
            rebuildMenu()
        }
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        guard let id = shortcutsMenus[m] else { return }
        m.removeAllItems()
        let names = monitor.installedShortcuts()
        if names.isEmpty {
            m.addItem(info("No shortcuts found. Create one in the Shortcuts app."))
        }
        for n in names {
            let i = action(n, #selector(pickShortcut(_:)))
            i.representedObject = [id.uuidString, n]
            m.addItem(i)
        }
    }

    // MARK: icon

    private func updateIcon(_ s: Snapshot) {
        var label = ""
        switch s.health {
        case .good: label = s.connected ? "" : "zz"
        case .unknown: label = "?"
        case .warn, .bad:
            if !s.btPowerOn || !s.paired || (!s.connected && !monitor.sleeps) { label = "BT" }
            else if s.connected && s.hid.isEmpty { label = "HID" }
            else if !s.inputMonitoring || !s.accessibility { label = "PERM" }
            else if s.bindings.isEmpty { label = "BIND" }
            else { label = "GRAB" }
        }
        let title = NSMutableAttributedString(
            string: "●",
            attributes: [.foregroundColor: s.health.color, .font: NSFont.systemFont(ofSize: 15)])
        if !label.isEmpty {
            title.append(NSAttributedString(
                string: " " + label,
                attributes: [.foregroundColor: NSColor.labelColor,
                             .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)]))
        }
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = "Clicktalk: \(s.diagnosis)"
    }

    // MARK: menu helpers

    private func action(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        i.isEnabled = true
        return i
    }

    private func info(_ title: String, bold: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = bold
        if bold {
            i.attributedTitle = NSAttributedString(
                string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        }
        return i
    }

    private func submenu(_ title: String, _ m: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = m
        i.isEnabled = true
        return i
    }

    // MARK: menu

    private func rebuildMenu() {
        let s = monitor.snapshot
        menu.removeAllItems()
        shortcutsMenus.removeAll()

        menu.addItem(info(s.diagnosis, bold: true))
        if let hint = s.hint { menu.addItem(info(hint)) }
        menu.addItem(.separator())

        menu.addItem(info("Button: \(s.deviceName ?? "none selected")"))
        if s.paired {
            if s.connected {
                let since = monitor.connectedSince.map { " for \(ago($0))" } ?? ""
                menu.addItem(info("Bluetooth: connected\(since)"))
            } else {
                let since = monitor.disconnectedSince.map { " for \(ago($0))" } ?? ""
                menu.addItem(info("Bluetooth: \(monitor.sleeps ? "asleep" : "disconnected")\(since)"))
            }
        } else if s.deviceName != nil {
            menu.addItem(info("Bluetooth: not paired"))
        }
        if s.hid.isEmpty {
            menu.addItem(info("Input device: \(s.connected ? "not registered" : "absent")"))
        } else {
            for h in s.hid {
                menu.addItem(info("Input device: \(h.kind) \(h.idString) via \(h.transport)"))
            }
        }
        menu.addItem(info("Input Monitoring: \(monitor.inputMonitoringState)"
            + (s.inputMonitoring ? "" : ", NOT usable by this build")))
        let grabText: String
        switch s.grab {
        case .idle: grabText = monitor.grabDetail.isEmpty ? "waiting for the button's identity" : monitor.grabDetail
        case .noPermission: grabText = "blocked, no permission"
        case .seized: grabText = monitor.grabDetail
        case .listening(let e): grabText = "\(monitor.grabDetail), seize refused \(hex(e))"
        case .failed(let e): grabText = "\(monitor.grabDetail), last error \(hex(e))"
        }
        menu.addItem(info("Grab: \(grabText)"))
        if s.karabinerRunning {
            menu.addItem(info("Karabiner: running, \(s.karabinerModifies ? "CLAIMS this button" : "not touching this button")"))
        }
        if let (d, t) = s.lastPress {
            menu.addItem(info("Last press: \(t.name) at \(timeFmt.string(from: d))"))
        }
        menu.addItem(.separator())

        // Bindings
        let bind = NSMenu()
        bind.autoenablesItems = false
        if s.bindings.isEmpty { bind.addItem(info("None yet")) }
        for b in s.bindings {
            let sub = NSMenu()
            sub.autoenablesItems = false
            let set = NSMenu()
            set.autoenablesItems = false
            for kind in ActionKind.allCases where kind != .none {
                if kind == .shortcut {
                    let sm = NSMenu()
                    sm.autoenablesItems = false
                    sm.delegate = self
                    shortcutsMenus[sm] = b.id
                    set.addItem(submenu(kind.label, sm))
                } else {
                    let i = action(kind.label + "…", #selector(setAction(_:)))
                    i.representedObject = [b.id.uuidString, kind.rawValue]
                    set.addItem(i)
                }
            }
            sub.addItem(submenu("Set action", set))
            let test = action("Test action", #selector(testBinding(_:)))
            test.representedObject = b.id.uuidString
            test.isEnabled = b.action.kind != .none
            sub.addItem(test)
            let rm = action("Remove binding", #selector(removeBinding(_:)))
            rm.representedObject = b.id.uuidString
            sub.addItem(rm)
            bind.addItem(submenu("\(b.trigger.name)  →  \(b.action.name)", sub))
        }
        bind.addItem(.separator())
        let add = action("Add button binding…", #selector(addBinding))
        add.isEnabled = s.deviceName != nil
        bind.addItem(add)
        menu.addItem(submenu("Bindings (\(s.bindings.count))", bind))
        menu.addItem(.separator())

        if !s.inputMonitoring {
            menu.addItem(action("Grant Input Monitoring…", #selector(grantInputMonitoring)))
        }
        if !s.accessibility {
            menu.addItem(action("Grant Accessibility…", #selector(grantAccessibility)))
        }
        let rc = action("Reconnect now", #selector(reconnectNow), key: "r")
        rc.isEnabled = s.paired && !s.connected
        menu.addItem(rc)
        let auto = action("Auto-reconnect every 20s while disconnected", #selector(toggleAuto))
        auto.state = monitor.autoReconnect ? .on : .off
        menu.addItem(auto)
        let sl = action("Button sleeps between presses", #selector(toggleSleeps))
        sl.state = monitor.sleeps ? .on : .off
        menu.addItem(sl)
        menu.addItem(.separator())

        let open = NSMenu()
        open.autoenablesItems = false
        open.addItem(action("Input Monitoring privacy pane", #selector(openInputMonitoring)))
        open.addItem(action("Accessibility privacy pane", #selector(openAccessibility)))
        open.addItem(action("Bluetooth settings", #selector(openBluetooth)))
        open.addItem(action("Shortcuts app", #selector(openShortcuts)))
        if s.karabinerRunning {
            open.addItem(action("Karabiner-Elements", #selector(openKarabiner)))
        }
        menu.addItem(submenu("Open", open))

        let dev = NSMenu()
        dev.autoenablesItems = false
        let paired = monitor.pairedDevices()
        if paired.isEmpty { dev.addItem(info("No paired Bluetooth devices")) }
        for d in paired {
            let n = d.name ?? d.addressString ?? "?"
            let i = action("\(n)\(d.isConnected() ? "  (connected)" : "")", #selector(selectDevice(_:)))
            i.representedObject = n
            i.state = n == s.deviceName ? .on : .off
            dev.addItem(i)
        }
        menu.addItem(submenu("Device", dev))

        let ev = NSMenu()
        ev.autoenablesItems = false
        if monitor.events.isEmpty { ev.addItem(info("Nothing yet")) }
        for e in monitor.events.prefix(25) {
            ev.addItem(info("\(timeFmt.string(from: e.date))  \(e.text)"))
        }
        menu.addItem(submenu("Recent events", ev))
        menu.addItem(.separator())

        if #available(macOS 13, *) {
            let li = action("Launch at login", #selector(toggleLogin))
            li.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(li)
        }
        menu.addItem(action("Quit Clicktalk", #selector(quit), key: "q"))
    }

    // MARK: binding flow

    @objc func addBinding() {
        guard monitor.inputMonitoringGranted else {
            grantInputMonitoring()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Press the button now"
        a.informativeText = "Clicktalk learns which key the button sends. Cancel with the button below."
        a.addButton(withTitle: "Cancel")
        monitor.learning = true
        let r = a.runModal()
        monitor.learning = false
        guard r == .OK, let t = monitor.learned else { return }
        if let existing = monitor.bindings.first(where: { $0.trigger == t }) {
            monitor.log("\(t.name) is already bound to \(existing.action.name)")
            chooseAction(for: existing.id)
            return
        }
        let b = Binding(trigger: t)
        monitor.bindings.append(b)
        chooseAction(for: b.id)
    }

    private func chooseAction(for id: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "What should the button do?"
        a.informativeText = "You can change this later under Bindings."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        let kinds = ActionKind.allCases.filter { $0 != .none }
        for k in kinds { popup.addItem(withTitle: k.label) }
        a.accessoryView = popup
        a.addButton(withTitle: "Next")
        a.addButton(withTitle: "Later")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        configure(kind: kinds[popup.indexOfSelectedItem], for: id)
    }

    @objc func setAction(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let id = UUID(uuidString: pair[0]), let kind = ActionKind(rawValue: pair[1]) else { return }
        configure(kind: kind, for: id)
    }

    @objc func pickShortcut(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let id = UUID(uuidString: pair[0]) else { return }
        update(id) { $0.action = Action(kind: .shortcut, value: pair[1]) }
    }

    private func configure(kind: ActionKind, for id: UUID) {
        NSApp.activate(ignoringOtherApps: true)
        switch kind {
        case .openApp, .toggleApp:
            let panel = NSOpenPanel()
            panel.title = "Choose the app"
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.allowedContentTypes = [.application]
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            update(id) { $0.action = Action(kind: kind, value: url.path) }
        case .shortcut:
            let names = monitor.installedShortcuts()
            guard !names.isEmpty else {
                alert("No shortcuts found", "Create one in the Shortcuts app first, then pick it under Bindings.")
                return
            }
            let a = NSAlert()
            a.messageText = "Which Shortcut?"
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26), pullsDown: false)
            popup.addItems(withTitles: names)
            a.accessoryView = popup
            a.addButton(withTitle: "Save")
            a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
            update(id) { $0.action = Action(kind: .shortcut, value: popup.titleOfSelectedItem ?? "") }
        case .keystroke:
            var keyCode = 0
            var flags: CGEventFlags = []
            var name = ""
            let recorder = KeyRecorder()
            var recorded = false
            if recorder.start() {
                let a = NSAlert()
                a.messageText = "Press the keystroke now"
                a.informativeText = "Hold the modifiers and tap the key, for example ⌥ Space. "
                    + "If another app owns that shortcut it will fire once; that is fine."
                a.addButton(withTitle: "Type it instead")
                a.addButton(withTitle: "Cancel")
                recorder.onKey = { code, f, chars in
                    keyCode = code
                    flags = f
                    name = keystrokeName(keyCode: UInt16(code), flags: nsFlags(f), chars: chars)
                    recorded = true
                    NSApp.stopModal(withCode: .OK)
                }
                let r = a.runModal()
                recorder.stop()
                if r == .alertSecondButtonReturn { return }
                if r == .OK && recorded {
                    // fall through to the Press/Hold question
                } else if r != .alertFirstButtonReturn {
                    return
                }
            }
            if !recorded {
                guard let typed = askText("Type the keystroke",
                                          "Examples: cmd+shift+space, option+k, ctrl+alt+f5.", initial: "") else { return }
                guard let parsed = parseKeystroke(typed) else {
                    alert("Could not read that", "Use names like cmd, shift, option, ctrl, fn and a key such as space, k or f5.")
                    return
                }
                keyCode = parsed.keyCode
                flags = parsed.flags
                name = parsed.name
            }
            let mode = NSAlert()
            mode.messageText = "How should \(name) be sent?"
            mode.informativeText = "Press: a quick tap, for toggles and app hotkeys. "
                + "Hold: key stays down while the button is held, for push-to-talk dictation such as Handy."
            mode.addButton(withTitle: "Press")
            mode.addButton(withTitle: "Hold")
            let hold = mode.runModal() == .alertSecondButtonReturn
            update(id) {
                $0.action = Action(kind: .keystroke, value: name, keyCode: keyCode,
                                   flags: flags.rawValue, hold: hold)
            }
            if !AXIsProcessTrusted() { monitor.requestAccessibility() }
        case .url:
            guard let v = askText("Open which URL?", "Any URL works: https://…, or an app scheme.",
                                  initial: "https://") else { return }
            update(id) { $0.action = Action(kind: .url, value: v) }
        case .shell:
            guard let v = askText("Run which command?", "Runs with /bin/sh -c. Output is discarded; "
                                  + "a non-zero exit is logged under Recent events.", initial: "") else { return }
            update(id) { $0.action = Action(kind: .shell, value: v) }
        case .none:
            break
        }
    }

    private func update(_ id: UUID, _ change: (inout Binding) -> Void) {
        var all = monitor.bindings
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[i])
        monitor.bindings = all
        monitor.log("Bound \(all[i].trigger.name) → \(all[i].action.name)")
    }

    private func askText(_ title: String, _ message: String, initial: String) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.stringValue = initial
        a.accessoryView = field
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        a.layout()
        a.window.initialFirstResponder = field
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }

    @objc func testBinding(_ sender: NSMenuItem) {
        guard let id = UUID(uuidString: sender.representedObject as? String ?? ""),
              let b = monitor.bindings.first(where: { $0.id == id }) else { return }
        if let err = monitor.run(b.action) { alert("Action failed", err) } else { monitor.log("Tested \(b.action.name)") }
    }

    @objc func removeBinding(_ sender: NSMenuItem) {
        guard let id = UUID(uuidString: sender.representedObject as? String ?? "") else { return }
        monitor.bindings.removeAll { $0.id == id }
        monitor.log("Removed binding")
    }

    // MARK: other actions

    @objc func grantInputMonitoring() {
        monitor.requestInputMonitoring()
        openInputMonitoring()
    }

    @objc func grantAccessibility() {
        monitor.requestAccessibility()
    }

    @objc func reconnectNow() { monitor.reconnect(manual: true) }
    @objc func toggleAuto() { monitor.autoReconnect.toggle() }
    @objc func toggleSleeps() { monitor.sleeps.toggle() }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func selectDevice(_ sender: NSMenuItem) {
        monitor.deviceName = sender.representedObject as? String
    }

    @objc func toggleLogin() {
        guard #available(macOS 13, *) else { return }
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
            monitor.log(svc.status == .enabled ? "Launch at login on" : "Launch at login off")
        } catch {
            monitor.log("Launch at login: \(error.localizedDescription)")
        }
    }

    private func openPane(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }

    @objc func openInputMonitoring() {
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
    @objc func openAccessibility() {
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    @objc func openBluetooth() { openPane("x-apple.systempreferences:com.apple.BluetoothSettings") }
    @objc func openShortcuts() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Shortcuts"]
        try? p.run()
    }
    @objc func openKarabiner() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", "Karabiner-Elements"]
        try? p.run()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
