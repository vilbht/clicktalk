// The EucLink window: a sidebar and one page per area.

import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(state: state)
                .frame(width: 210)
            Divider()
            ScrollView {
                page
                    .padding(28)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 820, minHeight: 580)
        .background(Brand.window)
        .onAppear { state.startTicking() }
    }

    @ViewBuilder private var page: some View {
        switch state.pane {
        case .overview: OverviewPage(state: state)
        case .button: ButtonPage(state: state)
        case .bindings: BindingsPage(state: state)
        case .permissions: PermissionsPage(state: state)
        case .activity: ActivityPage(state: state)
        case .general: GeneralPage(state: state)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject var state: AppState

    var body: some View {
        let s = state.monitor.snapshot
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                AppMark(size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EucLink").font(.system(size: 15, weight: .bold))
                    HStack(spacing: 5) {
                        StatusDot(color: s.health.tint, size: 7)
                        Text(shortStatus(s)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 16)
            ForEach(Pane.allCases) { p in
                SidebarRow(pane: p, selected: state.pane == p, badge: badge(for: p, s)) { state.pane = p }
            }
            Spacer()
            Button { state.restartGuide() } label: {
                Label("Setup guide", systemImage: "sparkles")
            }
            .buttonStyle(TextLinkStyle())
            .padding(.horizontal, 10).padding(.bottom, 16)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.03))
    }

    private func shortStatus(_ s: Snapshot) -> String {
        switch s.health {
        case .good: return s.connected ? "Ready" : "Asleep"
        case .warn: return "Needs a look"
        case .bad: return "Needs attention"
        case .unknown: return "Not set up"
        }
    }

    private func badge(for p: Pane, _ s: Snapshot) -> Color? {
        switch p {
        case .permissions:
            return (!s.inputMonitoring || !s.accessibility || !s.bluetoothAllowed || s.grab == .noPermission) ? Brand.bad : nil
        case .bindings:
            return (s.bindings.isEmpty || !s.unapproved.isEmpty || s.bindings.contains { $0.action.kind == .none }) ? Brand.warn : nil
        case .button:
            return (s.deviceName == nil || !s.deviceApproved || !s.paired) ? Brand.warn : nil
        default:
            return nil
        }
    }
}

struct SidebarRow: View {
    let pane: Pane
    let selected: Bool
    let badge: Color?
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: pane.symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
                .foregroundStyle(selected ? Brand.accent : Color.secondary)
            Text(pane.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
            Spacer()
            if let b = badge { Circle().fill(b).frame(width: 7, height: 7) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Brand.accent.opacity(0.13) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Overview

struct StatusHero: View {
    let snapshot: Snapshot
    let fixTitle: String?
    var onFix: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill(snapshot.health.tint.opacity(0.15)).frame(width: 56, height: 56)
                Image(systemName: symbol).font(.system(size: 24, weight: .semibold)).foregroundStyle(snapshot.health.tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.diagnosis).font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let h = snapshot.hint {
                    Text(h).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let t = fixTitle {
                Button(t, action: onFix).buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(snapshot.health.tint.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(snapshot.health.tint.opacity(0.25)))
    }

    private var symbol: String {
        switch snapshot.health {
        case .good: return snapshot.connected ? "checkmark" : "moon.zzz.fill"
        case .warn: return "exclamationmark"
        case .bad: return "xmark"
        case .unknown: return "questionmark"
        }
    }
}

/// The five stages a press goes through, coloured by their current state.
func chainNodes(_ s: Snapshot, sleeps: Bool) -> [FlowChain.Node] {
    let btColor: Color
    let btDetail: String
    if !s.bluetoothAllowed || !s.btPowerOn || (s.deviceName != nil && !s.paired) {
        btColor = Brand.bad; btDetail = !s.bluetoothAllowed ? "No access" : (!s.btPowerOn ? "Bluetooth off" : "Not paired")
    } else if s.deviceName == nil {
        btColor = Brand.idle; btDetail = "Not chosen"
    } else if s.connected {
        btColor = Brand.good; btDetail = "Connected"
    } else {
        btColor = sleeps ? Brand.good : Brand.warn; btDetail = sleeps ? "Asleep" : "Disconnected"
    }

    let hidColor: Color = !s.hid.isEmpty ? Brand.good : (s.connected ? Brand.warn : Brand.idle)
    let hidDetail = !s.hid.isEmpty ? (s.hid.first.map { $0.kind } ?? "") : (s.connected ? "Not registered" : "Waiting")

    let grabColor: Color
    let grabDetail: String
    switch s.grab {
    case .seized: grabColor = Brand.good; grabDetail = "Exclusive"
    case .listening: grabColor = Brand.warn; grabDetail = "Shared"
    case .noPermission: grabColor = Brand.bad; grabDetail = "No permission"
    case .failed: grabColor = Brand.bad; grabDetail = "Refused"
    case .idle: grabColor = Brand.idle; grabDetail = "Waiting"
    }

    let bindingOK = !s.bindings.isEmpty && !s.bindings.contains { $0.action.kind == .none }
    let bindColor: Color = bindingOK ? Brand.good : Brand.warn
    let bindDetail = s.bindings.first.map { $0.trigger.name } ?? "None yet"

    let actColor: Color = !bindingOK ? Brand.idle : (s.accessibility ? Brand.good : Brand.bad)
    let actDetail = !bindingOK ? "Not set" : (s.accessibility ? (s.bindings.first?.action.name ?? "") : "Needs Accessibility")

    return [
        .init(symbol: "dot.radiowaves.left.and.right", title: "Button", detail: btDetail, color: btColor),
        .init(symbol: "cpu", title: "macOS", detail: hidDetail, color: hidColor),
        .init(symbol: "hand.raised.fill", title: "EucLink", detail: grabDetail, color: grabColor),
        .init(symbol: "arrow.triangle.branch", title: "Binding", detail: bindDetail, color: bindColor),
        .init(symbol: "bolt.fill", title: "Action", detail: actDetail, color: actColor),
    ]
}

struct FactTile: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionTitle(text: title)
            Text(value).font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Brand.stroke))
    }
}

struct OverviewPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        let s = state.monitor.snapshot
        let fix = state.primaryFix(for: s)
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Overview", subtitle: "Where your button stands right now.")
            StatusHero(snapshot: s, fixTitle: fix?.title, onFix: { fix?.run() })
            Card {
                SectionTitle(text: "How a press travels")
                FlowChain(nodes: chainNodes(s, sleeps: state.monitor.sleeps))
                    .padding(.top, 6)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                FactTile(title: "Button", value: s.deviceName ?? "None", detail: connectionText(s))
                FactTile(title: "Last press", value: lastPressText,
                         detail: state.monitor.lastOutcome.map { $0.1 } ?? "Press your button to see it here.")
                FactTile(title: "Bindings", value: "\(s.bindings.count)",
                         detail: s.bindings.first.map { "\($0.trigger.name) → \($0.action.name)" } ?? "None yet")
                FactTile(title: "Launch at login", value: state.launchAtLogin ? "On" : "Off",
                         detail: state.launchAtLogin ? "Starts when you log in." : "Turn on under General.")
            }
            if s.karabinerRunning {
                Card {
                    Label("Karabiner-Elements is running", systemImage: "info.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(s.karabinerModifies
                         ? "It claims your button. In Karabiner-Elements > Devices, turn off Modify events for it so EucLink can hold it."
                         : "It leaves your button alone, so both can run.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func connectionText(_ s: Snapshot) -> String {
        if !s.paired { return s.deviceName == nil ? "Choose one under Button." : "Not paired" }
        if s.connected { return "Connected" + (state.monitor.connectedSince.map { " for \(ago($0))" } ?? "") }
        return (state.monitor.sleeps ? "Asleep" : "Disconnected") + (state.monitor.disconnectedSince.map { " for \(ago($0))" } ?? "")
    }

    private var lastPressText: String {
        guard let p = state.monitor.lastPress else { return "None yet" }
        return "\(p.1.name) at \(timeFmt.string(from: p.0))"
    }
}

// MARK: - Button

struct DeviceRow: View {
    let name: String
    let connected: Bool
    let selected: Bool
    var symbol = "dot.radiowaves.left.and.right"
    let onTap: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 16))
                .foregroundStyle(selected ? Brand.accent : Color.secondary)
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(name).font(.system(size: 13, weight: selected ? .semibold : .regular))
            Spacer()
            if connected { Badge(text: "Connected", color: Brand.good) }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Brand.accent.opacity(0.08) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct ButtonPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        let s = state.monitor.snapshot
        let devices = state.pairedDeviceList()
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Button", subtitle: "Choose the Bluetooth button EucLink listens to.")
            if s.deviceName != nil && !s.deviceApproved {
                Callout(symbol: "exclamationmark.shield.fill",
                        text: state.monitor.seal.keyWasReplaced
                            ? "EucLink was updated, and macOS treats the update as a new app. Choose your button again below. You only do this once per update."
                            : "Your button choice changed outside EucLink, so EucLink ignores it. Choose your button again below.",
                        color: Brand.warn)
            }
            Card {
                HStack {
                    SectionTitle(text: "Paired devices")
                    Spacer()
                    Button("Open Bluetooth Settings") { state.openBluetoothSettings() }.buttonStyle(TextLinkStyle())
                }
                if devices.isEmpty {
                    Text("No paired devices. Pair your button in Bluetooth settings, then it appears here.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                ForEach(devices) { d in
                    DeviceRow(name: d.name, connected: d.connected, selected: s.deviceName == d.name, symbol: d.symbol) {
                        state.monitor.deviceName = d.name
                    }
                }
            }
            Card {
                SectionTitle(text: "Connection")
                Toggle(isOn: Binding(get: { state.monitor.sleeps }, set: { state.monitor.sleeps = $0 })) {
                    SettingLabel(title: "Button sleeps between presses",
                                 detail: "Most clickers disconnect when idle and wake on a press. Shows as asleep instead of an error.")
                }
                .toggleStyle(SwitchStyle())
                Divider()
                Toggle(isOn: Binding(get: { state.monitor.autoReconnect }, set: { state.monitor.autoReconnect = $0 })) {
                    SettingLabel(title: "Reconnect automatically",
                                 detail: "Asks macOS to reconnect every 20 seconds while disconnected.")
                }
                .toggleStyle(SwitchStyle())
                Divider()
                HStack {
                    SettingLabel(title: "Reconnect now", detail: "A sleeping button may need a press instead.")
                    Spacer()
                    Button("Reconnect") { state.monitor.reconnect(manual: true) }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(!s.paired || s.connected)
                }
            }
            Card {
                SectionTitle(text: "Details")
                DetailRow(label: "Bluetooth", value: s.connected ? "Connected" : (s.paired ? "Not connected" : "Not paired"))
                DetailRow(label: "Input interfaces",
                          value: s.hid.isEmpty ? "None registered" : s.hid.map { "\($0.kind) \($0.idString)" }.joined(separator: ", "))
                DetailRow(label: "Grab", value: state.monitor.grabDetail.isEmpty ? "Waiting" : state.monitor.grabDetail)
            }
        }
    }
}

