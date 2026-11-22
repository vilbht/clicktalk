// Clicktalk: a menu bar watcher for one Bluetooth button and the Karabiner-Elements
// path it has to travel to become a key press.
//
// Layers it checks, top to bottom:
//   1. Bluetooth radio on, button paired, button connected.
//   2. macOS registered the button as an HID input device (keyboard / pointer).
//   3. karabiner_grabber and karabiner_console_user_server are running.
//   4. karabiner.json has the device with "Modify events" on (ignore == false).
// The first failing layer becomes the diagnosis in the menu and the dot colour.

import AppKit
import IOBluetooth
import IOKit.hid
import ServiceManagement

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
    var idString: String {
        String(format: "%04lx:%04lx", vendorID, productID)
    }
    var kind: String {
        switch (isKeyboard, isPointing) {
        case (true, true): return "keyboard+pointer"
        case (true, false): return "keyboard"
        case (false, true): return "pointer"
        default: return "other"
        }
    }
}

struct KEEntry: Equatable {
    var vendorID: Int
    var productID: Int
    var isKeyboard: Bool
    var isPointing: Bool
    var ignore: Bool
}

enum ModifyState: Equatable { case on, off, noEntry, unreadable, noDevice }

struct Snapshot: Equatable {
    var deviceName: String?
    var address: String?
    var btPowerOn = true
    var paired = false
    var connected = false
    var hid: [HIDInfo] = []
    var grabberRunning = false
    var userServerRunning = false
    var modify: ModifyState = .noDevice
    var grabberLogLine: String?
    var health: Health = .unknown
    var diagnosis = ""
    var hint: String?
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

// MARK: - Monitor

final class Monitor: NSObject {
    var onChange: ((Snapshot) -> Void)?
    private(set) var snapshot = Snapshot()
    private(set) var events: [Event] = []
    private(set) var connectedSince: Date?
    private(set) var disconnectedSince: Date?

    private var hidManager: IOHIDManager!
    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNote: IOBluetoothUserNotification?
    private var timer: Timer?
    private var lastReconnectAttempt = Date.distantPast
    private var procCache: (at: Date, names: [String]) = (.distantPast, [])
    private var hasBaseline = false

    private let defaults = UserDefaults.standard

    var deviceName: String? {
        get { defaults.string(forKey: "deviceName") }
        set {
            defaults.set(newValue, forKey: "deviceName")
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

    static let karabinerConfig = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/karabiner/karabiner.json")

    // MARK: lifecycle

    func start() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(hidManager, nil)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(hidManager, { p, _, _, _ in
            guard let p = p else { return }
            Unmanaged<Monitor>.fromOpaque(p).takeUnretainedValue().hidChanged()
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(hidManager, { p, _, _, _ in
            guard let p = p else { return }
            Unmanaged<Monitor>.fromOpaque(p).takeUnretainedValue().hidChanged()
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Open may be refused without Input Monitoring; enumeration still works, so ignore the result.
        _ = IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))

        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(btConnected(_:device:)))
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        log("Clicktalk started")
        refresh()
    }

    func log(_ text: String) {
        events.insert(Event(date: Date(), text: text), at: 0)
        if events.count > 60 { events.removeLast(events.count - 60) }
        print("[\(timeFmt.string(from: Date()))] \(text)")
    }

    private func hidChanged() {
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
        guard let set = IOHIDManagerCopyDevices(hidManager) as? Set<IOHIDDevice> else { return [] }
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
                    if page == 0x0C && usage == 1 { kb = true } // consumer control: Karabiner treats as keyboard
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

    private func karabinerEntries() -> [KEEntry]? {
        guard let data = try? Data(contentsOf: Monitor.karabinerConfig),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]] else { return nil }
        let profile = profiles.first { ($0["selected"] as? Bool) == true } ?? profiles.first
        let devices = profile?["devices"] as? [[String: Any]] ?? []
        return devices.compactMap { d in
            guard let id = d["identifiers"] as? [String: Any],
                  let vid = id["vendor_id"] as? Int,
                  let pid = id["product_id"] as? Int else { return nil }
            return KEEntry(vendorID: vid, productID: pid,
                           isKeyboard: id["is_keyboard"] as? Bool ?? false,
                           isPointing: id["is_pointing_device"] as? Bool ?? false,
                           ignore: d["ignore"] as? Bool ?? false)
        }
    }

    private func modifyState(hid: [HIDInfo]) -> ModifyState {
        guard !hid.isEmpty else { return .noDevice }
        guard let entries = karabinerEntries() else { return .unreadable }
        var sawEntry = false
        var allOn = true
        for h in hid {
            let same = entries.filter { $0.vendorID == h.vendorID && $0.productID == h.productID }
            let exact = same.first { $0.isKeyboard == h.isKeyboard && $0.isPointing == h.isPointing } ?? same.first
            guard let e = exact else { continue }
            sawEntry = true
            if e.ignore { allOn = false }
        }
        if !sawEntry { return .noEntry }
        return allOn ? .on : .off
    }

    private func grabberLogLine(matching name: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: "/var/log/karabiner/grabber.log") else { return nil }
        defer { try? fh.close() }
        let size = fh.seekToEndOfFile()
        fh.seek(toFileOffset: size > 65_536 ? size - 65_536 : 0)
        let text = String(decoding: fh.readDataToEndOfFile(), as: UTF8.self)
        return text.split(separator: "\n")
            .last { $0.localizedCaseInsensitiveContains(name) }
            .map(String.init)
    }

