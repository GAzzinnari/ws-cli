import Foundation

/// Reads and writes the `.ws.json` manifest.
public struct ManifestStore: Sendable {
    let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> Manifest {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw WorkspaceError.manifestNotFound(url.path)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    public func save(_ manifest: Manifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(manifest)
        data.append(0x0A) // trailing newline, so the file is a tidy text file
        try data.write(to: url, options: .atomic)
    }
}
