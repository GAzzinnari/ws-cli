import Foundation

/// The workspace root, resolved from the `WS_HOME` environment variable.
/// Everything the CLI does hangs off this one location.
public struct Workspace: Sendable {
    public static let manifestFileName = ".ws.json"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Resolve the workspace from the environment. Defaults to the real process
    /// environment; a caller can pass its own dictionary instead.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> Workspace {
        guard let raw = environment["WS_HOME"], !raw.isEmpty else {
            throw WorkspaceError.wsHomeNotSet
        }
        let expanded = (raw as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw WorkspaceError.wsHomeNotADirectory(url.path)
        }
        return Workspace(root: url)
    }

    /// Location of `.ws.json`.
    public var manifestURL: URL {
        root.appendingPathComponent(Self.manifestFileName)
    }

    /// Absolute location of a repo listed in the manifest.
    public func url(for repo: Repo) -> URL {
        root.appendingPathComponent(repo.path)
    }
}
