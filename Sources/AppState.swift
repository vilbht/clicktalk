// State shared by the window and the setup guide, and every action they can take.

import AppKit
import Combine
import CoreBluetooth
import IOKit.hid
import ServiceManagement
import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case overview, button, bindings, permissions, activity, general
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .button: return "Button"
        case .bindings: return "Bindings"
        case .permissions: return "Permissions"
        case .activity: return "Activity"
        case .general: return "General"
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "house"
        case .button: return "dot.radiowaves.left.and.right"
        case .bindings: return "arrow.triangle.branch"
        case .permissions: return "lock.shield"
        case .activity: return "list.bullet.rectangle"
        case .general: return "gearshape"
        }
    }
}

enum GuideStep: Int, CaseIterable {
    case welcome, bluetooth, pair, inputMonitoring, learn, action, accessibility, test, done
    var short: String {
        switch self {
        case .welcome: return "Welcome"
        case .bluetooth: return "Bluetooth"
        case .pair: return "Button"
        case .inputMonitoring: return "Input Monitoring"
        case .learn: return "Learn"
        case .action: return "Action"
        case .accessibility: return "Accessibility"
        case .test: return "Test"
        case .done: return "Done"
        }
    }
    var symbol: String {
        switch self {
        case .welcome: return "sparkles"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .pair: return "hand.tap"
        case .inputMonitoring: return "keyboard"
        case .learn: return "ear"
        case .action: return "bolt"
        case .accessibility: return "accessibility"
        case .test: return "checkmark.seal"
        case .done: return "flag.checkered"
        }
    }
}

struct GuideDevice: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let connected: Bool
    var symbol = "dot.radiowaves.left.and.right"
}

/// An SF Symbol for a paired device, from its Bluetooth class or, for Bluetooth LE
/// devices that report no class, from its name.
func deviceSymbol(name: String, major: Int, minor: Int) -> String {
    let n = name.lowercased()
    if n.contains("airpods") || n.contains("buds") || n.contains("headphone") || n.contains("beats") { return "headphones" }
    if n.contains("keys") || n.contains("keyboard") { return "keyboard" }
    if n.contains("mouse") || n.contains("mx master") || n.contains("trackpad") { return "computermouse" }
    if n.contains("gamepad") || n.contains("controller") { return "gamecontroller" }
    switch major {
    case 0x01: return "laptopcomputer"
    case 0x02: return "iphone"
    case 0x04: return n.contains("bar") || n.contains("speaker") ? "hifispeaker" : "headphones"
    case 0x05:
        if minor & 0x10 != 0 { return "keyboard" }
        if minor & 0x20 != 0 { return "computermouse" }
        if minor & 0x0F == 0x02 { return "gamecontroller" }
        return "dot.radiowaves.left.and.right"
    default: return "dot.radiowaves.left.and.right"
    }
}

/// Plain values the setup guide shows. Built live from the engine, or filled with
/// sample values when rendering the README images.
struct GuideContext {
    var inApplications = true
    var appFolder = "/Applications"
    var moveError: String?
    /// True when macOS runs a hidden temporary copy (App Translocation).
    var translocated = false
    var bluetooth: PermState = .notDetermined
    var devices: [GuideDevice] = []
    var selectedDevice: String?
    var connected = false
    var registered = false
    var inputMonitoring: PermState = .notDetermined
    var grab: GrabState = .idle
    var karabinerHolds = false
    var isLearning = false
    var trigger: Trigger?
    var needsAccessibility = true
    var accessibility: PermState = .notDetermined
    /// True once Allow Accessibility was clicked in this run, so a reset is only offered
    /// after the normal way has had its chance.
    var accessibilityTried = false
    var resetKeptInputMonitoring = false
    /// Bluetooth, Input Monitoring, Accessibility: which are allowed.
    var permissionsDone: [Bool] {
        [bluetooth == .granted, inputMonitoring == .granted, accessibility == .granted]
    }
    var testPassed = false
    var lastOutcome: String?
    var launchAtLogin = false
    var checksForUpdates = false
}

