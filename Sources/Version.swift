// Version numbers for the optional update check. No networking here, so the tests can
// cover it; the one request lives in Updates.swift.

import Foundation

enum Version {
    /// "v0.6.0" or "0.6.0" as numbers. Nil for anything else, such as a pre-release tag.
    static func parse(_ text: String) -> [Int]? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for p in parts {
            guard !p.isEmpty, p.count <= 6, p.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(p) else { return nil }
            numbers.append(n)
        }
        return numbers
    }

    /// True only when both are plain version numbers and the candidate is higher.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parse(candidate), let b = parse(current) else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The version tag in GitHub's "latest release" reply, if it is a plain version number.
    static func latestTag(fromReleaseJSON data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String, parse(tag) != nil else { return nil }
        return tag
    }
}
