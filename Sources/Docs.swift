// Renders the README images from the real views with sample data:
//   EucLink.app/Contents/MacOS/EucLink --render-docs docs/images
// build.sh runs this for `./build.sh docs`.

import AppKit
import SwiftUI

@MainActor
enum DocsRenderer {
    static func render(to path: String) {
        NSApp.appearance = NSAppearance(named: .aqua)
        let dir = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let keystroke = Action(kind: .keystroke, value: "fn Space", keyCode: 49,
                               flags: CGEventFlags.maskSecondaryFn.rawValue, hold: true)
        var base = GuideContext()
        base.devices = [GuideDevice(name: "AB Shutter3", connected: true),
                        GuideDevice(name: "AirPods Pro", connected: false, symbol: "headphones"),
                        GuideDevice(name: "MX Keys Mini", connected: false, symbol: "keyboard")]
        let steps = GuideStep.allCases

        func ctx(_ change: (inout GuideContext) -> Void) -> GuideContext {
            var c = base
            change(&c)
            return c
        }

        let pages: [(String, GuideStep, GuideContext, Action)] = [
            ("guide-1-welcome", .welcome, base, Action()),
            ("guide-2-bluetooth", .bluetooth, base, Action()),
            ("guide-3-button", .pair, ctx { $0.bluetooth = .granted; $0.selectedDevice = "AB Shutter3"; $0.connected = true }, Action()),
            ("guide-4-input-monitoring", .inputMonitoring, ctx { $0.bluetooth = .granted; $0.selectedDevice = "AB Shutter3" }, Action()),
            ("guide-5-learn", .learn, ctx { $0.isLearning = true }, Action()),
            ("guide-5b-learned", .learn, ctx { $0.trigger = Trigger(usagePage: 0x0C, usage: 0xE9) }, Action()),
            ("guide-6-action", .action, ctx { $0.trigger = Trigger(usagePage: 0x0C, usage: 0xE9) }, keystroke),
            ("guide-7-accessibility", .accessibility, base, keystroke),
            ("guide-8-test", .test, ctx {
                $0.testPassed = true
                $0.lastOutcome = "Volume Up held → key down fn Space"
            }, keystroke),
            ("guide-9-done", .done, ctx { $0.launchAtLogin = true }, keystroke),
        ]
        for (name, step, c, action) in pages {
            let view = GuideFrame(step: step, steps: steps, ctx: c, actions: GuideActions(),
                                  action: .constant(action), canContinue: true, scrolls: false)
            write(view, size: CGSize(width: 660, height: 700), to: dir.appendingPathComponent(name + ".png"))
        }

        write(OverviewSample(), size: CGSize(width: 760, height: 470), to: dir.appendingPathComponent("overview.png"))
        write(AppMark(size: 128).padding(24), size: CGSize(width: 176, height: 176),
              to: dir.appendingPathComponent("icon.png"), transparent: true)
    }

    private static func write<V: View>(_ view: V, size: CGSize, to url: URL, transparent: Bool = false) {
        let content = view
            .frame(width: size.width, height: size.height)
            .background(transparent ? Color.clear : Brand.window)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("Could not render \(url.lastPathComponent)")
            return
        }
        do {
            try png.write(to: url)
            print("Wrote \(url.path)")
        } catch {
            print("Could not write \(url.path): \(error.localizedDescription)")
        }
    }
}

/// The overview's top half with a healthy sample state.
struct OverviewSample: View {
    var body: some View {
        let s = OverviewSample.sample
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Overview", subtitle: "Where your button stands right now.")
            StatusHero(snapshot: s, fixTitle: nil)
            Card {
                SectionTitle(text: "How a press travels")
                FlowChain(nodes: chainNodes(s, sleeps: true)).padding(.top, 6)
            }
        }
        .padding(28)
    }

    static var sample: Snapshot {
        var s = Snapshot()
        s.deviceName = "AB Shutter3"
        s.paired = true
        s.connected = true
        s.hid = [HIDInfo(vendorID: 0x248a, productID: 0x8266, isKeyboard: true, isPointing: false,
                         transport: "Bluetooth Low Energy", product: "AB Shutter3", serial: "")]
        s.inputMonitoring = true
        s.grab = .seized
        s.bindings = [ButtonBinding(trigger: Trigger(usagePage: 0x0C, usage: 0xE9),
                                    action: Action(kind: .keystroke, value: "fn Space", hold: true))]
        s.health = .good
        s.diagnosis = "Ready: 1 binding"
        return s
    }
}
