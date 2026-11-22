// What the uninstaller removes, and the permission reset, kept apart from the app code
// so the tests can check them.

import Foundation

enum Uninstaller {
    /// Files EucLink or macOS may have created for it under the user's Library.
    /// Empty for a bundle identifier that could escape its folder, so a bad value
    /// can never point the deletion somewhere else.
    static func leftoverPaths(home: URL, bundleID: String) -> [URL] {
        guard !bundleID.isEmpty, !bundleID.contains("/"), !bundleID.hasPrefix("."),
              !bundleID.contains("..") else { return [] }
        let lib = home.appendingPathComponent("Library")
        return [
            lib.appendingPathComponent("Preferences/\(bundleID).plist"),
            lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
            lib.appendingPathComponent("Caches/\(bundleID)"),
            lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
        ]
    }

    /// The privacy permissions EucLink asks for, as tccutil names them.
    static let permissions = ["ListenEvent", "Accessibility", "BluetoothAlways"]
}

/// Clears macOS's stored answer for one of EucLink's permissions, so macOS asks again.
/// macOS ties each answer to one build's signature, so a switch that looks on in System
/// Settings can belong to another copy of EucLink and be ignored for this one.
enum PermissionReset {
    /// Only EucLink's own three permissions, and only for a plain bundle identifier.
    static func isAllowed(service: String, bundleID: String) -> Bool {
        Uninstaller.permissions.contains(service)
            && !Uninstaller.leftoverPaths(home: URL(fileURLWithPath: "/"), bundleID: bundleID).isEmpty
    }

    /// Runs `tccutil reset`. Returns false when refused or when tccutil fails.
    @discardableResult
    static func run(_ service: String, bundleID: String) -> Bool {
        guard isAllowed(service: service, bundleID: bundleID) else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        p.arguments = ["reset", service, bundleID]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}