/// Everything a guide step can do. No-ops by default, which is what the README
/// renderer uses.
struct GuideActions {
    var moveToApplications: () -> Void = {}
    var allowBluetooth: () -> Void = {}
    var openBluetoothSettings: () -> Void = {}
    var selectDevice: (String) -> Void = { _ in }
    var allowInputMonitoring: () -> Void = {}
    var allowAccessibility: () -> Void = {}
    var openPrivacyPane: (String) -> Void = { _ in }
    var relaunch: () -> Void = {}
    var resetPermission: (String) -> Void = { _ in }
    var learnAgain: () -> Void = {}
    var setLaunchAtLogin: (Bool) -> Void = { _ in }
    var setChecksForUpdates: (Bool) -> Void = { _ in }
}

@MainActor
final class AppState: ObservableObject {
    let monitor: Monitor
    @Published var pane: Pane = .overview
    @Published var step: GuideStep {
        didSet { UserDefaults.standard.set(step.rawValue, forKey: "guideStep") }
    }
    @Published var isLearningNew = false
    @Published var editingID: UUID?
    @Published var testStartedAt: Date?
    @Published var moveError: String?
    @Published var accessibilityTried = false

    var showMain: (Pane?) -> Void = { _ in }
    var showGuide: () -> Void = {}
    var closeGuide: () -> Void = {}

    private var cancellables = Set<AnyCancellable>()
    private var ticker: AnyCancellable?

    /// The optional update check. Off unless the owner turns it on.
    let updates = UpdateChecker()

    init(monitor: Monitor) {
        self.monitor = monitor
        step = GuideStep(rawValue: UserDefaults.standard.integer(forKey: "guideStep")) ?? .welcome
        monitor.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        updates.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Permissions can change in System Settings without any event reaching us, so
    /// while a window is open the views re-read them every second.
    func startTicking() {
        guard ticker == nil else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    func stopTicking() {
        ticker = nil
    }

    // MARK: permissions

    var bluetoothState: PermState {
        switch CBManager.authorization {
        case .allowedAlways: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    var inputMonitoringState: PermState {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted:
            return monitor.snapshot.grab == .noPermission ? .needsRelaunch : .granted
        case kIOHIDAccessTypeDenied:
            return .denied
        default:
            return .notDetermined
        }
    }

    var accessibilityState: PermState {
        AXIsProcessTrusted() ? .granted : .notDetermined
    }

    func allowBluetooth() {
        if bluetoothState == .notDetermined {
            monitor.requestBluetooth()
        } else {
            openPrivacyPane("Privacy_Bluetooth")
        }
    }

    /// Always asks, because asking is what puts EucLink in the list in System Settings.
    /// Then opens that list, unless macOS granted it straight away.
    func allowInputMonitoring() {
        monitor.requestInputMonitoring()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if self.inputMonitoringState == .denied || self.inputMonitoringState == .notDetermined {
                self.openPrivacyPane("Privacy_ListenEvent")
            }
        }
    }

    func allowAccessibility() {
        accessibilityTried = true
        monitor.requestAccessibility()
        if accessibilityState != .granted {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if self.accessibilityState != .granted { self.openPrivacyPane("Privacy_Accessibility") }
            }
        }
    }

    func openPrivacyPane(_ anchor: String) {
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(u)
        }
    }

