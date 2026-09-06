import ArgumentParser
import Foundation
import WorkspaceKit

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show branch and working-tree state for every repo."
    )

    func run() throws {
        let workspace = try Workspace.fromEnvironment()
        let manifest = try ManifestStore(url: workspace.manifestURL).load()

        let rows = manifest.repos.map { row(for: $0, in: workspace) }
        printTable(rows)
    }

    private func row(for repo: Repo, in workspace: Workspace) -> Row {
        let url = workspace.url(for: repo)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Row(name: repo.name, branch: "—", state: "missing")
        }

        let git = Git(runner: ProcessRunner(), repoURL: url, repoName: repo.name)
        let branch = (try? git.currentBranch()) ?? "?"
        let dirty = (try? git.isDirty()) ?? false
        let delta = (try? git.upstreamDelta()) ?? nil

        var state = dirty ? "dirty" : "clean"
        if let delta {
            if delta.ahead > 0 { state += "  ↑\(delta.ahead)" }
            if delta.behind > 0 { state += "  ↓\(delta.behind)" }
        }
        return Row(name: repo.name, branch: branch, state: state)
    }

    private struct Row {
        let name: String
        let branch: String
        let state: String
    }

    private func printTable(_ rows: [Row]) {
        let nameWidth = max(4, rows.map(\.name.count).max() ?? 0)
        let branchWidth = max(6, rows.map(\.branch.count).max() ?? 0)

        func pad(_ text: String, _ width: Int) -> String {
            text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
        }

        print("\(pad("REPO", nameWidth))  \(pad("BRANCH", branchWidth))  STATE")
        for row in rows {
            print("\(pad(row.name, nameWidth))  \(pad(row.branch, branchWidth))  \(row.state)")
        }
    }
}
