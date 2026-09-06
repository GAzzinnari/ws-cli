import Foundation

/// Deletes local branches across the workspace, keeping only the checked-out
/// branch and the default branch in each repo.
public struct BranchPruner: Sendable {
    let workspace: Workspace
    let manifest: Manifest
    let runner: any ProcessRunning
    let force: Bool

    public init(workspace: Workspace, manifest: Manifest, runner: any ProcessRunning, force: Bool) {
        self.workspace = workspace
        self.manifest = manifest
        self.runner = runner
        self.force = force
    }

    /// What happened in one repo. In a dry run, `deleted` holds the candidates.
    public struct RepoResult: Sendable {
        public let repo: String
        public let deleted: [String]
        public let keptUnmerged: [String]
        public let failures: [(branch: String, message: String)]
        public let skipped: String?

        public var didAnything: Bool {
            !deleted.isEmpty || !keptUnmerged.isEmpty || !failures.isEmpty
        }
    }

    /// One `RepoResult` per manifest repo, in manifest order.
    public func run(dryRun: Bool) throws -> [RepoResult] {
        manifest.repos.map { result(for: $0, dryRun: dryRun) }
    }

    private func result(for repo: Repo, dryRun: Bool) -> RepoResult {
        let url = workspace.url(for: repo)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return skip(repo.name, "directory missing")
        }

        let git = Git(runner: runner, repoURL: url, repoName: repo.name)

        do {
            let current = try git.currentBranch()
            let liveDefault = try? git.defaultBranch()
            guard let defaultBranch = repo.defaultBranch ?? (liveDefault ?? nil) else {
                return skip(repo.name, "no default branch — re-run 'ws init'")
            }

            var keep: Set<String> = [defaultBranch]
            if current != "detached" { keep.insert(current) }

            let candidates = try git.localBranches().filter { !keep.contains($0) }

            if dryRun {
                return RepoResult(repo: repo.name, deleted: candidates, keptUnmerged: [], failures: [], skipped: nil)
            }

            var deleted: [String] = []
            var keptUnmerged: [String] = []
            var failures: [(branch: String, message: String)] = []

            for branch in candidates {
                do {
                    if try git.deleteBranch(branch, force: force) {
                        deleted.append(branch)
                    } else {
                        keptUnmerged.append(branch)
                    }
                } catch {
                    failures.append((branch, "\(error)"))
                }
            }

            return RepoResult(repo: repo.name, deleted: deleted, keptUnmerged: keptUnmerged, failures: failures, skipped: nil)
        } catch {
            return skip(repo.name, "\(error)")
        }
    }

    private func skip(_ repo: String, _ reason: String) -> RepoResult {
        RepoResult(repo: repo, deleted: [], keptUnmerged: [], failures: [], skipped: reason)
    }
}
