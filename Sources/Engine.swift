// Clicktalk engine: watches one Bluetooth button, grabs it, and runs actions.
// No UI code lives here; the menu bar item, the window and the setup guide all
// read `Monitor` and call its methods.
//
// Layers, top to bottom. The first failing layer becomes the status.
//   0. Bluetooth permission for Clicktalk.
//   1. Bluetooth radio on, button paired, button connected.
//   2. macOS registered the button as an HID input device.
//   3. Input Monitoring permission granted to Clicktalk.
//   4. Clicktalk holds the device exclusively (seized), so its key never reaches macOS.
//      Falls back to listening, where the original key also passes through.
//   5. At least one binding: a learned button press mapped to an action.
//   6. Accessibility permission, when an action presses keys.
//
// Karabiner-Elements is not needed. If it is installed and holds the same device,
// the seize fails and the status says what to untick.

import AppKit
import Combine
import CoreBluetooth
import IOBluetooth
import IOKit.hid

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

struct ButtonBinding: Codable, Equatable {
    var id: UUID = UUID()
    var trigger: Trigger
    var action: Action = Action()
}

enum GrabState: Equatable {
    case idle, noPermission, seized, listening(Int32), failed(Int32)
}

struct Snapshot: Equatable {
    var deviceName: String?
    var bluetoothAllowed = true
    var btPowerOn = true
    var paired = false
    var connected = false
    var hid: [HIDInfo] = []
    var inputMonitoring = false
    var accessibility = true
    var grab: GrabState = .idle
    var bindings: [ButtonBinding] = []
    /// Bindings changed outside Clicktalk; they do not run until the owner approves them.
    var unapproved: [UUID] = []
    /// False when the chosen button was changed outside Clicktalk.
    var deviceApproved = true
    var karabinerRunning = false
    var karabinerModifies = false
    var lastPress: (Date, Trigger)?
    var health: Health = .unknown
    var diagnosis = ""
    var hint: String?

    static func == (a: Snapshot, b: Snapshot) -> Bool {
        a.deviceName == b.deviceName && a.bluetoothAllowed == b.bluetoothAllowed
            && a.btPowerOn == b.btPowerOn && a.paired == b.paired
            && a.connected == b.connected && a.hid == b.hid && a.inputMonitoring == b.inputMonitoring
            && a.accessibility == b.accessibility && a.grab == b.grab && a.bindings == b.bindings
            && a.unapproved == b.unapproved && a.deviceApproved == b.deviceApproved
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
    // 0xFFFFFFFF is the placeholder usage of an array input element: it carries no key
    // of its own, and some clickers send it straight after the real key on every press.
    guard usage != 0, usage <= 0xFFFF, usagePage < 0xFF00 else { return false }
    switch usagePage {
    case 0x07: return usage >= 0x04
    case 0x09: return true
    case 0x0C: return usage != 0x238 && usage != 0x239 // AC Pan, scroll
    case 0x01: return (0x81...0x83).contains(usage)
    default: return false
    }
}

// MARK: - Monitor

final class Monitor: NSObject, ObservableObject, CBCentralManagerDelegate {
    let objectWillChange = ObservableObjectPublisher()
    /// Called after every snapshot change. The menu bar item uses it.
    var onChange: ((Snapshot) -> Void)?
    private(set) var snapshot = Snapshot()
    private(set) var events: [Event] = []
    private(set) var connectedSince: Date?
    private(set) var disconnectedSince: Date?
    private(set) var lastPress: (Date, Trigger)?
    /// What the most recent press did, for the test step and the overview.
    private(set) var lastOutcome: (Date, String)?
    /// The most recent press that ran its action successfully.
    private(set) var lastFired: (Date, String)?

    /// While true, the next press is not run but handed to `onLearned`.
    var learning = false {
        didSet { objectWillChange.send() }
    }
    var onLearned: ((Trigger) -> Void)?
    private var central: CBCentralManager?

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

