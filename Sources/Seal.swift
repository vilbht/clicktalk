// Seals for settings the owner changes inside EucLink.
//
// EucLink's settings live in a preferences file that any program running under the
// same user account can edit. Bindings decide what runs with EucLink's Input
// Monitoring and Accessibility permissions, and the chosen button decides which device
// EucLink reads. So every time the owner changes one of them in the app, EucLink
// stores an HMAC of the new value, keyed with a secret kept in the login keychain.
//
// The keychain item is created by EucLink, so macOS lets only EucLink read it
// without asking. Another program can still edit the preferences file, but it cannot
// produce a matching seal, so EucLink refuses the changed setting until the owner
// approves it in the window.

import CryptoKit
import Foundation
import Security

final class SettingsSeal {
    private let service = "local.euclink.settings-seal"
    private let account = "hmac-key"
    private let storeKey = "settingsSeals"
    private let defaults = UserDefaults.standard
    private var cachedKey: SymmetricKey?
    /// Set when the keychain key could not be read or created.
    private(set) var lastError: String?

    /// The secret, read once from the keychain or created on first use.
    private func key() -> SymmetricKey? {
        if let k = cachedKey { return k }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecSuccess, let data = out as? Data, data.count == 32 {
            cachedKey = SymmetricKey(data: data)
            lastError = nil
            return cachedKey
        }
        guard status == errSecItemNotFound else {
            lastError = "EucLink could not read its seal key from the keychain (error \(status))."
            return nil
        }
        var bytes = Data(count: 32)
        let rng = bytes.withUnsafeMutableBytes { buf -> Int32 in
            guard let base = buf.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard rng == errSecSuccess else {
            lastError = "EucLink could not create a seal key."
            return nil
        }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "EucLink settings seal",
            kSecValueData as String: bytes,
        ]
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else {
            lastError = "EucLink could not store its seal key in the keychain (error \(added))."
            return nil
        }
        cachedKey = SymmetricKey(data: bytes)
        lastError = nil
        return cachedKey
    }

    private func mac(_ data: Data) -> String? {
        guard let k = key() else { return nil }
        return HMAC<SHA256>.authenticationCode(for: data, using: k)
            .map { String(format: "%02x", $0) }.joined()
    }

    private var seals: [String: String] {
        get { (defaults.dictionary(forKey: storeKey) as? [String: String]) ?? [:] }
        set { defaults.set(newValue, forKey: storeKey) }
    }

    /// Records that the owner set this value in the app.
    func seal(_ id: String, _ data: Data) {
        guard let m = mac(data) else { return }
        var s = seals
        s[id] = m
        seals = s
    }

    func remove(_ id: String) {
        var s = seals
        s.removeValue(forKey: id)
        seals = s
    }

    /// Drops seals whose ids no longer exist, keeping the store small.
    func keepOnly(_ ids: Set<String>, prefix: String) {
        seals = seals.filter { !$0.key.hasPrefix(prefix) || ids.contains($0.key) }
    }

    /// True only when the value carries a seal made with EucLink's own key.
    func isSealed(_ id: String, _ data: Data) -> Bool {
        guard let stored = seals[id], let m = mac(data) else { return false }
        return stored == m
    }

    // MARK: typed helpers

    static func data(_ b: ButtonBinding) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(b)) ?? Data()
    }

    static func id(_ b: ButtonBinding) -> String { "binding:" + b.id.uuidString }
    static let deviceID = "deviceName"
}
