// The setup guide: one step per thing the user has to do, each with a live check.
//
// GuideFrame takes plain values (GuideContext) so the README renderer can draw every
// step with sample data. GuideWindowView feeds it live values from AppState.

import SwiftUI

struct GuideWindowView: View {
    @ObservedObject var state: AppState

    var body: some View {
        let ctx = state.guideContext()
        GuideFrame(
            step: state.step,
            steps: state.guideSteps,
            ctx: ctx,
            actions: state.guideActions(),
            action: Binding(get: { state.guideBinding?.action ?? Action() },
                            set: { state.setGuideAction($0) }),
            canContinue: state.canContinue(ctx),
            onBack: { state.previousStep() },
            onNext: { state.nextStep() },
            onFinish: { state.finishGuide() },
            onLater: { state.closeGuide() })
        .onAppear {
            state.startTicking()
            state.enteredStep()
        }
    }
}

struct GuideFrame: View {
    let step: GuideStep
    let steps: [GuideStep]
    let ctx: GuideContext
    let actions: GuideActions
    @Binding var action: Action
    let canContinue: Bool
    /// False when rendering README images: ImageRenderer cannot draw a ScrollView.
    var scrolls = true
    var onBack: () -> Void = {}
    var onNext: () -> Void = {}
    var onFinish: () -> Void = {}
    var onLater: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            GuideProgress(step: step, steps: steps)
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 12)
            Divider()
            if scrolls {
                ScrollView { content }
            } else {
                content
                Spacer(minLength: 0)
            }
            Divider()
            HStack(spacing: 14) {
                if step != .welcome && step != .done {
                    Button("Back", action: onBack).buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                if step != .done {
                    Button("Finish later", action: onLater).buttonStyle(TextLinkStyle())
                }
                Button(primary.title, action: primary.run)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!primary.enabled)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 660, height: 700)
        .background(Brand.window)
    }

    private var content: some View {
        GuideStepView(step: step, ctx: ctx, actions: actions, action: $action)
            .padding(.horizontal, 40).padding(.vertical, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The one main button. It is the step's own action until the step is done, then it
    /// reads Continue. Nothing in the guide moves unless this button is clicked.
    private var primary: (title: String, enabled: Bool, run: () -> Void) {
        func permission(_ state: PermState, _ title: String, _ allow: @escaping () -> Void)
            -> (title: String, enabled: Bool, run: () -> Void) {
            switch state {
            case .granted: return ("Continue", true, onNext)
            case .needsRelaunch: return ("Restart EucLink", true, actions.relaunch)
            default: return (title, true, allow)
            }
        }
        switch step {
        case .welcome: return ("Get Started", true, onNext)
        case .bluetooth: return permission(ctx.bluetooth, "Allow Bluetooth", actions.allowBluetooth)
        case .pair: return (canContinue ? "Continue" : "Choose Your Button Above", canContinue, onNext)
        case .inputMonitoring:
            return permission(ctx.inputMonitoring, "Allow Input Monitoring", actions.allowInputMonitoring)
        case .learn: return (canContinue ? "Continue" : "Press Your Button", canContinue, onNext)
        case .action: return ("Continue", canContinue, onNext)
        case .accessibility:
            if !ctx.needsAccessibility { return ("Continue", true, onNext) }
            return permission(ctx.accessibility, "Allow Accessibility", actions.allowAccessibility)
        case .test: return (ctx.testPassed ? "Continue" : "Skip Test", true, onNext)
        case .done: return ("Open EucLink", true, onFinish)
        }
    }
}

/// The steps as one bar of small tabs, in the manner of a toolbar: a tick for each step
/// done, the current step spelled out and tinted, the rest as quiet icons. It shows
/// where you are; it is not clickable.
struct GuideProgress: View {
    let step: GuideStep
    let steps: [GuideStep]

    var body: some View {
        let current = steps.firstIndex(of: step) ?? 0
        HStack(spacing: 2) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(spacing: 6) {
                    Image(systemName: i < current ? "checkmark" : s.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 16)
                    if i == current {
                        Text(s.short).font(.system(size: 12, weight: .semibold)).lineLimit(1).fixedSize()
                    }
                }
                .foregroundStyle(i == current ? Brand.accent : (i < current ? Brand.good : Color.secondary.opacity(0.7)))
                .padding(.horizontal, i == current ? 12 : 9).padding(.vertical, 7)
                .background(Capsule().fill(i == current ? Brand.accent.opacity(0.14) : Color.clear))
                .frame(maxWidth: i == current ? nil : .infinity)
            }
        }
        .padding(4)
        .modifier(BarBackground())
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(steps.count): \(step.short)")
    }
}

