import Foundation

/// Thin git queries and actions for one repository.
public struct Git: Sendable {
    let runner: any ProcessRunning
    let repoURL: URL
    let repoName: String

    public init(runner: any ProcessRunning, repoURL: URL, repoName: String) {
        self.runner = runner
        self.repoURL = repoURL
        self.repoName = repoName
    }

    /// Current branch, or `"detached"` when HEAD is not on a branch.
    public func currentBranch() throws -> String {
        let branch = try git("rev-parse", "--abbrev-ref", "HEAD").trimmedStdout
        return branch == "HEAD" ? "detached" : branch
    }

    /// True when the working tree or index has changes.
    public func isDirty() throws -> Bool {
        !(try git("status", "--porcelain").trimmedStdout.isEmpty)
    }

    /// Commits ahead of / behind the tracked upstream, or `nil` when there is no upstream.
    public func upstreamDelta() throws -> (ahead: Int, behind: Int)? {
        let result = try runner.run(
            "git",
            ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
            in: repoURL
        )
        guard result.succeeded else { return nil } // no upstream configured

        // Output is "<behind>\t<ahead>": left side is upstream-only, right side is HEAD-only.
        let parts = result.trimmedStdout.split { $0 == " " || $0 == "\t" }
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else {
            return nil
        }
        return (ahead: ahead, behind: behind)
    }

    /// The push/fetch URL configured for a remote (default `origin`).
    public func remoteURL(named remote: String = "origin") throws -> String {
        try git("remote", "get-url", remote).trimmedStdout
    }

    /// The repo's default branch, from local branches only: `main` if it exists,
    /// otherwise `master`, otherwise `nil`.
    public func defaultBranch() throws -> String? {
        let branches = try git("branch", "--list", "--format=%(refname:short)", "main", "master")
            .trimmedStdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        if branches.contains("main") { return "main" }
        if branches.contains("master") { return "master" }
        return nil
    }

    // MARK: - Actions (mutating)

    /// Fetch from the default remote.
    public func fetch() throws {
        try git("fetch")
    }

    /// `git stash push --include-untracked` with a message.
    public func stashIncludingUntracked(message: String) throws {
        try git("stash", "push", "--include-untracked", "-m", message)
    }

    /// Check out an existing ref.
    public func checkout(_ ref: String) throws {
        try git("checkout", ref)
    }

    /// Create and check out a new branch from the current HEAD.
    public func createBranch(_ name: String) throws {
        try git("checkout", "-b", name)
    }

    /// Fast-forward the current branch to `ref`, or fail if it can't be a fast-forward.
    public func fastForwardMerge(_ ref: String) throws {
        try git("merge", "--ff-only", ref)
    }

    /// Delete a local branch. `force` maps to `-D`, otherwise `-d` (which git
    /// refuses for a branch that isn't fully merged).
    ///
    /// - Returns: `true` when the branch was deleted; `false` when a non-force
    ///   delete was refused because the branch is not fully merged.
    /// - Throws: `WorkspaceError.gitFailed` for any other failure.
    public func deleteBranch(_ name: String, force: Bool) throws -> Bool {
        let result = try runner.run("git", ["branch", force ? "-D" : "-d", name], in: repoURL)
        if result.succeeded { return true }
        if result.stderr.contains("not fully merged") { return false }
        throw WorkspaceError.gitFailed(
            repo: repoName,
            command: "branch \(force ? "-D" : "-d") \(name)",
            stderr: result.stderr
        )
    }

    // MARK: - Predicates (no throw on a "no" answer)

    /// Whether a local branch by this name exists.
    public func localBranchExists(_ name: String) throws -> Bool {
        try probe("rev-parse", "--verify", "--quiet", "refs/heads/\(name)")
    }

    /// Whether `<remote>/<name>` exists (call after `fetch()`).
    public func remoteBranchExists(_ name: String, remote: String = "origin") throws -> Bool {
        try probe("rev-parse", "--verify", "--quiet", "refs/remotes/\(remote)/\(name)")
    }

    /// Whether `ancestor` is an ancestor of `descendant` — i.e. `descendant` is a
    /// fast-forward away from `ancestor`.
    public func isAncestor(_ ancestor: String, of descendant: String) throws -> Bool {
        try probe("merge-base", "--is-ancestor", ancestor, descendant)
    }

    // MARK: - Lists

    /// Local branch names.
    public func localBranches() throws -> [String] {
        try git("for-each-ref", "--format=%(refname:short)", "refs/heads")
            .trimmedStdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    // MARK: -

    @discardableResult
    private func git(_ arguments: String...) throws -> CommandResult {
        let result = try runner.run("git", Array(arguments), in: repoURL)
        guard result.succeeded else {
            throw WorkspaceError.gitFailed(
                repo: repoName,
                command: arguments.joined(separator: " "),
                stderr: result.stderr
            )
        }
        return result
    }

    /// Run a git command purely for its exit status.
    private func probe(_ arguments: String...) throws -> Bool {
        try runner.run("git", Array(arguments), in: repoURL).succeeded
    }
}
