import ArgumentParser
import Foundation
import WorkspaceKit

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scan WS_HOME for git repositories and write \(Workspace.manifestFileName)."
    )

    func run() throws {
        let workspace = try Workspace.fromEnvironment()
        let scanned = try RepoScanner(root: workspace.root).scan()

        // Fill in each repo's default branch. A git failure for one repo leaves
        // it nil rather than aborting the whole init.
        let repos = scanned.map { repo -> Repo in
            let git = Git(runner: ProcessRunner(), repoURL: workspace.url(for: repo), repoName: repo.name)
            var enriched = repo
            enriched.defaultBranch = (try? git.defaultBranch()) ?? nil
            enriched.packageName = packageName(forRepoNamed: repo.name)
            return enriched
        }

        try ManifestStore(url: workspace.manifestURL).save(Manifest(repos: repos))

        let noun = repos.count == 1 ? "repository" : "repositories"
        print("found \(repos.count) \(noun) → \(workspace.manifestURL.path)")
        for repo in repos {
            let pkg = repo.packageName.map { ", package \($0)" } ?? ""
            print("  \(repo.name)  (\(repo.defaultBranch ?? "no default branch")\(pkg))")
        }
    }

    /// `ios-<x>` → `<x>`, anything else → nil.
    private func packageName(forRepoNamed name: String) -> String? {
        let prefix = "ios-"
        guard name.hasPrefix(prefix) else { return nil }
        let stripped = String(name.dropFirst(prefix.count))
        return stripped.isEmpty ? nil : stripped
    }
}
