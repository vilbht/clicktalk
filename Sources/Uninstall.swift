// Removes EucLink from this Mac from inside the app, for people who installed a
// release and have no copy of uninstall.sh. It removes the same things the script
// does: the login item, the settings, the seal key, the permission entries and the
// app itself. Bluetooth pairings belong to macOS and stay.

import AppKit
import ServiceManagement

extension Uninstaller {
    /// Asks first, then removes everything and quits.
    @MainActor static func confirmAndRun() {
        NSApp.activate(ignoringOtherApps: true)
        let ask = NSAlert()
        ask.alertStyle = .warning
        ask.messageText = "Uninstall EucLink?"
        ask.informativeText = "This removes your bindings and settings, the login item and EucLink's "
            + "permissions, and moves the app to the Trash. Your Bluetooth pairing stays."
        ask.addButton(withTitle: "Uninstall")
        ask.addButton(withTitle: "Cancel")
        ask.buttons.first?.hasDestructiveAction = true
        guard ask.runModal() == .alertFirstButtonReturn else { return }

        let bundleID = Bundle.main.bundleIdentifier ?? "local.euclink"
        var problems: [String] = []

        if SMAppService.mainApp.status == .enabled {
            do { try SMAppService.mainApp.unregister() } catch {
                problems.append("Remove EucLink under System Settings > General > Login Items.")
            }
        }

        let sealQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SettingsSeal.service,
        ]
        let deleted = SecItemDelete(sealQuery as CFDictionary)
        if deleted != errSecSuccess && deleted != errSecItemNotFound {
            problems.append("Delete \"EucLink settings seal\" in Keychain Access.")
        }

        for service in permissions {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", service, bundleID]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            var ok = false
            do { try p.run(); p.waitUntilExit(); ok = p.terminationStatus == 0 } catch {}
            if !ok {
                problems.append("Turn EucLink off in System Settings > Privacy & Security (\(service)).")
            }
        }

        do {
            try FileManager.default.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        } catch {
            problems.append("Drag EucLink from \(Bundle.main.bundleURL.deletingLastPathComponent().path) to the Trash.")
        }

        let done = NSAlert()
        done.messageText = problems.isEmpty ? "EucLink is uninstalled" : "EucLink is almost uninstalled"
        done.informativeText = problems.isEmpty
            ? "Everything it stored is gone and the app is in the Trash."
            : "One more step:\n" + problems.joined(separator: "\n")
        done.runModal()

        // Settings go last, right before quitting, so nothing writes them back.
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        for url in leftoverPaths(home: FileManager.default.homeDirectoryForCurrentUser, bundleID: bundleID) {
            try? FileManager.default.removeItem(at: url)
        }
        exit(0)
    }
}
