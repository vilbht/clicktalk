// Shared look: colours, cards, buttons, switches, keycaps and illustrations.
//
// Every control here is drawn in SwiftUI rather than wrapping an AppKit control, so
// the same views render into the README images with ImageRenderer.

import SwiftUI

enum Brand {
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.96)
    static let accent2 = Color(red: 0.91, green: 0.33, blue: 0.62)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let good = Color(red: 0.20, green: 0.70, blue: 0.40)
    static let warn = Color(red: 0.95, green: 0.62, blue: 0.10)
    static let bad = Color(red: 0.90, green: 0.27, blue: 0.27)
    static let idle = Color.secondary
    static let card = Color(nsColor: .controlBackgroundColor)
    static let window = Color(nsColor: .windowBackgroundColor)
    static let stroke = Color.primary.opacity(0.08)
}

extension Health {
    var tint: Color {
        switch self {
        case .good: return Brand.good
        case .warn: return Brand.warn
        case .bad: return Brand.bad
        case .unknown: return Brand.idle
        }
    }
}

/// State of one macOS permission, as the UI explains it.
enum PermState: Equatable {
    case granted, notDetermined, denied, needsRelaunch

    var label: String {
        switch self {
        case .granted: return "Allowed"
        case .notDetermined: return "Not allowed yet"
        case .denied: return "Turned off in System Settings"
        case .needsRelaunch: return "Allowed. Restarting EucLink to use it"
        }
    }
    var color: Color {
        switch self {
        case .granted: return Brand.good
        case .notDetermined: return Brand.idle
        case .denied: return Brand.bad
        case .needsRelaunch: return Brand.warn
        }
    }
    var symbol: String {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .notDetermined: return "circle.dashed"
        case .denied: return "xmark.circle.fill"
        case .needsRelaunch: return "arrow.clockwise.circle.fill"
        }
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Brand.stroke))
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 22, weight: .bold))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Buttons and switches

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Brand.gradient))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.07)))
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Capsule())
    }
}

struct TextLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Brand.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

struct SwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.15)))
                    .frame(width: 36, height: 21)
                Circle().fill(Color.white)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .frame(width: 17, height: 17)
                    .padding(2)
            }
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
    }
}

// MARK: - Small pieces

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .overlay(Circle().stroke(color.opacity(0.35), lineWidth: size * 0.35).scaleEffect(1.5))
    }
}

struct Badge: View {
    let text: String
    let color: Color
    var symbol: String?
    var body: some View {
        HStack(spacing: 4) {
            if let s = symbol { Image(systemName: s).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}

struct PermStatus: View {
    let state: PermState
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.symbol).foregroundStyle(state.color)
            Text(state.label).font(.system(size: 12, weight: .medium)).foregroundStyle(state.color)
        }
    }
}

/// A rounded tile with a gradient and a symbol, used as a step or page icon.
struct SymbolTile: View {
    let symbol: String
    var size: CGFloat = 52
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Brand.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white))
            .shadow(color: Brand.accent.opacity(0.3), radius: 8, y: 4)
    }
}

/// The app icon drawn in SwiftUI, for headers. The Finder icon is drawn by AppIcon.
struct AppMark: View {
    var size: CGFloat = 64
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
            .fill(LinearGradient(colors: [Brand.accent, Brand.accent2], startPoint: .top, endPoint: .bottom))
            .frame(width: size, height: size)
            .overlay(
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: size * 0.025).frame(width: size * 0.74)
                    Circle().stroke(Color.white.opacity(0.45), lineWidth: size * 0.025).frame(width: size * 0.6)
                    Circle().fill(Color.white).frame(width: size * 0.46)
                    Circle().fill(LinearGradient(colors: [Brand.accent, Brand.accent2], startPoint: .top, endPoint: .bottom))
                        .frame(width: size * 0.17)
                })
            .shadow(color: Brand.accent.opacity(0.3), radius: size * 0.12, y: size * 0.05)
    }
}

/// Splits "⌃⌥fn Space" style names into keycaps.
struct KeyCaps: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(KeyCaps.split(text).enumerated()), id: \.offset) { _, part in
                Text(part)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8).frame(minWidth: 26, minHeight: 26)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Brand.card))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary.opacity(0.18)))
                    .shadow(color: .black.opacity(0.08), radius: 0, y: 1.5)
            }
        }
    }

    static func split(_ text: String) -> [String] {
        var parts: [String] = []
        var rest = Substring(text)
        let symbols: [Character] = ["⌃", "⌥", "⇧", "⌘"]
        while let c = rest.first, symbols.contains(c) {
            parts.append(String(c))
            rest = rest.dropFirst()
        }
        if rest.hasPrefix("fn ") {
            parts.append("fn")
            rest = rest.dropFirst(3)
        }
        if !rest.isEmpty { parts.append(String(rest)) }
        return parts
    }
}

