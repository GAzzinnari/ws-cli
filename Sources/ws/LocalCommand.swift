import ArgumentParser
import Foundation
import WorkspaceKit

struct Local: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "local",
        abstract: "Point a Package.swift's dependencies at local checkouts under WS_HOME."
    )

    @Argument(help: "Path to a Package.swift (a directory is accepted).")
    var packageManifest: String

    @Option(name: [.customShort("p"), .customLong("packages")],
            help: "Comma-separated package names (the 'ios-' prefix stripped).")
    var packages: String

    @Option(name: [.customShort("b"), .customLong("branch")],
            help: "Stash, fetch, and check out this branch before editing.")
    var branch: String?

    func run() throws {
        var seen = Set<String>()
        let names = packages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !names.isEmpty else {
            throw ValidationError("--packages needs at least one package name")
        }

        let packageURL = try resolvePackageManifest()
        let workspace = try Workspace.fromEnvironment()
        let manifest = try ManifestStore(url: workspace.manifestURL).load()

        var reasons: [String] = []
        var targets: [PackageEditor.Target] = []
        for name in names {
            guard let repo = manifest.repo(packageNamed: name) else {
                reasons.append("'\(name)': no repo in the manifest has this package name")
                continue
            }
            targets.append(PackageEditor.Target(
                packageName: name,
                fullName: repo.name,
                localPath: workspace.url(for: repo).path
            ))
        }
        guard reasons.isEmpty else {
            throw WorkspaceError.localBlocked(reasons: reasons)
        }

        if let branch {
            let dir = packageURL.deletingLastPathComponent()
            let git = Git(runner: ProcessRunner(), repoURL: dir, repoName: dir.lastPathComponent)
            if try git.isDirty() {
                try git.stashIncludingUntracked(message: "ws local \(branch)")
            }
            try git.fetch()
            try git.checkout(branch)
        }

        let original = try String(contentsOf: packageURL, encoding: .utf8)
        let (updated, reports) = PackageEditor.applyLocalOverrides(to: original, targets: targets)

        let unmatched = reports.filter { !$0.matched }.map {
            "'\($0.packageName)': no .dependency or .product line references it in \(packageURL.lastPathComponent)"
        }
        guard unmatched.isEmpty else {
            throw WorkspaceError.localBlocked(reasons: unmatched)
        }

        try updated.write(to: packageURL, atomically: true, encoding: .utf8)

        for report in reports {
            print("\(report.packageName)  \(report.dependencyLines) dependency · \(report.productLines) product")
        }
        print("updated \(packageURL.path)")
    }

    /// Resolve the positional path (relative to cwd) to an existing Package.swift file.
    private func resolvePackageManifest() throws -> URL {
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let base = URL(fileURLWithPath: packageManifest, relativeTo: cwd).standardizedFileURL

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: base.path, isDirectory: &isDirectory) else {
            throw ValidationError("no such path: \(base.path)")
        }
        let file = isDirectory.boolValue ? base.appendingPathComponent("Package.swift") : base
        guard fileManager.fileExists(atPath: file.path) else {
            throw ValidationError("no Package.swift at \(file.path)")
        }
        return file
    }
}
