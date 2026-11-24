import Foundation

public enum AppVersion {
    /// "v1.2.0" / "1.2" → [1, 2, 0]. Nil if any part isn't a number.
    static func parts(_ s: String) -> [Int]? {
        let t = s.hasPrefix("v") || s.hasPrefix("V") ? String(s.dropFirst()) : s
        let parts = t.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.map { $0! }
    }

    /// True only if `remote` is a well-formed version strictly newer than `local`.
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let r = parts(remote), let l = parts(local) else { return false }
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}

/// Once-a-day check of the latest GitHub release. Only the version tag is read from the
/// response; the download link is always our own releases page.
public enum UpdateCheck {
    public static let apiURL = URL(string: "https://api.github.com/repos/dvvbit/FretOS/releases/latest")!
    public static let downloadPage = URL(string: "https://github.com/dvvbit/FretOS/releases/latest")!
    static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    public static func latestTag(fromReleaseJSON data: Data) -> String? {
        struct Release: Decodable { let tag_name: String }
        return (try? JSONDecoder().decode(Release.self, from: data))?.tag_name
    }
}

/// A pre-filled GitHub issue. Nothing is sent until the user submits it themselves.
public enum ProblemReport {
    public static func url(appVersion: String, macOS: String, arch: String, guitar: String?, status: String) -> URL {
        let body = """
        **What happened?**


        **What did you expect?**


        ---
        FretOS: \(appVersion)
        macOS: \(macOS) (\(arch))
        Guitar: \(guitar ?? "none detected")
        Status: \(status)
        """
        var c = URLComponents(string: "https://github.com/dvvbit/FretOS/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: "Problem: "), URLQueryItem(name: "body", value: body)]
        return c.url!
    }
}