struct StepHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SymbolTile(symbol: symbol, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 22, weight: .bold))
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct NumberedSteps: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, text in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Brand.accent)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Brand.accent.opacity(0.13)))
                    Text(text).font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct Callout: View {
    let symbol: String
    let text: String
    let color: Color
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.1)))
    }
}

/// Shared layout for the three permission steps.
struct PermissionStep: View {
    let symbol: String
    let title: String
    let why: String
    let pane: String
    let anchor: String
    let instructions: [String]
    let state: PermState
    let actions: GuideActions
    let onAllow: () -> Void
    /// Set when the switch may belong to another copy of EucLink.
    var onReset: (() -> Void)? = nil
    /// Shows the drag tile and the + button, for permissions macOS may not list by itself.
    var dragToAdd = false
    /// Which of the three permissions are allowed, and which one this step is.
    var done: [Bool] = [false, false, false]
    var index = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            StepHeader(symbol: symbol, title: title, subtitle: why)
            if state == .granted {
                let count = done.filter { $0 }.count
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Brand.good).frame(width: 46, height: 46)
                        Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(pane) allowed").font(.system(size: 17, weight: .bold))
                        Text(count >= 3 ? "All 3 permissions done." : "\(count) of 3 permissions done.")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.good.opacity(0.1)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.good.opacity(0.35)))
            } else {
            NumberedSteps(items: instructions)
            HStack(spacing: 14) {
                Button("Open \(pane) Settings") { actions.openPrivacyPane(anchor) }.buttonStyle(TextLinkStyle())
                Spacer()
                PermStatus(state: state)
            }
            if dragToAdd {
                // macOS, not EucLink, asks for this, and only inside System Settings.
                Label("macOS may ask for your Mac password or Touch ID to change this setting. EucLink never asks for a password.",
                      systemImage: "lock.shield")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let onReset {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "arrow.counterclockwise.circle.fill").foregroundStyle(Brand.warn)
                    Text("Already on in System Settings? That switch can belong to another copy of EucLink. Reset clears it and restarts EucLink, then click Allow \(pane) again.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Reset and Try Again", action: onReset).buttonStyle(SecondaryButtonStyle())
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Brand.warn.opacity(0.1)))
            }
            // The drag picture stays visible next to the reset row: the instructions above
            // point to it in every state.
            if dragToAdd && state != .granted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOT IN THE LIST? DRAG EUCLINK IN, OR CLICK + AND CHOOSE IT FROM APPLICATIONS")
                        .font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                    HStack(alignment: .center, spacing: 10) {
                        DragAppTile()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Brand.gradient)
                        SettingsIllustration(pane: pane, showAddBar: true)
                            .frame(maxWidth: 400)
                    }
                    .frame(maxWidth: .infinity)
                    .overlayPreferenceValue(DragAnchorKey.self) { anchors in
                        GeometryReader { g in
                            if let from = anchors["from"], let to = anchors["to"] {
                                DragDemo(from: g[from], to: g[to])
                            }
                        }
                    }
                }
            } else if onReset == nil {
                SettingsIllustration(pane: pane)
                    .frame(maxWidth: 460)
                    .frame(maxWidth: .infinity)
            }
            }
        }
    }
}

struct GuideStepView: View {
    let step: GuideStep
    let ctx: GuideContext
    let actions: GuideActions
    @Binding var action: Action
    @State private var showAllDevices = false

