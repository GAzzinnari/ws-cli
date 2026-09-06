import Foundation

/// The on-disk `.ws.json` file: the list of repos that make up the workspace.
public struct Manifest: Codable, Equatable, Sendable {
    public var repos: [Repo]

    public init(repos: [Repo]) {
        self.repos = repos
    }
}

/// One repository in the workspace. `path` is relative to WS_HOME.
public struct Repo: Codable, Equatable, Sendable {
    public var name: String
    public var path: String

    /// The repo's default branch (`main` or `master`), determined from local
    /// branches at `init` time. `nil` when neither exists. Used by `prune`.
    public var defaultBranch: String?

    public init(name: String, path: String, defaultBranch: String? = nil) {
        self.name = name
        self.path = path
        self.defaultBranch = defaultBranch
    }
}
