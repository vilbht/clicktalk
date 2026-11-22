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
        case .needsRelaunch: return "Allowed. Restart EucLink to use it"
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

// MARK: - Controls
//
// Buttons and switches are Apple's standard controls, enhanced where the system allows:
//
//   macOS 13 to 15   bordered and prominent buttons, the system switch
//   macOS 26 and up  the same controls in their Liquid Glass styles
//
// The glass styles only exist in the macOS 26 SDK, so that code is compiled only by a
// toolchain that has it (Swift 6.2 or later); an older toolchain builds the base layer.
// The README renderer cannot draw system controls, so it asks for the drawn versions
// through the drawnControls environment value.

private struct DrawnControlsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True while rendering README images, where system controls cannot be drawn.
    var drawnControls: Bool {
        get { self[DrawnControlsKey.self] }
        set { self[DrawnControlsKey.self] = newValue }
    }
}

/// A standard push button: prominent for the main action, bordered otherwise.
struct AdaptiveButtonStyle: PrimitiveButtonStyle {
    var prominent: Bool
    @Environment(\.drawnControls) private var drawn

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if drawn {
            if prominent {
                Button(configuration).buttonStyle(DrawnPrimaryButtonStyle())
            } else {
                Button(configuration).buttonStyle(DrawnSecondaryButtonStyle())
            }
        } else {
            SystemButton(configuration: configuration, prominent: prominent)
        }
    }
}

struct PrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AdaptiveButtonStyle(prominent: true).makeBody(configuration: configuration)
    }
}

struct SecondaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AdaptiveButtonStyle(prominent: false).makeBody(configuration: configuration)
    }
}

private struct SystemButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let prominent: Bool

    var body: some View { styled.controlSize(.large).tint(Brand.accent) }

    @ViewBuilder private var styled: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                Button(configuration).buttonStyle(.glassProminent)
            } else {
                Button(configuration).buttonStyle(.glass)
            }
        } else {
            classic
        }
        #else
        classic
        #endif
    }

    @ViewBuilder private var classic: some View {
        if prominent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

/// A text link, such as Open Bluetooth Settings.
struct TextLinkStyle: PrimitiveButtonStyle {
    @Environment(\.drawnControls) private var drawn
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if drawn {
            Button(configuration).buttonStyle(DrawnLinkStyle())
        } else {
            Button(configuration).buttonStyle(.link).tint(Brand.accent)
                .font(.system(size: 12, weight: .medium))
        }
    }
}

/// A label on the left and the system switch on the right.
struct SwitchStyle: ToggleStyle {
    @Environment(\.drawnControls) private var drawn
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            if drawn {
                DrawnSwitch(isOn: configuration.isOn)
            } else {
                Toggle("", isOn: configuration.$isOn)
                    .labelsHidden().toggleStyle(.switch).tint(Brand.accent)
            }
        }
    }
}

/// Fills the background of a bar of controls: glass on macOS 26 and later, a quiet tint
/// before that.
struct BarBackground: ViewModifier {
    @Environment(\.drawnControls) private var drawn
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), !drawn {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(Capsule().fill(Color.primary.opacity(0.05)))
        }
        #else
        content.background(Capsule().fill(Color.primary.opacity(0.05)))
        #endif
    }
}

// The drawn versions, used only for README images.

struct DrawnPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Brand.gradient))
            .opacity(enabled ? 1 : 0.4)
    }
}

struct DrawnSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(Color.primary.opacity(0.07)))
            .opacity(enabled ? 1 : 0.4)
    }
}

struct DrawnLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Brand.accent)
    }
}

struct DrawnSwitch: View {
    let isOn: Bool
    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.15)))
                .frame(width: 36, height: 21)
            Circle().fill(Color.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                .frame(width: 17, height: 17)
                .padding(2)
        }
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
        .anchorPreference(key: DragAnchorKey.self, value: .center) { ["to": $0] }
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
/// The drag carries the app the same way Finder does (see AppDragSourceView).
struct DragAppTile: View {
    var body: some View {
        VStack(spacing: 8) {
            AppMark(size: 58)
                .anchorPreference(key: DragAnchorKey.self, value: .center) { ["from": $0] }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.accent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .overlay(AppDragSource())
                .help("Drag EucLink into the list in System Settings")
            Text("Drag me into the list")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Brand.accent)
        }
        .frame(width: 120)
    }
}

/// Where the drag demonstration starts (the EucLink tile) and ends (the drop slot).
struct DragAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGPoint>] = [:]
    static func reduce(value: inout [String: Anchor<CGPoint>], nextValue: () -> [String: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// A looping demonstration of the drag, drawn over the tile and the System Settings
/// drawing: the open-hand cursor reaches the icon, closes into a fist, carries a ghost
/// of the icon to the drop slot and lets go. It ignores the mouse, so the real tile
/// underneath stays draggable.
struct DragDemo: View {
    let from: CGPoint
    let to: CGPoint
    private let period = 3.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            let start = CGPoint(x: from.x - 40, y: from.y + 46)
            // 0-0.18 reach the icon, 0.18-0.26 grab, 0.26-0.72 carry, 0.72-0.80 drop, then rest.
            let reach = ease(clamp((t - 0.0) / 0.18))
            let carry = ease(clamp((t - 0.26) / 0.46))
            let p: CGPoint = t < 0.26
                ? mix(start, from, reach)
                : mix(from, to, carry)
            let holding = t >= 0.18 && t < 0.76
            let fade = t < 0.9 ? 1.0 : 1 - clamp((t - 0.9) / 0.1)
            let flash = t >= 0.74 && t < 0.92 ? 1 - clamp((t - 0.74) / 0.18) : 0

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Brand.accent.opacity(0.25 * flash))
                    .frame(width: 170, height: 30)
                    .position(to)
                if holding {
                    AppMark(size: 34)
                        .opacity(0.75)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                        .position(x: p.x, y: p.y)
                }
                Image(nsImage: (holding ? NSCursor.closedHand : NSCursor.openHand).image)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .position(x: p.x + 6, y: p.y + 6)
                    .opacity(fade)
            }
        }
        .allowsHitTesting(false)
    }

    private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    private func ease(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
    private func mix(_ a: CGPoint, _ b: CGPoint, _ k: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k)
    }
}

/// Starts a drag that carries the app exactly as Finder does: a file URL item, plus the
/// older list of file names that System Settings' privacy lists read. A SwiftUI drag
/// sends an item provider instead, which those lists ignore. It also takes the first
/// click, because the guide window is usually inactive while System Settings is in front.
final class AppDragSourceView: NSView, NSDraggingSource {
    private var downEvent: NSEvent?
    private static let filenames = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { downEvent = event }
    override func mouseUp(with event: NSEvent) { downEvent = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downEvent else { return }
        downEvent = nil
        let url = Bundle.main.bundleURL
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        let p = convert(down.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - 32, y: p.y - 32, width: 64, height: 64), contents: icon)
        let session = beginDraggingSession(with: [item], event: down, source: self)
        session.draggingPasteboard.addTypes([Self.filenames], owner: nil)
        session.draggingPasteboard.setPropertyList([url.path], forType: Self.filenames)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .link, .generic] : []
    }
}

struct AppDragSource: NSViewRepresentable {
    func makeNSView(context: Context) -> AppDragSourceView { AppDragSourceView() }
    func updateNSView(_ view: AppDragSourceView, context: Context) {}
}
