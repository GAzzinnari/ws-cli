import Foundation

/// Turns a git remote URL into the `https://host/owner/repo` web URL it corresponds to.
public enum RemoteWebURL {
    /// Accepts the three shapes git remotes come in:
    ///   - `https://github.com/owner/repo.git`
    ///   - `ssh://git@github.com/owner/repo.git`
    ///   - `git@github.com:owner/repo.git`  (scp-like, no scheme)
    /// Drops any `.git` suffix and any `user@` credentials. Returns nil for
    /// anything else (a bare local path, for instance).
    public static func web(from remote: String) -> String? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let host: String
        var path: String

        if trimmed.contains("://") {
            guard let url = URL(string: trimmed), let parsedHost = url.host, !url.path.isEmpty else {
                return nil
            }
            host = parsedHost           // URL.host already excludes userinfo
            path = url.path
        } else if let colon = trimmed.firstIndex(of: ":") {
            let left = String(trimmed[..<colon])                    // [user@]host
            let right = String(trimmed[trimmed.index(after: colon)...]) // owner/repo(.git)
            host = left.split(separator: "@").last.map(String.init) ?? left
            path = right.hasPrefix("/") ? right : "/" + right
        } else {
            return nil
        }

        guard !host.isEmpty else { return nil }

        if path.hasSuffix(".git") { path.removeLast(4) }
        while path.hasSuffix("/") { path.removeLast() }
        guard path.count > 1 else { return nil } // need at least "/x"

        return "https://\(host)\(path)"
    }
}