    var body: some View {
        switch step {
        case .welcome: welcome
        case .bluetooth:
            PermissionStep(
                symbol: "antenna.radiowaves.left.and.right", title: "Allow Bluetooth",
                why: "EucLink checks whether your button is connected or asleep. It does not scan for or connect to other devices.",
                pane: "Bluetooth", anchor: "Privacy_Bluetooth",
                instructions: ["Click Allow Bluetooth at the bottom of this window.",
                               "Choose Allow in the prompt macOS shows.",
                               "Chose Don't Allow before? Open Bluetooth Settings below and turn EucLink on."],
                state: ctx.bluetooth, actions: actions, onAllow: actions.allowBluetooth,
                onReset: ctx.bluetooth == .denied ? { actions.resetPermission("BluetoothAlways") } : nil,
                done: ctx.permissionsDone, index: 0)
        case .pair: pair
        case .inputMonitoring:
            VStack(alignment: .leading, spacing: 18) {
                PermissionStep(
                    symbol: "keyboard", title: "Allow Input Monitoring",
                    why: "This lets EucLink read your button directly and keep its own key, such as Volume Up, from reaching other apps. EucLink only opens the button you chose.",
                    pane: "Input Monitoring", anchor: "Privacy_ListenEvent",
                    instructions: ["Click Allow Input Monitoring at the bottom of this window. Privacy & Security > Input Monitoring opens.",
                                   "Find EucLink in the list. Not there? Drag the EucLink icon below into the list.",
                                   "Turn EucLink on, then click Restart EucLink at the bottom of this window."],
                    state: ctx.inputMonitoring, actions: actions, onAllow: actions.allowInputMonitoring,
                    onReset: ctx.inputMonitoring == .denied ? { actions.resetPermission("ListenEvent") } : nil,
                    dragToAdd: true, done: ctx.permissionsDone, index: 1)
                if ctx.resetKeptInputMonitoring {
                    Callout(symbol: "hand.raised.fill",
                            text: "macOS kept EucLink's Input Monitoring switch, which happens when EucLink was added with +. "
                                + "Open System Settings > Privacy & Security > Input Monitoring, select EucLink, click −, "
                                + "then click Allow Input Monitoring here.",
                            color: Brand.warn)
                }
                grabStatus
            }
        case .learn: learn
        case .action: chooseAction
        case .accessibility:
            if !ctx.needsAccessibility {
                VStack(alignment: .leading, spacing: 18) {
                    StepHeader(symbol: "accessibility", title: "Accessibility",
                               subtitle: "Only needed when the button presses keys for you.")
                    Callout(symbol: "checkmark.circle.fill",
                            text: "Your action does not press keys, so EucLink does not need this permission. Continue.",
                            color: Brand.good)
                }
            } else {
            PermissionStep(
                symbol: "accessibility", title: "Allow Accessibility",
                why: "macOS requires this for any app that presses keys for you. EucLink only presses \(action.value.isEmpty ? "your shortcut" : KeyCaps.split(action.value).joined(separator: " + ")), and only when you press the button.",
                pane: "Accessibility", anchor: "Privacy_Accessibility",
                instructions: ["Click Allow Accessibility at the bottom of this window. Privacy & Security > Accessibility opens.",
                               "Find EucLink in the list. Not there? Drag the EucLink icon below into the list.",
                               "Turn EucLink on. This one works without a relaunch."],
                state: ctx.accessibility, actions: actions, onAllow: actions.allowAccessibility,
                onReset: ctx.accessibilityTried && ctx.accessibility != .granted
                    ? { actions.resetPermission("Accessibility") } : nil,
                dragToAdd: true, done: ctx.permissionsDone, index: 2)
            }
        case .test: test
        case .done: done
        }
    }

    // MARK: steps