    let seal = SettingsSeal()

    /// The chosen button's name. Setting it is an owner action in the app, so it is sealed.
    var deviceName: String? {
        get { defaults.string(forKey: "deviceName") }
        set {
            defaults.set(newValue, forKey: "deviceName")
            if let n = newValue { seal.seal(SettingsSeal.deviceID, Data(n.utf8)) } else { seal.remove(SettingsSeal.deviceID) }
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
        set { objectWillChange.send(); defaults.set(newValue, forKey: "autoReconnect"); refresh() }
    }

    /// The button disconnects between presses to save battery and wakes on press.
    var sleeps: Bool {
        get { defaults.bool(forKey: "sleeps") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "sleeps"); refresh() }
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

    /// The chosen button's name, but only if the owner set it in the app.
    var trustedDeviceName: String? {
        guard let n = deviceName, seal.isSealed(SettingsSeal.deviceID, Data(n.utf8)) else { return nil }
        return n
    }

    /// Writes come only from the app's own editors. Bindings this write adds or changes
    /// are sealed as the owner's. Bindings it leaves untouched keep whatever seal they
    /// had, so editing one binding never approves another that changed outside the app.
    var bindings: [ButtonBinding] {
        get {
            guard let d = defaults.data(forKey: "bindings") else { return [] }
            return (try? JSONDecoder().decode([ButtonBinding].self, from: d)) ?? []
        }
        set {
            let before = Dictionary(bindings.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "bindings")
            for b in newValue where before[b.id] != b {
                seal.seal(SettingsSeal.id(b), SettingsSeal.data(b))
            }
            seal.keepOnly(Set(newValue.map { SettingsSeal.id($0) }), prefix: "binding:")
            refresh()
        }
    }

    func isApproved(_ b: ButtonBinding) -> Bool {
        seal.isSealed(SettingsSeal.id(b), SettingsSeal.data(b))
    }

    /// The owner reviewed a binding that changed outside the app and accepts it.
    func approve(_ id: UUID) {
        guard let b = bindings.first(where: { $0.id == id }) else { return }
        seal.seal(SettingsSeal.id(b), SettingsSeal.data(b))
        log("Approved binding \(b.trigger.name) → \(b.action.name)")
        refresh()
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
        objectWillChange.send()
        events.insert(Event(date: Date(), text: text), at: 0)
        if events.count > 60 { events.removeLast(events.count - 60) }
        // Not printed in release builds: standard output can be redirected by whoever
        // launches the app, and the log names every key press.
        #if DEBUG
        print("[\(timeFmt.string(from: Date()))] \(text)")
        #endif
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

    // MARK: Bluetooth permission

    var bluetoothAuthorization: CBManagerAuthorization { CBManager.authorization }

    /// Creating a central manager is what makes macOS show the Bluetooth prompt.
    func requestBluetooth() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil)
            log("Bluetooth access requested")
        }
        refreshSoon()
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        refresh()
    }

    // MARK: data sources

