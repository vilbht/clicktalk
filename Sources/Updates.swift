// The optional update check.
//
// This is the only file in EucLink that goes online, and `./build.sh ci` fails if
// networking code appears anywhere else or if this file names another address.
//
// It is off unless the owner turns it on, or clicks Check Now. It asks GitHub one
// question: what is the latest release of this project? The request carries no
// cookies, no identifier and nothing about the Mac; GitHub sees the IP address, as it
// does for any visit. EucLink never downloads or installs anything: when a newer
// version exists it shows a message with a button that opens the release page.

import AppKit

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case unknown, checking, upToDate, available(String), failed(String)
    }

    static let releasesPage = URL(string: "https://github.com/vilbht/euclink/releases/latest")!
    private static let endpoint = URL(string: "https://api.github.com/repos/vilbht/euclink/releases/latest")!
    /// Relaunches during setup should not each ask GitHub again.
    private static let quietPeriod: TimeInterval = 6 * 3600

    private let defaults = UserDefaults.standard
    @Published private(set) var state: State = .unknown
    /// Called when the state changes, so the menu bar menu can follow.
    var onChange: () -> Void = {}

    var current: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    var lastChecked: Date? { defaults.object(forKey: "lastUpdateCheck") as? Date }

    /// Off unless the owner turns it on.
    var checksAtLaunch: Bool {
        get { defaults.bool(forKey: "checkForUpdates") }
        set {
            objectWillChange.send()
            defaults.set(newValue, forKey: "checkForUpdates")
            if newValue { check() }
        }
    }

    /// Called once when EucLink opens.
    func checkAtLaunchIfEnabled() {
        guard checksAtLaunch else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.quietPeriod {
            if let known = defaults.string(forKey: "latestKnownVersion"), Version.isNewer(known, than: current) {
                set(.available(known))
            }
            return
        }
        check()
    }

    /// One request to GitHub. A click on Check Now is the owner's consent for that request.
    func check() {
        guard state != .checking else { return }
        set(.checking)
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("EucLink", forHTTPHeaderField: "User-Agent")
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        let session = URLSession(configuration: config)
        session.dataTask(with: request) { data, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            let tag = ok ? data.flatMap { Version.latestTag(fromReleaseJSON: $0) } : nil
            let problem = error?.localizedDescription
            session.finishTasksAndInvalidate()
            Task { @MainActor in self.finish(tag: tag, problem: problem) }
        }.resume()
    }

    private func finish(tag: String?, problem: String?) {
        guard let tag else {
            set(.failed(problem ?? "GitHub did not answer with a version."))
            return
        }
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        defaults.set(Date(), forKey: "lastUpdateCheck")
        defaults.set(latest, forKey: "latestKnownVersion")
        set(Version.isNewer(latest, than: current) ? .available(latest) : .upToDate)
    }

    private func set(_ new: State) {
        state = new
        onChange()
    }

    func openReleasesPage() { NSWorkspace.shared.open(Self.releasesPage) }
}
