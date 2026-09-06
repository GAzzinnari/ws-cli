import Foundation

/// The on-disk `.ws.json` file: the list of repos that make up the workspace.
public struct Manifest: Codable, Equatable, Sendable {
    public var repos: [Repo]

    public init(repos: [Repo]) {
        self.repos = repos
    }

    /// The repo with this name, or `nil` if the manifest doesn't list it.
    public func repo(named name: String) -> Repo? {
        repos.first { $0.name == name }
    }

    /// The repo whose `packageName` matches, or `nil`.
    public func repo(packageNamed packageName: String) -> Repo? {
        repos.first { $0.packageName == packageName }
    }
}

/// One repository in the workspace. `path` is relative to WS_HOME.
public struct Repo: Codable, Equatable, Sendable {
    public var name: String
    public var path: String

    /// The repo's default branch (`main` or `master`), determined from local
    /// branches at `init` time. `nil` when neither exists. Used by `prune`.
    public var defaultBranch: String?

    /// The SwiftPM package name. For a repo named `ios-<x>` this is `<x>`,
    /// otherwise `nil`. Set at `init` time. Used by `local`.
    public var packageName: String?

    public init(name: String, path: String, defaultBranch: String? = nil, packageName: String? = nil) {
        self.name = name
        self.path = path
        self.defaultBranch = defaultBranch
        self.packageName = packageName
    }
}
