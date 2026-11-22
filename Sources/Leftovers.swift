// What the uninstaller removes, kept apart from the app code so the tests can check it.

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
