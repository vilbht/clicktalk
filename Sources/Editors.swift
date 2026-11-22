// Editing what a button press does.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ActionKind {
    var shortLabel: String {
        switch self {
        case .none: return "None"
        case .keystroke: return "Keystroke"
        case .toggleApp: return "Toggle app"
        case .openApp: return "Open app"
        case .shortcut: return "Shortcut"
        case .url: return "URL"
        case .shell: return "Command"
        }
    }
    var symbol: String {
        switch self {
        case .none: return "circle.slash"
        case .keystroke: return "keyboard"
        case .toggleApp: return "macwindow.on.rectangle"
        case .openApp: return "arrow.up.forward.app"
        case .shortcut: return "square.stack.3d.up.fill"
        case .url: return "link"
        case .shell: return "terminal"
        }
    }
    static let editable: [ActionKind] = [.keystroke, .toggleApp, .openApp, .shortcut, .url, .shell]
}

/// Starting points the guide offers. Each one is an action kind with sensible settings.
enum Preset: CaseIterable, Identifiable {
    case pushToTalk, toggleDictation, summonApp, shortcut, other
    var id: Self { self }
    var title: String {
        switch self {
        case .pushToTalk: return "Push-to-talk dictation"
        case .toggleDictation: return "Tap to start and stop"
        case .summonApp: return "Summon an app"
        case .shortcut: return "Run a Shortcut"
        case .other: return "Something else"
        }
    }
    var detail: String {
        switch self {
        case .pushToTalk: return "Hold the button to talk. For Handy, Superwhisper, Wispr Flow and similar apps."
        case .toggleDictation: return "Tap once to start dictation, tap again to stop."
        case .summonApp: return "Bring a chat app forward. Press again to hide it."
        case .shortcut: return "Anything the Shortcuts app can do, with no code."
        case .other: return "Open a URL or run a shell command."
        }
    }
    var symbol: String {
        switch self {
        case .pushToTalk: return "mic.fill"
        case .toggleDictation: return "waveform"
        case .summonApp: return "macwindow"
        case .shortcut: return "square.stack.3d.up.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
    func matches(_ a: Action) -> Bool {
        switch self {
        case .pushToTalk: return a.kind == .keystroke && a.hold
        case .toggleDictation: return a.kind == .keystroke && !a.hold
        case .summonApp: return a.kind == .toggleApp || a.kind == .openApp
        case .shortcut: return a.kind == .shortcut
        case .other: return a.kind == .url || a.kind == .shell
        }
    }
    /// Applies the preset, keeping a recorded keystroke when switching between the two
    /// keystroke presets.
    func apply(to a: Action) -> Action {
        switch self {
        case .pushToTalk, .toggleDictation:
            var k = a.kind == .keystroke ? a : Action(kind: .keystroke)
            k.hold = self == .pushToTalk
            return k
        case .summonApp: return a.kind == .toggleApp ? a : Action(kind: .toggleApp)
        case .shortcut: return a.kind == .shortcut ? a : Action(kind: .shortcut)
        case .other: return (a.kind == .url || a.kind == .shell) ? a : Action(kind: .url, value: "https://")
        }
    }
}

struct PresetCard: View {
    let preset: Preset
    let selected: Bool
    let onTap: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: preset.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Brand.accent)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Brand.accent.opacity(0.12))))
            VStack(alignment: .leading, spacing: 3) {
                Text(preset.title).font(.system(size: 13, weight: .semibold))
                Text(preset.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(selected ? Brand.accent : Brand.stroke, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Kind chips plus the fields for the chosen kind.
struct ActionEditor: View {
    @Binding var action: Action
    var showKinds = true
    /// The guide sets hold through its presets, so it hides the switch.
    var showHold = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showKinds {
                HStack(spacing: 6) {
                    ForEach(ActionKind.editable, id: \.self) { kind in
                        KindChip(kind: kind, selected: action.kind == kind) {
                            if action.kind != kind { action = Action(kind: kind) }
                        }
                    }
                }
            }
            switch action.kind {
            case .keystroke: KeystrokeEditor(action: $action, showHold: showHold)
            case .toggleApp, .openApp: AppEditor(action: $action)
            case .shortcut: ShortcutEditor(action: $action)
            case .url:
                TextActionEditor(action: $action, label: "URL", placeholder: "https://claude.ai/new",
                                 help: "Any link works, including app links such as shortcuts:// or raycast://.")
            case .shell:
                TextActionEditor(action: $action, label: "Command", placeholder: "open -a Notes",
                                 help: "Runs with /bin/sh. A failure shows up under Activity.")
            case .none:
                Text("Choose what the button does.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }
}

struct KindChip: View {
    let kind: ActionKind
    let selected: Bool
    let onTap: () -> Void
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbol).font(.system(size: 11, weight: .semibold))
            Text(kind.shortLabel).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(selected ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.07))))
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
    }
}

