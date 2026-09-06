import Foundation

/// Thin, read-only git queries for one repository.
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
}
