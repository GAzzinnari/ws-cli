import ArgumentParser
import Foundation
import WorkspaceKit

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scan the current directory for git repositories and record the workspace."
    )

    func run() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
        let scanned = try RepoScanner(root: root).scan()

        // Fill in each repo's default branch. A git failure for one repo leaves
        // it nil rather than aborting the whole init.
        let repos = scanned.map { repo -> Repo in
            let git = Git(runner: ProcessRunner(), repoURL: root.appendingPathComponent(repo.path), repoName: repo.name)
            var enriched = repo
            enriched.defaultBranch = (try? git.defaultBranch()) ?? nil
            enriched.packageName = packageName(forRepoNamed: repo.name)
            return enriched
        }

        let configURL = Workspace.configURL()
        try ManifestStore(url: configURL).save(Manifest(root: root.path, repos: repos))

        let noun = repos.count == 1 ? "repository" : "repositories"
        print("workspace \(root.path)")
        print("found \(repos.count) \(noun) → \(configURL.path)")
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
