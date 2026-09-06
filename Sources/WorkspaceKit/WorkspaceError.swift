import Foundation

/// Every failure the CLI can report to the user, with a message written for a human.
public enum WorkspaceError: Error, CustomStringConvertible {
    case workspaceRootMissing(String)
    case manifestNotFound(String)
    case gitFailed(repo: String, command: String, stderr: String)
    case commandFailed(repo: String, command: String, stderr: String)
    case unrecognizedRemote(String)
    case openFailed(url: String, stderr: String)
    case featureBlocked(reasons: [String])
    case localBlocked(reasons: [String])
    case cleanFailed(paths: [String])
    case pruneFailed(entries: [String])

    public var description: String {
        switch self {
        case .workspaceRootMissing(let path):
            return "the workspace directory recorded in the manifest is gone: \(path) — re-run 'ws init'"
        case .manifestNotFound(let path):
            return "no manifest at \(path) — cd to your workspace and run 'ws init' first"
        case .gitFailed(let repo, let command, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git \(command) failed in \(repo): \(detail)"
        case .commandFailed(let repo, let command, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "`\(command)` failed in \(repo): \(detail)"
        case .unrecognizedRemote(let url):
            return "don't know how to turn this remote into a web URL: \(url)"
        case .openFailed(let url, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "could not open \(url): \(detail)"
        case .featureBlocked(let reasons):
            return (["cannot start feature:"] + reasons.map { "  - \($0)" }).joined(separator: "\n")
        case .localBlocked(let reasons):
            return (["cannot apply local overrides:"] + reasons.map { "  - \($0)" }).joined(separator: "\n")
        case .cleanFailed(let paths):
            return (["could not delete:"] + paths.map { "  - \($0)" }).joined(separator: "\n")
        case .pruneFailed(let entries):
            return (["could not delete some branches:"] + entries.map { "  - \($0)" }).joined(separator: "\n")
        }
    }
}
