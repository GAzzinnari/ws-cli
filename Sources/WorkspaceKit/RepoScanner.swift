import Foundation

/// Finds git repositories directly under the workspace root.
public struct RepoScanner: Sendable {
    let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Direct child directories of `root` that contain a `.git` entry, sorted by name.
    /// `.git` is checked as a plain path so worktrees and submodules (where `.git`
    /// is a file, not a directory) still count.
    public func scan() throws -> [Repo] {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var repos: [Repo] = []
        for entry in entries {
            let isDirectory = try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            guard isDirectory else { continue }

            let gitEntry = entry.appendingPathComponent(".git").path
            guard fileManager.fileExists(atPath: gitEntry) else { continue }

            let name = entry.lastPathComponent
            repos.append(Repo(name: name, path: name))
        }

        return repos.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