    // MARK: refresh

    func refresh() {
        var s = Snapshot()
        s.deviceName = deviceName
        if let hc = IOBluetoothHostController.default() {
            s.btPowerOn = hc.powerState == BluetoothHCIPowerState(kBluetoothHCIPowerStateON)
        }
        let device = selectedDevice()
        s.paired = device != nil
        s.connected = device?.isConnected() ?? false
        s.address = device?.addressString
        s.hid = hidDevices().filter { matches($0, device: device, name: s.deviceName) }
        let procs = processNames()
        s.grabberRunning = procs.contains { $0.hasSuffix("/karabiner_grabber") || $0 == "karabiner_grabber" }
        s.userServerRunning = procs.contains {
            $0.hasSuffix("/karabiner_console_user_server") || $0 == "karabiner_console_user_server"
        }
        s.modify = modifyState(hid: s.hid)
        if let name = s.deviceName { s.grabberLogLine = grabberLogLine(matching: name) }
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
            s.health = .unknown
            s.diagnosis = "No button selected"
            s.hint = "Pick it under Device."
            return
        }
        if !s.btPowerOn {
            s.health = .bad; s.diagnosis = "Bluetooth is off"
            s.hint = "Turn Bluetooth on."
            return
        }
        if !s.paired {
            s.health = .bad; s.diagnosis = "Button is not paired with this Mac"
            s.hint = "Pair it in Bluetooth settings, then pick it again under Device."
            return
        }
        if !s.connected {
            s.health = .bad; s.diagnosis = "Button is disconnected"
            s.hint = "Press the button once to wake it. Reconnect now also asks macOS to connect."
            return
        }
        if s.hid.isEmpty {
            s.health = .warn; s.diagnosis = "Connected, but macOS has not registered it as an input device"
            s.hint = "Usually clears within seconds. If it stays, remove the pairing and pair again."
            return
        }
        if !s.grabberRunning {
            s.health = .bad; s.diagnosis = "karabiner_grabber is not running"
            s.hint = "Use Restart Karabiner daemons, or open Karabiner-Elements."
            return
        }
        if !s.userServerRunning {
            s.health = .bad; s.diagnosis = "Karabiner user agent is not running"
            s.hint = "Open Karabiner-Elements once to start it."
            return
        }
        switch s.modify {
        case .unreadable:
            s.health = .warn; s.diagnosis = "Cannot read karabiner.json"
            s.hint = "Expected at ~/.config/karabiner/karabiner.json."
        case .noEntry:
            if s.hid.contains(where: { $0.isPointing && !$0.isKeyboard }) {
                s.health = .warn; s.diagnosis = "Karabiner has no entry for this button"
                s.hint = "Pointing devices are ignored by default. Use Enable Modify events."
            } else {
                s.health = .good; s.diagnosis = "Working: connected, registered, Karabiner defaults apply"
                s.hint = nil
            }
        case .off:
            s.health = .bad; s.diagnosis = "Karabiner is ignoring this button (Modify events off)"
            s.hint = "Use Enable Modify events, or tick it in Karabiner-Elements > Devices."
        case .on, .noDevice:
            s.health = .good; s.diagnosis = "Working: connected, registered, Karabiner modifying events"
            s.hint = "If a rule still does not fire, check Input Monitoring for Karabiner."
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
                log("Bluetooth disconnected")
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
        if old.grabberRunning != new.grabberRunning {
            log(new.grabberRunning ? "karabiner_grabber started" : "karabiner_grabber stopped")
        }
        if old.userServerRunning != new.userServerRunning {
            log(new.userServerRunning ? "Karabiner user agent started" : "Karabiner user agent stopped")
        }
        if old.modify != new.modify && old.modify != .noDevice && new.modify != .noDevice {
            switch new.modify {
            case .on: log("Karabiner: Modify events on")
            case .off: log("Karabiner: Modify events OFF")
            case .noEntry: log("Karabiner: device entry missing")
            case .unreadable: log("Karabiner: karabiner.json unreadable")
            case .noDevice: break
            }
        }
        if old.btPowerOn != new.btPowerOn {
            log(new.btPowerOn ? "Bluetooth radio on" : "Bluetooth radio off")
        }
    }

