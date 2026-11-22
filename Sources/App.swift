// Entry point, menu bar item and windows.
//
// Command line modes, used by build.sh and uninstall.sh:
//   --render-iconset DIR   write the app icon PNGs and exit
//   --render-docs DIR      write the README images and exit
//   --unregister-login     remove the launch-at-login item and exit

import AppKit
import ServiceManagement
import SwiftUI

@main
struct ClicktalkMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let dir = value(after: "--render-iconset") {
            AppIcon.writeIconset(to: dir)
            exit(0)
        }
        if args.contains("--unregister-login") {
            try? SMAppService.mainApp.unregister()
            exit(0)
        }
        let app = NSApplication.shared
        if let dir = value(after: "--render-docs") {
            DocsRenderer.render(to: dir)
            exit(0)
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let monitor = Monitor()
    lazy var state = AppState(monitor: monitor)
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var mainWindow: NSWindow?
    private var guideWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = AppIcon.image(size: 512)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        state.showMain = { [weak self] pane in self?.showMain(pane) }
        state.showGuide = { [weak self] in self?.showGuide() }
        state.closeGuide = { [weak self] in self?.guideWindow?.close() }

        monitor.onChange = { [weak self] s in
            self?.updateIcon(s)
            self?.rebuildMenu()
        }
        monitor.start()
        updateIcon(monitor.snapshot)
        rebuildMenu()

        if !state.guideDone && monitor.bindings.isEmpty {
            showGuide()
        }
    }

    /// Opening the app again from Finder or Spotlight shows the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMain(nil)
        return true
    }

    func menuWillOpen(_ m: NSMenu) {
        monitor.refresh()
        rebuildMenu()
    }

    // MARK: windows

    func showMain(_ pane: Pane?) {
        if let p = pane { state.pane = p }
        if mainWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "Clicktalk"
            w.contentViewController = NSHostingController(rootView: MainView(state: state))
            w.setContentSize(NSSize(width: 880, height: 620))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            w.setFrameAutosaveName("ClicktalkMain")
            mainWindow = w
        }
        present(mainWindow!)
    }

    func showGuide() {
        if guideWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 640),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "Set Up Clicktalk"
            w.contentViewController = NSHostingController(rootView: GuideWindowView(state: state))
            w.setContentSize(NSSize(width: 660, height: 640))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            guideWindow = w
        }
        present(guideWindow!)
    }

    private func present(_ w: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Back to a menu bar only app, without a Dock icon, once no window is open.
    func windowWillClose(_ notification: Notification) {
        let closing = notification.object as? NSWindow
        if closing === guideWindow, monitor.learning { state.cancelLearning() }
        let open = [mainWindow, guideWindow].compactMap { $0 }.filter { $0 !== closing && $0.isVisible }
        if open.isEmpty {
            state.stopTicking()
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: menu bar

    private func updateIcon(_ s: Snapshot) {
        var label = ""
        switch s.health {
        case .good: label = s.connected ? "" : "zz"
        case .unknown: label = "?"
        case .warn, .bad:
            if !s.bluetoothAllowed { label = "PERM" }
            else if !s.btPowerOn || !s.paired || (!s.connected && !monitor.sleeps) { label = "BT" }
            else if s.connected && s.hid.isEmpty { label = "HID" }
            else if !s.inputMonitoring || !s.accessibility || s.grab == .noPermission { label = "PERM" }
            else if s.bindings.isEmpty || s.bindings.contains(where: { $0.action.kind == .none }) { label = "BIND" }
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

    private func item(_ title: String, _ sel: Selector?, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        i.isEnabled = sel != nil
        return i
    }

    private func rebuildMenu() {
        let s = monitor.snapshot
        menu.removeAllItems()
        let head = item(s.diagnosis, nil)
        head.isEnabled = true
        head.attributedTitle = NSAttributedString(string: s.diagnosis,
                                                  attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
        menu.addItem(head)
        if let h = s.hint { menu.addItem(item(h, nil)) }
        if let p = monitor.lastPress {
            menu.addItem(item("Last press: \(p.1.name) at \(timeFmt.string(from: p.0))", nil))
        }
        menu.addItem(.separator())
        if let fix = state.primaryFix(for: s) {
            let i = item(fix.title, #selector(runFix))
            menu.addItem(i)
        }
        if s.paired && !s.connected {
            menu.addItem(item("Reconnect Now", #selector(reconnectNow), key: "r"))
        }
        menu.addItem(item("Open Clicktalk…", #selector(openMain), key: ","))
        menu.addItem(item("Setup Guide…", #selector(openGuide)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Clicktalk", #selector(quit), key: "q"))
    }

    @objc private func runFix() {
        guard let fix = state.primaryFix(for: monitor.snapshot) else { return }
        showMain(nil)
        fix.run()
    }
    @objc private func reconnectNow() { monitor.reconnect(manual: true) }
    @objc private func openMain() { showMain(nil) }
    @objc private func openGuide() { state.restartGuide() }
    @objc private func quit() { NSApp.terminate(nil) }
}
