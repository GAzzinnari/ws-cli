import Foundation

/// The workspace: a root directory holding the repos, plus the manifest that
/// records it. The manifest lives at `$WS_CONFIG`, or `~/.ws.json` by default —
/// never inside the workspace itself.
public struct Workspace: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The manifest file: `$WS_CONFIG` (expanded) if set, otherwise `~/.ws.json`.
    public static func configURL(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let custom = environment["WS_CONFIG"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ws.json")
    }

    /// Load the manifest and resolve its recorded root. Throws if there is no
    /// manifest yet or the recorded workspace directory is gone.
    public static func load(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> (workspace: Workspace, manifest: Manifest) {
        let manifest = try ManifestStore(url: configURL(environment)).load()
        let root = URL(fileURLWithPath: manifest.root).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw WorkspaceError.workspaceRootMissing(root.path)
        }
        return (Workspace(root: root), manifest)
    }

    /// Absolute location of a repo listed in the manifest.
    public func url(for repo: Repo) -> URL {
        root.appendingPathComponent(repo.path)
    }
}
