import ArgumentParser
import Foundation
import WorkspaceKit

struct Clean: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Delete every .build directory in the workspace (nested included)."
    )

    @Flag(name: [.customShort("n"), .customLong("dry-run")],
          help: "List what would be deleted, delete nothing.")
    var dryRun = false

    func run() throws {
        let (workspace, _) = try Workspace.load()
        let root = workspace.root
        let cleaner = BuildCleaner(root: root)

        let dirs = try cleaner.find()
        guard !dirs.isEmpty else {
            print("no .build directories under \(root.path)")
            return
        }

        let sized = dirs.map { (url: $0, size: BuildCleaner.size(of: $0)) }
        for entry in sized {
            let verb = dryRun ? "would remove" : "removing"
            print("\(verb)  \(relativePath(entry.url, under: root))  (\(bytes(entry.size)))")
        }

        if dryRun {
            let total = sized.reduce(0) { $0 + $1.size }
            print("\(count(sized.count)) · \(bytes(total)) — dry run, nothing deleted")
            return
        }

        let failed = Set(cleaner.remove(dirs).filter { $0.failure != nil }.map(\.url))
        let removed = sized.filter { !failed.contains($0.url) }
        let freed = removed.reduce(0) { $0 + $1.size }
        print("removed \(count(removed.count)) · freed \(bytes(freed))")

        if !failed.isEmpty {
            throw WorkspaceError.cleanFailed(
                paths: failed.map { relativePath($0, under: root) }.sorted()
            )
        }
    }

    private func count(_ n: Int) -> String {
        "\(n) .build director\(n == 1 ? "y" : "ies")"
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// `url` relative to `root`, by path components. Both come from the same base
    /// URL the enumerator walked, so this sidesteps `/tmp` vs `/private/tmp`
    /// string mismatches. Falls back to the absolute path if `url` isn't under `root`.
    private func relativePath(_ url: URL, under root: URL) -> String {
        let rootParts = root.standardizedFileURL.pathComponents
        let urlParts = url.standardizedFileURL.pathComponents
        guard urlParts.count > rootParts.count,
              Array(urlParts.prefix(rootParts.count)) == rootParts
        else {
            return url.path
        }
        return urlParts.dropFirst(rootParts.count).joined(separator: "/")
    }
}