    private var welcome: some View {
        VStack(spacing: 18) {
            AppMark(size: 88).padding(.top, 4)
            Text("Welcome to EucLink").font(.system(size: 26, weight: .bold))
            Text("Turn a Bluetooth button into a key for your Mac. Hold it to talk to your dictation app, tap it to summon a chat, or run any Shortcut.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
            Card {
                SectionTitle(text: "What you need, about two minutes")
                need("dot.radiowaves.left.and.right", "A Bluetooth button",
                     "Camera shutter remotes and presentation clickers work.")
                need("lock.shield", "Two or three permissions",
                     "Bluetooth and Input Monitoring. Accessibility too if the button presses keys.")
                need("keyboard", "The shortcut you want to trigger",
                     "For a dictation app, its push-to-talk shortcut from its settings.")
            }
            if !ctx.inApplications {
                Card {
                    Label("Copy EucLink to Applications first", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Brand.warn)
                    Text(ctx.translocated
                         ? "You opened EucLink before moving it, so macOS is running a temporary copy. Permissions granted now would be lost. Copy it to Applications first."
                         : "It is running from \(ctx.appFolder). macOS ties permissions to the app's location, so granting them here and moving it later means granting them again.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Copy to Applications and Relaunch", action: actions.moveToApplications)
                        .buttonStyle(PrimaryButtonStyle())
                    if let e = ctx.moveError { Text(e).font(.system(size: 11)).foregroundStyle(Brand.bad) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func need(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Brand.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private func deviceRow(_ d: GuideDevice) -> some View {
        DeviceRow(name: d.name, connected: d.connected, selected: ctx.selectedDevice == d.name, symbol: d.symbol) {
            actions.selectDevice(d.name)
        }
    }

    private var pair: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "dot.radiowaves.left.and.right", title: "Choose your button",
                       subtitle: "Pair it with your Mac first, then pick it here.")
            if ctx.devices.isEmpty {
                Card {
                    Text("No paired Bluetooth devices yet.").font(.system(size: 13, weight: .semibold))
                    NumberedSteps(items: [
                        "Put the button in pairing mode. On many clickers you hold the button for 3 to 5 seconds until a light blinks.",
                        "Open Bluetooth settings and click Connect next to it.",
                        "Come back here. It shows up in this list.",
                    ])
                    Button("Open Bluetooth Settings", action: actions.openBluetoothSettings)
                        .buttonStyle(PrimaryButtonStyle())
                }
            } else {
                Callout(symbol: "hand.point.up.left.fill",
                        text: "Press your button once. Most clickers connect only when pressed, so yours moves to Connected now.",
                        color: Brand.accent)
                let connected = ctx.devices.filter { $0.connected }
                let others = ctx.devices.filter { !$0.connected }
                if !connected.isEmpty {
                    SectionTitle(text: "Connected now")
                    Card(padding: 8) {
                        ForEach(connected) { d in deviceRow(d) }
                    }
                }
                if !others.isEmpty {
                    SectionTitle(text: "Other paired devices")
                    Card(padding: 8) {
                        let shown = showAllDevices ? others : Array(others.prefix(4))
                        ForEach(shown) { d in deviceRow(d) }
                        if others.count > shown.count {
                            Button("Show all \(others.count)") { showAllDevices = true }
                                .buttonStyle(TextLinkStyle())
                                .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }
                }
                HStack(spacing: 6) {
                    Text("Not in the list?").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Pair it in Bluetooth Settings", action: actions.openBluetoothSettings)
                        .buttonStyle(TextLinkStyle())
                }
            }
            if let name = ctx.selectedDevice {
                if ctx.connected {
                    Callout(symbol: "checkmark.circle.fill", text: "\(name) is connected.", color: Brand.good)
                } else {
                    Callout(symbol: "moon.zzz.fill",
                            text: "\(name) is paired but asleep. Press it once to wake it. That is normal for most clickers.",
                            color: Brand.warn)
                }
            }
        }
    }

    @ViewBuilder private var grabStatus: some View {
        if ctx.inputMonitoring == .granted {
            switch ctx.grab {
            case .seized:
                Callout(symbol: "hand.raised.fill",
                        text: "EucLink now holds \(ctx.selectedDevice ?? "your button"). Its own key no longer reaches other apps.",
                        color: Brand.good)
            case .listening:
                Callout(symbol: "exclamationmark.triangle.fill",
                        text: ctx.karabinerHolds
                            ? "Karabiner-Elements holds this button. In Karabiner-Elements > Devices, turn off Modify events for it."
                            : "Another app holds this button. Presses still work, but its own key also reaches other apps.",
                        color: Brand.warn)
            case .idle:
                Callout(symbol: "hand.point.up.left.fill",
                        text: "Press your button once so EucLink can take hold of it.", color: Brand.accent)
            case .noPermission, .failed:
                EmptyView()
            }
        }
    }

    private var learn: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "hand.point.up.left.fill", title: "Press your button",
                       subtitle: "Every clicker sends a different key. EucLink learns yours.")
            VStack(spacing: 14) {
                PulseRings(active: ctx.isLearning, done: ctx.trigger != nil && !ctx.isLearning,
                           label: ctx.isLearning ? "Waiting for a press…" : (ctx.trigger != nil ? "Got it" : "Not listening"))
                if let t = ctx.trigger, !ctx.isLearning {
                    HStack(spacing: 8) {
                        Text("EucLink heard").font(.system(size: 13)).foregroundStyle(.secondary)
                        KeyCaps(text: t.name)
                    }
                    Button("Learn Again", action: actions.learnAgain).buttonStyle(SecondaryButtonStyle())
                } else if !ctx.isLearning {
                    Button("Start Listening", action: actions.learnAgain).buttonStyle(PrimaryButtonStyle())
                }
            }
            .frame(maxWidth: .infinity)
            Callout(symbol: "info.circle.fill",
                    text: "Several buttons on one clicker? Set up one now and add the others later under Bindings.",
                    color: Brand.accent)
        }
    }

    private var chooseAction: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "bolt.fill", title: "What should it do?",
                       subtitle: "Pick a starting point, then fill in the details. You can change it any time.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Preset.allCases) { p in
                    PresetCard(preset: p, selected: p.matches(action)) { action = p.apply(to: action) }
                }
            }
            if action.kind != .none {
                Card {
                    ActionEditor(action: $action, showKinds: action.kind == .url || action.kind == .shell, showHold: false)
                }
            }
        }
    }

    private var test: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(symbol: "checkmark.seal.fill", title: "Try it",
                       subtitle: action.kind == .keystroke && action.hold
                        ? "Hold the button, speak, then let go."
                        : "Press your button once.")
            PulseRings(active: !ctx.testPassed, done: ctx.testPassed,
                       label: ctx.testPassed ? "It works" : "Waiting for a press…")
                .frame(maxWidth: .infinity)
            if let o = ctx.lastOutcome {
                Callout(symbol: ctx.testPassed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        text: o, color: ctx.testPassed ? Brand.good : Brand.warn)
            }
            if !ctx.testPassed {
                Text("Nothing happening? Wake the button with a press, and check that the shortcut matches the one in the other app's settings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var done: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Brand.good.opacity(0.15)).frame(width: 88, height: 88)
                Image(systemName: "checkmark").font(.system(size: 38, weight: .bold)).foregroundStyle(Brand.good)
            }
            Text("You're set").font(.system(size: 26, weight: .bold))
            Text("EucLink lives in your menu bar. The dot shows its state, and clicking it shows the fix when something is off.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
            Card {
                legend(Brand.good, "", "Ready")
                legend(Brand.good, "zz", "Button asleep. It wakes on a press")
                legend(Brand.warn, "", "Needs a look. Click the dot for the fix")
                legend(Brand.bad, "", "Needs attention. Click the dot for the fix")
            }
            Card {
                Toggle(isOn: Binding(get: { ctx.launchAtLogin }, set: { actions.setLaunchAtLogin($0) })) {
                    SettingLabel(title: "Open EucLink at login", detail: "Recommended, so the button works right after you log in.")
                }
                .toggleStyle(SwitchStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func legend(_ color: Color, _ label: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 10, height: 10)
                if !label.isEmpty { Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)) }
            }
            .frame(width: 32, alignment: .leading)
            Text(text).font(.system(size: 12))
        }
    }
}
