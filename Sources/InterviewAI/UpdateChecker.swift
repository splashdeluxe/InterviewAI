import Foundation

/// Checks the app's own GitHub repo for a newer release. Manual by
/// design: a button in About and in the app menu, plus one quiet check
/// a day at launch. The repo is private, so a signed-out check gets a
/// 404 from GitHub and says so plainly instead of pretending.
@MainActor
@Observable
final class UpdateChecker {
    static let shared = UpdateChecker()

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed(String)
    }

    private(set) var state: State = .idle

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static let lastCheckKey = "update.lastCheck"

    /// When the last check ran, shown in About. Nil until the first one.
    static var lastCheck: Date? {
        UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    /// One quiet check a day, called at launch. The automatic check
    /// can be turned off in About; a manual check always runs.
    func checkIfStale() {
        let automatic = UserDefaults.standard.object(forKey: "update.automaticCheck") as? Bool ?? true
        guard automatic else { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date.now.timeIntervalSince(last) < 24 * 60 * 60 { return }
        Task { await check() }
    }

    func check() async {
        if case .checking = state { return }
        state = .checking
        UserDefaults.standard.set(Date.now, forKey: Self.lastCheckKey)
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/splashdeluxe/InterviewAI/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("InterviewAI \(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failed("No answer from GitHub.")
                return
            }
            if http.statusCode == 404 {
                state = .failed("GitHub shows no release a signed-out check can see. The repo is private, so its releases stay hidden until it goes public.")
                return
            }
            guard http.statusCode == 200 else {
                state = .failed("GitHub answered \(http.statusCode).")
                return
            }
            struct Release: Decodable {
                let tag_name: String
                let html_url: URL
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            state = Self.isNewer(latest, than: Self.currentVersion)
                ? .available(version: latest, url: release.html_url)
                : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    var statusText: String {
        switch state {
        case .idle: "Not checked yet."
        case .checking: "Checking GitHub…"
        case .upToDate: "You run the newest release."
        case .available(let version, _): "Version \(version) is out."
        case .failed(let message): message
        }
    }
}
