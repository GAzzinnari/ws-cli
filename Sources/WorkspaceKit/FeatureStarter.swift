import Foundation

/// Starts a feature branch across a set of workspace modules: fetch, fast-forward
/// each module's default branch, then cut the new branch from it.
///
/// Every module is preflighted before any of them is touched. If a preflight check
/// fails for any module, nothing is modified and `WorkspaceError.featureBlocked` is
/// thrown listing every reason.
public struct FeatureStarter: Sendable {
    /// What happened to one module.
    public struct Outcome: Sendable {
        public let module: String
        public let stashed: Bool
        /// The ref the new branch was cut from, e.g. `origin/main` or `main (local)`.
        public let base: String
        public let generated: Bool
    }

    let workspace: Workspace
    let runner: any ProcessRunning
    let branch: String
    let repoNames: [String]
    let force: Bool
    let generate: Bool

    public init(
        workspace: Workspace,
        runner: any ProcessRunning,
        branch: String,
        repoNames: [String],
        force: Bool,
        generate: Bool
    ) {
        self.workspace = workspace
        self.runner = runner
        self.branch = branch
        self.repoNames = repoNames
        self.force = force
        self.generate = generate
    }

    public func run() throws -> [Outcome] {
        let manifest = try ManifestStore(url: workspace.manifestURL).load()
        let plans = try preflight(manifest: manifest)
        return try execute(plans)
    }

    // MARK: - Preflight

    private struct Plan {
        let repo: Repo
        let git: Git
        let url: URL
        let defaultBranch: String
        let dirty: Bool
        let hasRemoteDefault: Bool
    }

    private func preflight(manifest: Manifest) throws -> [Plan] {
        var reasons: [String] = []
        var plans: [Plan] = []

        if !isValidBranchName(branch) {
            reasons.append("'\(branch)' is not a valid branch name")
        }

        if generate, !isOnPath("jarvis") {
            reasons.append("--generate needs 'jarvis' on PATH")
        }

        for name in repoNames {
            guard let repo = manifest.repo(named: name) else {
                reasons.append("\(name): not in the manifest")
                continue
            }
            let url = workspace.url(for: repo)
            guard FileManager.default.fileExists(atPath: url.path) else {
                reasons.append("\(name): directory is missing (\(url.path))")
                continue
            }
            guard let defaultBranch = repo.defaultBranch else {
                reasons.append("\(name): no default branch recorded — re-run 'ws init'")
                continue
            }

            let git = Git(runner: runner, repoURL: url, repoName: name)

            // Fetch first so the checks below see current remote refs. This is the
            // only preflight step that reaches the network; it changes no branch
            // and no working tree.
            do {
                try git.fetch()
            } catch {
                reasons.append("\(name): git fetch failed — \(error)")
                continue
            }

            let dirty = try git.isDirty()
            if dirty && !force {
                reasons.append("\(name): has uncommitted changes (pass -f to stash them)")
            }

            if try git.localBranchExists(branch) {
                reasons.append("\(name): branch '\(branch)' already exists")
            }

            let hasRemoteDefault = try git.remoteBranchExists(defaultBranch)
            if hasRemoteDefault,
               try !git.isAncestor(defaultBranch, of: "origin/\(defaultBranch)") {
                reasons.append("\(name): local \(defaultBranch) has diverged from origin/\(defaultBranch)")
            }

            plans.append(Plan(
                repo: repo,
                git: git,
                url: url,
                defaultBranch: defaultBranch,
                dirty: dirty,
                hasRemoteDefault: hasRemoteDefault
            ))
        }

        guard reasons.isEmpty else {
            throw WorkspaceError.featureBlocked(reasons: reasons)
        }
        return plans
    }

    // MARK: - Execute

    private func execute(_ plans: [Plan]) throws -> [Outcome] {
        var outcomes: [Outcome] = []
        for plan in plans {
            let git = plan.git
            var stashed = false

            if force && plan.dirty {
                try git.stashIncludingUntracked(message: "ws feature \(branch)")
                stashed = true
            }

            try git.checkout(plan.defaultBranch)

            let base: String
            if plan.hasRemoteDefault {
                try git.fastForwardMerge("origin/\(plan.defaultBranch)")
                base = "origin/\(plan.defaultBranch)"
            } else {
                base = "\(plan.defaultBranch) (local)"
            }

            try git.createBranch(branch)

            if generate {
                let result = try runner.run("jarvis", ["generate"], in: plan.url)
                guard result.succeeded else {
                    throw WorkspaceError.commandFailed(
                        repo: plan.repo.name,
                        command: "jarvis generate",
                        stderr: result.stderr
                    )
                }
            }

            outcomes.append(Outcome(
                module: plan.repo.name,
                stashed: stashed,
                base: base,
                generated: generate
            ))
        }
        return outcomes
    }

    private func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let result = try? runner.run("git", ["check-ref-format", "refs/heads/\(name)"], in: workspace.root)
        return result?.succeeded ?? false
    }

    private func isOnPath(_ tool: String) -> Bool {
        let result = try? runner.run("which", [tool], in: workspace.root)
        return result?.succeeded ?? false
    }
}