final class RecorderBox: ObservableObject {
    @Published var recording = false
    @Published var failed = false
    private let recorder = KeyRecorder()

    func start(_ done: @escaping (Int, CGEventFlags, String) -> Void) {
        recorder.onKey = { [weak self] code, flags, name in
            self?.stop()
            done(code, flags, name)
        }
        failed = !recorder.start()
        recording = !failed
    }

    func stop() {
        recorder.stop()
        recording = false
    }
}

struct KeystrokeEditor: View {
    @Binding var action: Action
    var showHold = true
    @StateObject private var box = RecorderBox()
    @State private var showTyped = false
    @State private var typed = ""
    @State private var typedError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                if box.recording {
                    HStack(spacing: 8) {
                        Circle().fill(Brand.bad).frame(width: 8, height: 8)
                        Text("Press the shortcut now…").font(.system(size: 13, weight: .medium))
                    }
                    Spacer()
                    Button("Cancel") { box.stop() }.buttonStyle(SecondaryButtonStyle())
                } else if !action.value.isEmpty {
                    KeyCaps(text: action.value)
                    Spacer()
                    Button("Record Again", action: record).buttonStyle(SecondaryButtonStyle())
                } else {
                    Text("No shortcut yet").font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Record Shortcut", action: record).buttonStyle(PrimaryButtonStyle())
                }
            }
            if box.failed {
                Label("Recording needs Input Monitoring. Type the shortcut instead.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Brand.warn)
            }
            if showHold {
            Toggle(isOn: $action.hold) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hold while the button is held").font(.system(size: 13, weight: .medium))
                    Text("Push-to-talk: the key goes down when you press and up when you let go.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(SwitchStyle())
            }
            Button(showTyped ? "Hide typing" : "Type it instead") { showTyped.toggle() }
                .buttonStyle(TextLinkStyle())
            if showTyped {
                HStack(spacing: 8) {
                    TextField("cmd+shift+space, fn, right option", text: $typed)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(useTyped)
                    Button("Use", action: useTyped).buttonStyle(SecondaryButtonStyle())
                }
                if let e = typedError {
                    Text(e).font(.system(size: 11)).foregroundStyle(Brand.bad)
                }
            }
            Text("Find the shortcut in the other app's settings first. Recording it makes that app react once; that is expected.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear { box.stop() }
    }

    private func record() {
        let hold = action.hold
        box.start { code, flags, name in
            action = Action(kind: .keystroke, value: name, keyCode: code, flags: flags.rawValue, hold: hold)
        }
    }

    private func useTyped() {
        guard let p = parseKeystroke(typed) else {
            typedError = "Use names like cmd, shift, option, ctrl, fn, right option, and a key such as space, k or f5."
            return
        }
        typedError = nil
        action = Action(kind: .keystroke, value: p.name, keyCode: p.keyCode, flags: p.flags.rawValue, hold: action.hold)
        showTyped = false
    }
}

struct AppEditor: View {
    @Binding var action: Action
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if action.value.isEmpty {
                    Text("No app chosen").font(.system(size: 13)).foregroundStyle(.secondary)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: action.value))
                        .resizable().frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.appName).font(.system(size: 13, weight: .semibold))
                        Text(action.kind == .toggleApp ? "Press to bring it forward, press again to hide it."
                                                        : "Press to open it or bring it forward.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(action.value.isEmpty ? "Choose App…" : "Change…", action: choose)
                    .buttonStyle(AdaptiveButtonStyle(prominent: action.value.isEmpty))
            }
            Toggle(isOn: Binding(get: { action.kind == .toggleApp },
                                 set: { action.kind = $0 ? .toggleApp : .openApp })) {
                Text("Hide the app when it is already in front").font(.system(size: 13, weight: .medium))
            }
            .toggleStyle(SwitchStyle())
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            action.value = url.path
        }
    }
}

struct ShortcutEditor: View {
    @Binding var action: Action
    @State private var names: [String] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if loading {
                Text("Loading your Shortcuts…").font(.system(size: 12)).foregroundStyle(.secondary)
            } else if names.isEmpty {
                Text("No Shortcuts found. Create one in the Shortcuts app, then come back.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Picker("Shortcut", selection: $action.value) {
                    if action.value.isEmpty { Text("Choose…").tag("") }
                    ForEach(names, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 320)
            }
            HStack(spacing: 14) {
                Button("Open Shortcuts") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                }
                .buttonStyle(TextLinkStyle())
                Button("Reload list") { Task { await load() } }.buttonStyle(TextLinkStyle())
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        names = await Task.detached { listShortcuts() }.value
        loading = false
    }
}

struct TextActionEditor: View {
    @Binding var action: Action
    let label: String
    let placeholder: String
    let help: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .semibold))
            TextField(placeholder, text: $action.value)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
            Text(help).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