struct SettingLabel: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 13, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Bindings

struct BindingsPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        let s = state.monitor.snapshot
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                PageHeader(title: "Bindings", subtitle: "What each press does. A clicker with several buttons gets one binding per button.")
                Spacer()
                if !state.isLearningNew {
                    Button("Add Binding") { state.learnNewBinding() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(s.deviceName == nil)
                }
            }
            if state.isLearningNew {
                Card {
                    VStack(spacing: 6) {
                        PulseRings(active: true, label: "Press a button on \(s.deviceName ?? "your clicker")")
                        Button("Cancel") { state.cancelLearning() }.buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            if s.bindings.isEmpty && !state.isLearningNew {
                Card {
                    Text("No bindings yet.").font(.system(size: 13, weight: .semibold))
                    Text("Click Add Binding and press your button. EucLink learns which key it sends.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            ForEach(s.bindings, id: \.id) { b in
                BindingCard(state: state, binding: b, expanded: state.editingID == b.id)
            }
        }
    }
}

struct BindingCard: View {
    @ObservedObject var state: AppState
    let binding: ButtonBinding
    let expanded: Bool
    @State private var testError: String?

    private var approved: Bool { state.monitor.isApproved(binding) }

    var body: some View {
        Card {
            HStack(spacing: 10) {
                Badge(text: binding.trigger.name, color: Brand.accent, symbol: "hand.point.up.left.fill")
                Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.tertiary)
                Image(systemName: binding.action.kind.symbol).foregroundStyle(.secondary)
                Text(binding.action.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                Button("Test") { testError = state.test(binding.id) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(binding.action.kind == .none || !approved)
                Button(expanded ? "Done" : "Edit") { state.editingID = expanded ? nil : binding.id }
                    .buttonStyle(SecondaryButtonStyle())
                Button { state.removeBinding(binding.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Remove this binding")
            }
            if !approved {
                Callout(symbol: "exclamationmark.shield.fill",
                        text: state.monitor.seal.keyWasReplaced
                            ? "EucLink was updated, and macOS treats the update as a new app. Check the action above and approve it. You only do this once per update."
                            : "This binding changed outside EucLink, so it will not run. Check the action above. If you did not set it, remove it with the trash button and check your Mac for unwanted software.",
                        color: Brand.warn)
                Button("Approve This Binding") { state.monitor.approve(binding.id) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if let e = testError {
                Text(e).font(.system(size: 11)).foregroundStyle(Brand.bad)
            }
            if expanded {
                Divider().padding(.vertical, 4)
                ActionEditor(action: Binding(
                    get: { state.binding(binding.id)?.action ?? Action() },
                    set: { state.setAction(binding.id, $0) }))
            }
        }
    }
}

// MARK: - Permissions

struct PermissionRow: View {
    let symbol: String
    let title: String
    let why: String
    let state: PermState
    let onAllow: () -> Void
    let onOpen: () -> Void
    var onRelaunch: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SymbolTile(symbol: symbol, size: 38)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(why).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                PermStatus(state: state)
                HStack(spacing: 12) {
                    if state == .needsRelaunch {
                        Button("Relaunch EucLink", action: onRelaunch).buttonStyle(PrimaryButtonStyle())
                    } else if state != .granted {
                        Button("Allow", action: onAllow).buttonStyle(PrimaryButtonStyle())
                    }
                    Button("Open \(title) Settings", action: onOpen).buttonStyle(TextLinkStyle())
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}

struct PermissionsPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Permissions", subtitle: "macOS asks for each of these once. EucLink keeps working as long as they stay on.")
            Card {
                PermissionRow(symbol: "antenna.radiowaves.left.and.right", title: "Bluetooth",
                              why: "To see whether your button is connected or asleep.",
                              state: state.bluetoothState,
                              onAllow: { state.allowBluetooth() },
                              onOpen: { state.openPrivacyPane("Privacy_Bluetooth") })
                Divider()
                PermissionRow(symbol: "keyboard", title: "Input Monitoring",
                              why: "To read your button directly and keep its own key from reaching other apps.",
                              state: state.inputMonitoringState,
                              onAllow: { state.allowInputMonitoring() },
                              onOpen: { state.openPrivacyPane("Privacy_ListenEvent") },
                              onRelaunch: { state.relaunch() })
                Divider()
                PermissionRow(symbol: "accessibility", title: "Accessibility",
                              why: "To press keys for you. Only needed when a binding sends a keystroke.",
                              state: state.accessibilityState,
                              onAllow: { state.allowAccessibility() },
                              onOpen: { state.openPrivacyPane("Privacy_Accessibility") })
            }
            Card {
                SectionTitle(text: "Still not working?")
                Text("macOS ties permissions to the exact app build. After an update, or after switching between a download and your own build, it can show EucLink as allowed while ignoring it. Reset clears EucLink's entries and restarts it. Then allow each one again above.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if state.resetKeptInputMonitoring {
                    Callout(symbol: "hand.raised.fill",
                            text: "Input Monitoring stayed on after the reset. That happens when EucLink was added with +. "
                                + "In System Settings > Privacy & Security > Input Monitoring, select EucLink and click −.",
                            color: Brand.warn)
                }
                HStack(spacing: 10) {
                    Button("Reset Permissions and Relaunch") { state.resetPermissionAndRelaunch(Uninstaller.permissions) }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Relaunch Only") { state.relaunch() }.buttonStyle(TextLinkStyle())
                }
            }
        }
    }
}

struct CommandRow: View {
    let command: String
    @State private var copied = false
    var body: some View {
        HStack {
            Text(command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Spacer()
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            }
            .buttonStyle(TextLinkStyle())
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

// MARK: - Activity

struct ActivityPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        let events = state.monitor.events
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                PageHeader(title: "Activity", subtitle: "Connections, presses and what they did. Newest first.")
                Spacer()
                Button("Copy Log") {
                    let text = events.map { "\(timeFmt.string(from: $0.date))  \($0.text)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Card(padding: 0) {
                if events.isEmpty {
                    Text("Nothing yet.").font(.system(size: 12)).foregroundStyle(.secondary).padding(16)
                }
                ForEach(Array(events.enumerated()), id: \.offset) { i, e in
                    HStack(alignment: .top, spacing: 12) {
                        Text(timeFmt.string(from: e.date))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        Text(e.text).font(.system(size: 12)).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(i % 2 == 0 ? Color.clear : Color.primary.opacity(0.025))
                }
            }
        }
    }
}

// MARK: - General

struct GeneralPage: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "General", subtitle: "Startup, setup, about and uninstall.")
            Card {
                Toggle(isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) })) {
                    SettingLabel(title: "Open EucLink at login", detail: "Recommended, so the button works right after you log in.")
                }
                .toggleStyle(SwitchStyle())
            }
            if !state.isInApplications {
                Card {
                    Label("EucLink is not in Applications", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.warn)
                    Text("Copy it to Applications so macOS keeps its permissions and Launch at login works.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Copy to Applications and Relaunch") { state.moveToApplications() }
                        .buttonStyle(PrimaryButtonStyle())
                    if let e = state.moveError { Text(e).font(.system(size: 11)).foregroundStyle(Brand.bad) }
                }
            }
            Card {
                HStack {
                    SettingLabel(title: "Setup guide", detail: "Walks through permissions, your button and its action again.")
                    Spacer()
                    Button("Open Guide") { state.restartGuide() }.buttonStyle(SecondaryButtonStyle())
                }
            }
            Card {
                HStack(spacing: 14) {
                    AppMark(size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EucLink \(state.version)").font(.system(size: 14, weight: .semibold))
                        Text("Turn a Bluetooth button into a key for your Mac. MIT licensed.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }.buttonStyle(SecondaryButtonStyle())
                }
            }
            Card {
                HStack {
                    SettingLabel(title: "Uninstall EucLink",
                                 detail: "Removes its settings, login item and permissions, and moves the app to the Trash.")
                    Spacer()
                    Button("Uninstall…") { Uninstaller.confirmAndRun() }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
}
