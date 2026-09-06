import ArgumentParser
import Foundation
import WorkspaceKit

struct Prune: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Delete local branches in every repo except the current one and the default branch."
    )

    @Flag(name: [.customShort("n"), .customLong("dry-run")],
          help: "List what would be deleted, delete nothing.")
    var dryRun = false

    @Flag(name: [.customShort("f"), .customLong("force")],
          help: "Use `git branch -D` — delete branches even when not merged.")
    var force = false

    func run() throws {
        let (workspace, manifest) = try Workspace.load()
        let pruner = BranchPruner(workspace: workspace, manifest: manifest, runner: ProcessRunner(), force: force)
        let results = try pruner.run(dryRun: dryRun)

        var deletedTotal = 0
        var failureEntries: [String] = []

        for result in results {
            if let skipped = result.skipped {
                print("\(result.repo)  skipped: \(skipped)")
                continue
            }

            if dryRun {
                print("\(result.repo)  " + (result.deleted.isEmpty
                    ? "nothing to prune"
                    : "would delete \(result.deleted.joined(separator: ", "))"))
                continue
            }

            guard result.didAnything else {
                print("\(result.repo)  nothing to prune")
                continue
            }

            var parts: [String] = []
            if !result.deleted.isEmpty {
                parts.append("deleted \(result.deleted.joined(separator: ", "))")
            }
            if !result.keptUnmerged.isEmpty {
                parts.append("kept unmerged \(result.keptUnmerged.joined(separator: ", "))")
            }
            if !result.failures.isEmpty {
                parts.append("failed \(result.failures.map(\.branch).joined(separator: ", "))")
            }
            print("\(result.repo)  \(parts.joined(separator: " · "))")

            deletedTotal += result.deleted.count
            failureEntries += result.failures.map { "\(result.repo)/\($0.branch): \($0.message)" }
        }

        if dryRun {
            let n = results.reduce(0) { $0 + $1.deleted.count }
            print("\(n) branch\(n == 1 ? "" : "es") would be deleted — dry run")
            return
        }

        print("deleted \(deletedTotal) branch\(deletedTotal == 1 ? "" : "es")")

        if !failureEntries.isEmpty {
            throw WorkspaceError.pruneFailed(entries: failureEntries)
        }
    }
}