    func pairedDevices() -> [IOBluetoothDevice] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
    }

    func selectedDevice() -> IOBluetoothDevice? {
        guard let name = trustedDeviceName else { return nil }
        return pairedDevices().first { ($0.name ?? "") == name }
    }

    /// Only the owner's chosen Bluetooth button may be opened. The stored HID identity
    /// narrows which devices the system reports, but it lives in the same editable
    /// preferences, so each device is checked against the chosen button before opening.
    private func isChosenButton(_ dev: IOHIDDevice) -> Bool {
        func prop(_ key: String) -> String { (IOHIDDeviceGetProperty(dev, key as CFString) as? String) ?? "" }
        guard prop(kIOHIDTransportKey).localizedCaseInsensitiveContains("bluetooth"),
              let name = trustedDeviceName else { return false }
        if !name.isEmpty, prop(kIOHIDProductKey).caseInsensitiveCompare(name) == .orderedSame { return true }
        if let addr = selectedDevice()?.addressString {
            let a = hexDigits(addr), s = hexDigits(prop(kIOHIDSerialNumberKey))
            if a.count == 12 && a == s { return true }
        }
        return false
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

    private var procRefreshing = false

    /// Returns the cached process list and refreshes it in the background when stale,
    /// so a button press never waits on a `ps` spawn on the main thread.
    private func processNames() -> [String] {
        if Date().timeIntervalSince(procCache.at) > 5 && !procRefreshing {
            procRefreshing = true
            DispatchQueue.global(qos: .utility).async { [weak self] in
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
                DispatchQueue.main.async {
                    self?.procCache = (Date(), names)
                    self?.procRefreshing = false
                }
            }
        }
        return procCache.names
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
        for d in present where isChosenButton(d) {
            if opened[d] == nil {
                openDevice(d)
            } else if case .failed = opened[d]!, Date().timeIntervalSince(failedAt[d] ?? .distantPast) > 10 {
                // Retry refused interfaces every 10s: the other holder may have let go.
                openDevice(d)
            }
        }
        for d in Array(opened.keys) where !present.contains(d) || !isChosenButton(d) {
            if present.contains(d), opened[d] != nil {
                if case .failed = opened[d]! {} else {
                    IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
                    IOHIDDeviceClose(d, IOOptionBits(kIOHIDOptionsTypeNone))
                }
            }
            opened.removeValue(forKey: d)
            failedAt.removeValue(forKey: d)
        }
        summarise()
    }

    private func deviceArrived(_ dev: IOHIDDevice) {
        guard inputMonitoringGranted, opened[dev] == nil, isChosenButton(dev) else { return }
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
        objectWillChange.send()
        lastPress = (Date(), t)
        if learning {
            learning = false
            log("Learned press: \(t.name)")
            onLearned?(t)
            return
        }
        let outcome: String
        var fired = false
        if let b = bindings.first(where: { $0.trigger == t }) {
            if let last = lastFire[b.id], Date().timeIntervalSince(last) < 0.25 { return }
            lastFire[b.id] = Date()
            if !isApproved(b) {
                outcome = "\(t.name): not run. This binding changed outside Clicktalk; review it under Bindings."
            } else if b.action.kind == .keystroke && b.action.hold {
                if AXIsProcessTrusted() {
                    heldKeys[t] = b.action
                    postKey(b.action, down: true)
                    outcome = "\(t.name) held → key down \(b.action.value)"
                    fired = true
                } else {
                    outcome = "\(t.name): Accessibility permission missing"
                }
            } else if let err = run(b.action) {
                outcome = "\(t.name): \(err)"
            } else {
                outcome = "\(t.name) → \(b.action.name)"
                fired = true
            }
        } else {
            outcome = "Unbound press: \(t.name)"
        }
        let now = Date()
        if fired { lastFired = (now, outcome) }
        // A clicker that sends a second, unbound key with every press must not hide the
        // result of the bound one.
        let shadowed = !fired && lastFired.map { now.timeIntervalSince($0.0) < 1 } == true
        if !shadowed { lastOutcome = (now, outcome) }
        log(outcome)
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
        // A modifier-only shortcut, such as Right Option alone, has the modifier as its
        // main key; it must not also be pressed as one of the extra modifiers.
        let own = modifierFlag(forKeyCode: a.keyCode)
        var modifiers: [(CGEventFlags, CGKeyCode)] = [
            (.maskControl, 59), (.maskAlternate, 58), (.maskShift, 56), (.maskCommand, 55), (.maskSecondaryFn, 63),
        ].filter { wanted.contains($0.0) }
        if let own = own { modifiers.removeAll { $0.0 == own } }

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
            if let own = own { flags.insert(own) }
            post(CGKeyCode(a.keyCode), true, flags)
        } else {
            var flags = wanted
            if let own = own { flags.remove(own) }
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

    // MARK: refresh

    func refresh() {
        var s = Snapshot()
        s.deviceName = deviceName
        let auth = CBManager.authorization
        s.bluetoothAllowed = auth != .denied && auth != .restricted
        if let hc = IOBluetoothHostController.default() {
            s.btPowerOn = hc.powerState == kBluetoothHCIPowerStateON
        }
        let device = selectedDevice()
        s.paired = device != nil
        s.connected = device?.isConnected() ?? false
        s.hid = hidDevices().filter { matches($0, device: device, name: s.deviceName) }

        // Remember the button's HID identity so the grab survives sleep. While the button is
        // connected, what it reports now replaces whatever was stored, so a stale or
        // planted identity does not linger.
        if !s.hid.isEmpty {
            var idents: [HIDIdent] = []
            for h in s.hid {
                let i = HIDIdent(vendorID: h.vendorID, productID: h.productID, product: h.product)
                if !idents.contains(i) { idents.append(i) }
            }
            if idents != deviceIdents { deviceIdents = idents }
        }

        if grab == .noPermission && inputMonitoringState == "granted" { rebuildGrab() } else { sweep() }
        // Permission counts as present when TCC says granted, or when an open went through.
        s.inputMonitoring = inputMonitoringState == "granted" || (grab != .noPermission && !opened.isEmpty)
            || (inputMonitoringGranted && opened.isEmpty)
        s.grab = grab
        s.bindings = bindings
        s.unapproved = s.bindings.filter { !isApproved($0) }.map { $0.id }
        s.deviceApproved = deviceName == nil || trustedDeviceName != nil
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
        if changed { objectWillChange.send() }
        snapshot = s
        hasBaseline = true
        maybeAutoReconnect()
        if changed { onChange?(s) }
    }

    private func diagnose(_ s: inout Snapshot) {
        guard s.bluetoothAllowed else {
            s.health = .bad; s.diagnosis = "Bluetooth access is off for Clicktalk"
            s.hint = "Open Clicktalk > Permissions and allow Bluetooth."
            return
        }
        guard s.deviceName != nil else {
            s.health = .unknown; s.diagnosis = "No button selected"
            s.hint = "Open Clicktalk and choose your button."
            return
        }
        guard s.deviceApproved else {
            s.health = .warn; s.diagnosis = "Your button choice changed outside Clicktalk"
            s.hint = "Clicktalk ignores it. Open Clicktalk > Button and choose your button again."
                + (seal.lastError.map { " " + $0 } ?? "")
            return
        }
        if !s.btPowerOn {
            s.health = .bad; s.diagnosis = "Bluetooth is off"; s.hint = "Turn Bluetooth on."
            return
        }
        if !s.paired {
            s.health = .bad; s.diagnosis = "Button is not paired with this Mac"
            s.hint = "Pair it in Bluetooth settings, then choose it in Clicktalk > Button."
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
            s.hint = "Open Clicktalk > Permissions and allow Input Monitoring. Already on? Relaunch Clicktalk."
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
                s.hint = "Unexpected error. Remove the pairing, pair again, and check Activity."
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
            s.hint = "Open Clicktalk > Bindings, add a binding and press the button."
            return
        }
        if s.bindings.contains(where: { $0.action.kind == .none }) {
            s.health = .warn; s.diagnosis = "A binding has no action"
            s.hint = "Open Clicktalk > Bindings and choose what it does."
            return
        }
        if !s.unapproved.isEmpty {
            s.health = .warn; s.diagnosis = "A binding changed outside Clicktalk"
            s.hint = "It will not run until you review it. Open Clicktalk > Bindings to approve or remove it."
                + (seal.lastError.map { " " + $0 } ?? "")
            return
        }
        if !s.accessibility {
            s.health = .warn; s.diagnosis = "Accessibility permission missing for keystrokes"
            s.hint = "Open Clicktalk > Permissions and allow Accessibility."
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