/// Concentric rings that pulse while waiting for a button press.
struct PulseRings: View {
    var active: Bool
    var done: Bool = false
    var label: String
    @State private var phase = false
    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(Brand.accent.opacity(active ? 0.35 - Double(i) * 0.1 : 0.12), lineWidth: 2)
                    .frame(width: 96 + CGFloat(i) * 36, height: 96 + CGFloat(i) * 36)
                    .scaleEffect(active && phase ? 1.08 : 1)
                    .animation(active ? .easeInOut(duration: 1.1).repeatForever().delay(Double(i) * 0.15) : .default,
                               value: phase)
            }
            Circle()
                .fill(done ? AnyShapeStyle(Brand.good) : AnyShapeStyle(Brand.gradient))
                .frame(width: 96, height: 96)
                .shadow(color: (done ? Brand.good : Brand.accent).opacity(0.35), radius: 12, y: 6)
                .overlay(Image(systemName: done ? "checkmark" : "hand.point.up.left.fill")
                    .font(.system(size: 34, weight: .bold)).foregroundStyle(.white))
        }
        .frame(height: 180)
        .overlay(alignment: .bottom) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).offset(y: 22)
        }
        .padding(.bottom, 22)
        .onAppear { phase = true }
    }
}

/// A drawn miniature of a System Settings privacy pane with EucLink switched on.
/// Drawn rather than screenshotted, so it fits light and dark mode and every macOS version.
struct SettingsIllustration: View {
    let pane: String
    var otherApps: [String] = ["Terminal", "Raycast"]
    /// Draws the + and - buttons under the list, with + marked, for the add-by-hand route.
    var showAddBar = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color.red, Color.yellow, Color.green], id: \.self) { c in
                    Circle().fill(c.opacity(0.8)).frame(width: 9, height: 9)
                }
                Spacer()
            }
            .padding(10)
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(["General", "Bluetooth", "Privacy & Security", "Keyboard"], id: \.self) { item in
                        Text(item)
                            .font(.system(size: 10, weight: item == "Privacy & Security" ? .semibold : .regular))
                            .foregroundStyle(item == "Privacy & Security" ? Color.white : Color.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(item == "Privacy & Security" ? Brand.accent : Color.clear))
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 120, alignment: .leading)
                .padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Privacy & Security").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.secondary)
                        Text(pane).fontWeight(.semibold)
                    }
                    .font(.system(size: 11))
                    VStack(spacing: 0) {
                        ForEach(otherApps, id: \.self) { app in
                            row(app, on: false, highlight: false)
                            Divider()
                        }
                        if showAddBar {
                            dropSlot
                        } else {
                            row("EucLink", on: true, highlight: true)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Brand.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Brand.stroke))
                    if showAddBar {
                        HStack(spacing: 0) {
                            Text("+").font(.system(size: 12, weight: .bold)).foregroundStyle(Brand.accent)
                                .frame(width: 22, height: 18)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Brand.accent, lineWidth: 1.5))
                            Text("−").font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: 22, height: 18)
                            Spacer()
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.turn.left.up").foregroundStyle(Brand.accent)
                        Text("Turn EucLink on").foregroundStyle(Brand.accent).fontWeight(.semibold)
                    }
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.trailing, 12)
            }
            .padding(.bottom, 12)
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.window))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    /// The empty place in the list where the dragged EucLink icon goes.
    private var dropSlot: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.app.fill").foregroundStyle(Brand.accent).font(.system(size: 14))
            Text("Drop EucLink here").font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.accent)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Brand.accent.opacity(0.06))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Brand.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).padding(2))
    }

    private func row(_ name: String, on: Bool, highlight: Bool) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(highlight ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.15)))
                .frame(width: 16, height: 16)
            Text(name).font(.system(size: 11, weight: highlight ? .semibold : .regular))
            Spacer()
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? Color.accentColor : Color.primary.opacity(0.15)).frame(width: 26, height: 15)
                Circle().fill(Color.white).frame(width: 12, height: 12).padding(1.5)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(highlight ? Brand.accent.opacity(0.08) : Color.clear)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(highlight ? Brand.accent : Color.clear, lineWidth: 1.5).padding(1))
    }
}

/// The path a press takes, with the state of each stage.
struct FlowChain: View {
    struct Node: Identifiable {
        var id: String { title }
        let symbol: String
        let title: String
        let detail: String
        let color: Color
    }
    let nodes: [Node]
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(nodes.enumerated()), id: \.element.id) { i, n in
                VStack(spacing: 6) {
                    ZStack {
                        Circle().fill(n.color.opacity(0.14)).frame(width: 44, height: 44)
                        Image(systemName: n.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(n.color)
                    }
                    Text(n.title).font(.system(size: 12, weight: .semibold))
                    Text(n.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                if i < nodes.count - 1 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 15)
                }
            }
        }
    }
}

/// The real app, as a tile the user can drag into a System Settings privacy list.
/// It carries the app's file URL, like dragging EucLink from Applications in Finder.
struct DragAppTile: View {
    var body: some View {
        VStack(spacing: 8) {
            AppMark(size: 58)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                .help("Drag EucLink into the list in System Settings")
            Text("Drag me into the list")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.accent)
        }
        .frame(width: 120)
    }
}