    // MARK: actions

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
            log("Reconnect request refused (0x\(String(UInt32(bitPattern: r), radix: 16))). "
                + "A BLE button must be pressed to wake it.")
        }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        if status == 0 {
            log("Reconnect succeeded")
        } else {
            log("Reconnect failed (0x\(String(UInt32(bitPattern: status), radix: 16))). "
                + "Press the button to wake it.")
        }
        refresh()
    }

    /// Sets ignore=false for every HID interface of the watched button in the selected
    /// Karabiner profile, adding entries that are missing. Writes a backup first.
    func enableModifyEvents() -> String {
        let hid = snapshot.hid
        guard !hid.isEmpty else { return "Button is not registered as an input device yet" }
        let url = Monitor.karabinerConfig
        guard let data = try? Data(contentsOf: url),
              var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var profiles = root["profiles"] as? [[String: Any]], !profiles.isEmpty else {
            return "Could not parse karabiner.json"
        }
        let idx = profiles.firstIndex { ($0["selected"] as? Bool) == true } ?? 0
        var devices = profiles[idx]["devices"] as? [[String: Any]] ?? []
        var changed = 0
        for h in hid {
            let i = devices.firstIndex { d in
                let id = d["identifiers"] as? [String: Any] ?? [:]
                return id["vendor_id"] as? Int == h.vendorID
                    && id["product_id"] as? Int == h.productID
                    && (id["is_keyboard"] as? Bool ?? false) == h.isKeyboard
                    && (id["is_pointing_device"] as? Bool ?? false) == h.isPointing
            }
            if let i = i {
                if (devices[i]["ignore"] as? Bool) != false {
                    devices[i]["ignore"] = false
                    changed += 1
                }
            } else {
                devices.append([
                    "identifiers": [
                        "vendor_id": h.vendorID,
                        "product_id": h.productID,
                        "is_keyboard": h.isKeyboard,
                        "is_pointing_device": h.isPointing,
                    ],
                    "ignore": false,
                ])
                changed += 1
            }
        }
        if changed == 0 { return "Modify events was already on" }
        profiles[idx]["devices"] = devices
        root["profiles"] = profiles
        let bak = url.deletingLastPathComponent().appendingPathComponent("karabiner.json.clicktalk.bak")
        try? FileManager.default.removeItem(at: bak)
        try? FileManager.default.copyItem(at: url, to: bak)
        do {
            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: url, options: .atomic)
        } catch {
            return "Write failed: \(error.localizedDescription)"
        }
        log("Enabled Modify events for \(changed) interface(s); backup at karabiner.json.clicktalk.bak")
        procCache.at = .distantPast
        refresh()
        return "Enabled Modify events (\(changed) change(s)). Karabiner reloads the file itself."
    }

    /// Finds Karabiner's launchd labels at run time (they differ between versions) and
    /// kickstarts them. The system daemons need an admin prompt; the user agent does not.
    func restartKarabiner() {
        log("Karabiner restart requested")
        let daemons = """
        for l in $(launchctl list | awk '/karabiner_grabber|karabiner_session_monitor|VirtualHIDDevice-Daemon/ {print $3}'); do \
        launchctl kickstart -k system/$l; done
        """
        let agents = """
        uid=$(id -u); for l in $(launchctl list | awk '/karabiner_console_user_server|karabiner_grabber|karabiner_session_monitor/ {print $3}'); do \
        launchctl kickstart -k gui/$uid/$l; done
        """
        DispatchQueue.global().async { [weak self] in
            var err: NSDictionary?
            let escaped = daemons.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            let src = "do shell script \"\(escaped)\" with administrator privileges"
            NSAppleScript(source: src)?.executeAndReturnError(&err)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", agents]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            DispatchQueue.main.async {
                if let err = err, let msg = err[NSAppleScript.errorMessage] as? String {
                    self?.log("Karabiner restart: \(msg)")
                } else {
                    self?.log("Karabiner daemons kickstarted")
                }
                self?.procCache.at = .distantPast
                self?.refresh()
            }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let monitor = Monitor()
    var statusItem: NSStatusItem!
    let menu = NSMenu()

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

    func menuWillOpen(_ menu: NSMenu) {
        monitor.refresh()
        rebuildMenu()
    }

    // MARK: icon

    private func updateIcon(_ s: Snapshot) {
        let label: String
        switch s.health {
        case .good: label = ""
        case .unknown: label = "?"
        case .warn, .bad:
            if !s.btPowerOn || !s.paired || !s.connected { label = "BT" }
            else if s.hid.isEmpty { label = "HID" }
            else { label = "KE" }
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

    // MARK: menu

    private func action(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        i.isEnabled = true
        return i
    }

    private func info(_ title: String, bold: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = bold // keep the diagnosis line black, the rest grey
        if bold {
            i.attributedTitle = NSAttributedString(
                string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        }
        return i
    }

    private func rebuildMenu() {
        let s = monitor.snapshot
        menu.removeAllItems()

        menu.addItem(info(s.diagnosis, bold: true))
        if let hint = s.hint { menu.addItem(info(hint)) }
        menu.addItem(.separator())

        let name = s.deviceName ?? "no button selected"
        menu.addItem(info("Button: \(name)"))
        if s.paired {
            if s.connected {
                let since = monitor.connectedSince.map { " for \(ago($0))" } ?? ""
                menu.addItem(info("Bluetooth: connected\(since)"))
            } else {
                let since = monitor.disconnectedSince.map { " for \(ago($0))" } ?? ""
                menu.addItem(info("Bluetooth: disconnected\(since)"))
            }
        } else if s.deviceName != nil {
            menu.addItem(info("Bluetooth: not paired"))
        }
        if s.hid.isEmpty {
            menu.addItem(info("Input device: not registered"))
        } else {
            for h in s.hid {
                menu.addItem(info("Input device: \(h.kind) \(h.idString) via \(h.transport)"))
            }
        }
        menu.addItem(info("Karabiner grabber: \(s.grabberRunning ? "running" : "NOT running")"))
        menu.addItem(info("Karabiner user agent: \(s.userServerRunning ? "running" : "NOT running")"))
        let modify: String
        switch s.modify {
        case .on: modify = "on"
        case .off: modify = "OFF"
        case .noEntry: modify = "no entry (default applies)"
        case .unreadable: modify = "karabiner.json unreadable"
        case .noDevice: modify = "waiting for input device"
        }
        menu.addItem(info("Modify events: \(modify)"))
        if let line = s.grabberLogLine {
            let trimmed = line.count > 110 ? String(line.prefix(110)) + "…" : line
            menu.addItem(info("grabber.log: \(trimmed)"))
        }
        menu.addItem(.separator())

        let rc = action("Reconnect now", #selector(reconnectNow), key: "r")
        rc.isEnabled = s.paired && !s.connected
        menu.addItem(rc)
        let auto = action("Auto-reconnect every 20s while disconnected", #selector(toggleAuto))
        auto.state = monitor.autoReconnect ? .on : .off
        menu.addItem(auto)
        let en = action("Enable Modify events in karabiner.json", #selector(enableModify))
        en.isEnabled = !s.hid.isEmpty && (s.modify == .off || s.modify == .noEntry)
        menu.addItem(en)
        menu.addItem(action("Restart Karabiner daemons…", #selector(restartKarabiner)))
        menu.addItem(.separator())

        let open = NSMenu()
        open.autoenablesItems = false
        open.addItem(action("Karabiner-Elements settings", #selector(openKarabiner)))
        open.addItem(action("Karabiner EventViewer", #selector(openEventViewer)))
        open.addItem(action("Input Monitoring privacy pane", #selector(openInputMonitoring)))
        open.addItem(action("Bluetooth settings", #selector(openBluetooth)))
        open.addItem(action("karabiner.json", #selector(openConfig)))
        open.addItem(action("grabber.log", #selector(openGrabberLog)))
        let openItem = NSMenuItem(title: "Open", action: nil, keyEquivalent: "")
        openItem.submenu = open
        menu.addItem(openItem)

        let dev = NSMenu()
        dev.autoenablesItems = false
        let paired = monitor.pairedDevices()
        if paired.isEmpty {
            dev.addItem(info("No paired Bluetooth devices"))
        }
        for d in paired {
            let n = d.name ?? d.addressString ?? "?"
            let i = action("\(n)\(d.isConnected() ? "  (connected)" : "")", #selector(selectDevice(_:)))
            i.representedObject = n
            i.state = n == s.deviceName ? .on : .off
            dev.addItem(i)
        }
        let devItem = NSMenuItem(title: "Device", action: nil, keyEquivalent: "")
        devItem.submenu = dev
        menu.addItem(devItem)

        let ev = NSMenu()
        ev.autoenablesItems = false
        if monitor.events.isEmpty { ev.addItem(info("Nothing yet")) }
        for e in monitor.events.prefix(25) {
            ev.addItem(info("\(timeFmt.string(from: e.date))  \(e.text)"))
        }
        let evItem = NSMenuItem(title: "Recent events", action: nil, keyEquivalent: "")
        evItem.submenu = ev
        menu.addItem(evItem)
        menu.addItem(.separator())

        if #available(macOS 13, *) {
            let li = action("Launch at login", #selector(toggleLogin))
            li.state = SMAppService.mainApp.status == .enabled ? .on : .off
            menu.addItem(li)
        }
        menu.addItem(action("Quit Clicktalk", #selector(quit), key: "q"))
    }

    // MARK: actions

    @objc func reconnectNow() { monitor.reconnect(manual: true) }
    @objc func toggleAuto() { monitor.autoReconnect.toggle() }
    @objc func enableModify() {
        let msg = monitor.enableModifyEvents()
        let a = NSAlert()
        a.messageText = "Clicktalk"
        a.informativeText = msg
        a.runModal()
    }
    @objc func restartKarabiner() { monitor.restartKarabiner() }
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

    private func openApp(_ name: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", name]
        try? p.run()
    }

    @objc func openKarabiner() { openApp("Karabiner-Elements") }
    @objc func openEventViewer() { openApp("Karabiner-EventViewer") }
    @objc func openInputMonitoring() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(u)
        }
    }
    @objc func openBluetooth() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(u)
        }
    }
    @objc func openConfig() { NSWorkspace.shared.open(Monitor.karabinerConfig) }
    @objc func openGrabberLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/var/log/karabiner/grabber.log"))
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