    func openBluetoothSettings() {
        if let u = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
            NSWorkspace.shared.open(u)
        }
    }

    // MARK: app lifecycle

    var isInApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    func relaunch() { launchAndQuit(Bundle.main.bundlePath) }

    /// Clears a permission entry that may belong to another copy of EucLink, then
    /// relaunches so this copy can ask again. The guide reopens on the same step.
    func resetPermissionAndRelaunch(_ services: [String]) {
        let id = Bundle.main.bundleIdentifier ?? "local.euclink"
        let refused = services.filter { !PermissionReset.run($0, bundleID: id) }
        guard refused.isEmpty else {
            monitor.log("macOS refused to reset \(refused.joined(separator: ", "))")
            let alert = NSAlert()
            alert.messageText = "macOS did not reset the permission"
            alert.informativeText = "Quit EucLink, paste this into Terminal, then open EucLink again:\n\n"
                + refused.map { "tccutil reset \($0) \(id)" }.joined(separator: "\n")
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(refused.map { "tccutil reset \($0) \(id)" }.joined(separator: "; "),
                                               forType: .string)
            }
            return
        }
        monitor.log("Reset \(services.joined(separator: ", ")) and relaunched")
        // System Settings keeps showing the old switch until it is reopened, so quit it now.
        // EucLink reopens it on the right list when it asks again after the restart.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences") {
            app.terminate()
        }
        if services.contains("ListenEvent") { UserDefaults.standard.set(true, forKey: "listenEventWasReset") }
        relaunch()
    }

    /// Set at launch when Input Monitoring was reset but macOS still reports it allowed.
    /// That happens when EucLink was added by hand with +: macOS stores that entry by the
    /// app's location, which tccutil does not clear, so it has to be removed with -.
    @Published var resetKeptInputMonitoring = false

    /// Called at launch: after a reset, notices an Input Monitoring entry that survived it.
    func resumePermissionRequest() {
        if UserDefaults.standard.bool(forKey: "listenEventWasReset") {
            UserDefaults.standard.removeObject(forKey: "listenEventWasReset")
            if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted {
                resetKeptInputMonitoring = true
                monitor.log("Input Monitoring is still allowed after the reset: remove EucLink with - in System Settings")
                return
            }
        }
    }

    /// True when macOS runs a hidden, read-only temporary copy of the app. That is App
    /// Translocation: it happens when a downloaded app is opened before it was moved,
    /// for example straight from the disk image.
    var isTranslocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }

    /// Where the app really is. For a translocated app, asks macOS for the original
    /// location; the temporary copy itself cannot be copied.
    private func originalBundlePath() -> String {
        let here = Bundle.main.bundlePath
        guard isTranslocated,
              let lib = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(lib, "SecTranslocateCreateOriginalPathForURL") else { return here }
        typealias Original = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let original = unsafeBitCast(sym, to: Original.self)
        guard let url = original(Bundle.main.bundleURL as CFURL, nil)?.takeRetainedValue() as URL? else { return here }
        return url.path
    }

    /// Copies the app to /Applications and relaunches from there. macOS ties the
    /// permissions to the app, so it is best done before granting any.
    func moveToApplications() {
        let src = originalBundlePath()
        let dst = "/Applications/EucLink.app"
        let fm = FileManager.default
        guard fm.fileExists(atPath: src), !src.contains("/AppTranslocation/") else {
            moveError = "EucLink can't copy itself from here. Quit EucLink, open the disk image again, "
                + "drag EucLink into Applications, and open it from Applications."
            return
        }
        do {
            if fm.fileExists(atPath: dst) { try fm.removeItem(atPath: dst) }
            try fm.copyItem(atPath: src, toPath: dst)
        } catch {
            moveError = "Could not copy to Applications: \(error.localizedDescription). "
                + "Drag EucLink into Applications in Finder instead."
            return
        }
        // You already allowed this download once. Without its "downloaded" label the copy
        // opens without a second Gatekeeper warning.
        let x = Process()
        x.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        x.arguments = ["-dr", "com.apple.quarantine", dst]
        try? x.run()
        x.waitUntilExit()
        launchAndQuit(dst)
    }

    private func launchAndQuit(_ path: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? p.run()
        NSApp.terminate(nil)
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        objectWillChange.send()
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            monitor.log(on ? "Launch at login on" : "Launch at login off")
        } catch {
            monitor.log("Launch at login: \(error.localizedDescription)")
        }
    }

    // MARK: bindings

    func binding(_ id: UUID) -> ButtonBinding? { monitor.bindings.first { $0.id == id } }

    func setAction(_ id: UUID, _ action: Action) {
        var all = monitor.bindings
        guard let i = all.firstIndex(where: { $0.id == id }), all[i].action != action else { return }
        all[i].action = action
        monitor.bindings = all
    }

    func removeBinding(_ id: UUID) {
        monitor.bindings.removeAll { $0.id == id }
        if editingID == id { editingID = nil }
        monitor.log("Removed binding")
    }

    /// Runs a binding's action now. Returns an error message, or nil.
    func test(_ id: UUID) -> String? {
        guard let b = binding(id) else { return "binding not found" }
        guard monitor.isApproved(b) else {
            return monitor.seal.keyWasReplaced
                ? "EucLink was updated. Approve this binding once before testing."
                : "This binding changed outside EucLink. Approve it before testing."
        }
        let err = monitor.run(b.action)
        monitor.log(err.map { "Test failed: \($0)" } ?? "Tested \(b.action.name)")
        return err
    }

    /// Waits for the next press and adds a binding for it, or opens the existing one.
    func learnNewBinding() {
        isLearningNew = true
        monitor.onLearned = { [weak self] t in
            guard let self = self else { return }
            self.isLearningNew = false
            var all = self.monitor.bindings
            if let existing = all.first(where: { $0.trigger == t }) {
                self.editingID = existing.id
            } else {
                let b = ButtonBinding(trigger: t)
                all.append(b)
                self.monitor.bindings = all
                self.editingID = b.id
            }
        }
        monitor.learning = true
    }

    func cancelLearning() {
        monitor.learning = false
        monitor.onLearned = nil
        isLearningNew = false
    }

    // MARK: guide

    var guideDone: Bool {
        get { UserDefaults.standard.bool(forKey: "guideDone") }
        set { UserDefaults.standard.set(newValue, forKey: "guideDone") }
    }

    /// The binding the guide sets up.
    var guideBindingID: UUID? {
        get { UserDefaults.standard.string(forKey: "guideBinding").flatMap { UUID(uuidString: $0) } }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "guideBinding") }
    }

    var guideBinding: ButtonBinding? {
        if let id = guideBindingID, let b = binding(id) { return b }
        return monitor.bindings.first
    }

    var guideNeedsAccessibility: Bool { guideBinding?.action.kind == .keystroke }

    func setGuideAction(_ action: Action) {
        guard let b = guideBinding else { return }
        setAction(b.id, action)
    }

    func startGuideLearning() {
        isLearningNew = true
        monitor.onLearned = { [weak self] t in
            guard let self = self else { return }
            self.isLearningNew = false
            var all = self.monitor.bindings
            if let id = self.guideBinding?.id, let i = all.firstIndex(where: { $0.id == id }) {
                all[i].trigger = t
                all.removeAll { $0.trigger == t && $0.id != id }
                self.guideBindingID = id
            } else {
                let b = ButtonBinding(trigger: t)
                all.removeAll { $0.trigger == t }
                all.append(b)
                self.guideBindingID = b.id
            }
            self.monitor.bindings = all
        }
        monitor.learning = true
    }

    /// Paired devices, connected ones first, each with an icon.
    func pairedDeviceList() -> [GuideDevice] {
        monitor.pairedDevices()
            .map { d -> GuideDevice in
                let name = d.name ?? d.addressString ?? "Unknown device"
                return GuideDevice(name: name, connected: d.isConnected(),
                                   symbol: deviceSymbol(name: name, major: Int(d.deviceClassMajor),
                                                        minor: Int(d.deviceClassMinor)))
            }
            .sorted { a, b in
                if a.connected != b.connected { return a.connected }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
    }

    func guideContext() -> GuideContext {
        let s = monitor.snapshot
        var c = GuideContext()
        c.inApplications = isInApplications
        c.appFolder = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        c.moveError = moveError
        c.translocated = isTranslocated
        c.bluetooth = bluetoothState
        c.devices = pairedDeviceList()
        c.needsAccessibility = guideNeedsAccessibility
        c.selectedDevice = s.deviceName
        c.connected = s.connected
        c.registered = !s.hid.isEmpty
        c.inputMonitoring = inputMonitoringState
        c.grab = s.grab
        c.karabinerHolds = s.karabinerModifies
        c.isLearning = monitor.learning
        c.trigger = guideBinding?.trigger
        c.accessibility = accessibilityState
        c.accessibilityTried = accessibilityTried
        c.resetKeptInputMonitoring = resetKeptInputMonitoring
        if let start = testStartedAt {
            // Passed once any bound action ran after the step opened, whatever came after it.
            if let f = monitor.lastFired, f.0 > start {
                c.testPassed = true
                c.lastOutcome = f.1
            } else if let o = monitor.lastOutcome, o.0 > start {
                c.lastOutcome = o.1
            }
        }
        c.launchAtLogin = launchAtLogin
        c.checksForUpdates = updates.checksAtLaunch
        return c
    }

    func guideActions() -> GuideActions {
        GuideActions(
            moveToApplications: { [weak self] in self?.moveToApplications() },
            allowBluetooth: { [weak self] in self?.allowBluetooth() },
            openBluetoothSettings: { [weak self] in self?.openBluetoothSettings() },
            selectDevice: { [weak self] name in self?.monitor.deviceName = name },
            allowInputMonitoring: { [weak self] in self?.allowInputMonitoring() },
            allowAccessibility: { [weak self] in self?.allowAccessibility() },
            openPrivacyPane: { [weak self] anchor in self?.openPrivacyPane(anchor) },
            relaunch: { [weak self] in self?.relaunch() },
            resetPermission: { [weak self] s in self?.resetPermissionAndRelaunch([s]) },
            learnAgain: { [weak self] in self?.startGuideLearning() },
            setLaunchAtLogin: { [weak self] on in self?.setLaunchAtLogin(on) },
            setChecksForUpdates: { [weak self] on in self?.updates.checksAtLaunch = on })
    }

    func canContinue(_ c: GuideContext) -> Bool {
        switch step {
        case .welcome: return true
        case .bluetooth: return c.bluetooth == .granted
        case .pair: return c.selectedDevice != nil
        case .inputMonitoring: return c.inputMonitoring == .granted
        case .learn: return c.trigger != nil && !c.isLearning
        case .action:
            guard let a = guideBinding?.action else { return false }
            switch a.kind {
            case .none: return false
            case .keystroke, .toggleApp, .openApp, .shortcut, .url, .shell: return !a.value.isEmpty
            }
        case .accessibility: return !c.needsAccessibility || c.accessibility == .granted
        case .test, .done: return true
        }
    }

    /// Always all nine, so the count never jumps. The Accessibility step says it is not
    /// needed when the action presses no keys.
    var guideSteps: [GuideStep] { GuideStep.allCases }

    func nextStep() {
        let steps = guideSteps
        guard let i = steps.firstIndex(of: step), i + 1 < steps.count else { return }
        step = steps[i + 1]
        enteredStep()
    }

    func previousStep() {
        let steps = guideSteps
        guard let i = steps.firstIndex(of: step), i > 0 else { return }
        if monitor.learning { cancelLearning() }
        step = steps[i - 1]
        enteredStep()
    }

    func enteredStep() {
        switch step {
        case .learn:
            if guideBinding == nil { startGuideLearning() }
        case .test:
            testStartedAt = Date()
        case .done:
            if monitor.learning { cancelLearning() }
            // Open at login is on by default, once. The switch on this step turns it off.
            if !UserDefaults.standard.bool(forKey: "loginDefaultApplied") {
                UserDefaults.standard.set(true, forKey: "loginDefaultApplied")
                if !launchAtLogin { setLaunchAtLogin(true) }
            }
        default:
            if monitor.learning { cancelLearning() }
        }
    }

    func finishGuide() {
        guideDone = true
        step = .welcome
        closeGuide()
        showMain(.overview)
    }

    func restartGuide() {
        step = .welcome
        showGuide()
    }

    // MARK: overview

    /// The one action that fixes the current top problem, if there is one.
    func primaryFix(for s: Snapshot) -> (title: String, run: () -> Void)? {
        if !s.bluetoothAllowed { return ("Allow Bluetooth", { [weak self] in self?.allowBluetooth() }) }
        if s.deviceName == nil { return ("Choose Button", { [weak self] in self?.pane = .button }) }
        if !s.deviceApproved { return ("Choose Button Again", { [weak self] in self?.pane = .button }) }
        if !s.paired { return ("Open Bluetooth Settings", { [weak self] in self?.openBluetoothSettings() }) }
        if !s.connected && !monitor.sleeps {
            return ("Reconnect", { [weak self] in self?.monitor.reconnect(manual: true) })
        }
        if !s.inputMonitoring || s.grab == .noPermission {
            if inputMonitoringState == .needsRelaunch {
                return ("Relaunch EucLink", { [weak self] in self?.relaunch() })
            }
            return ("Allow Input Monitoring", { [weak self] in self?.allowInputMonitoring() })
        }
        if s.bindings.isEmpty {
            return ("Add Binding", { [weak self] in
                self?.pane = .bindings
                self?.learnNewBinding()
            })
        }
        if s.bindings.contains(where: { $0.action.kind == .none }) {
            return ("Set Action", { [weak self] in
                self?.pane = .bindings
                self?.editingID = s.bindings.first { $0.action.kind == .none }?.id
            })
        }
        if let id = s.unapproved.first {
            return ("Review Binding", { [weak self] in
                self?.pane = .bindings
                self?.editingID = id
            })
        }
        if !s.accessibility { return ("Allow Accessibility", { [weak self] in self?.allowAccessibility() }) }
        return nil
    }
}
