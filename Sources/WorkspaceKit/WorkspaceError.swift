import Foundation

/// Every failure the CLI can report to the user, with a message written for a human.
public enum WorkspaceError: Error, CustomStringConvertible {
    case wsHomeNotSet
    case wsHomeNotADirectory(String)
    case manifestNotFound(String)
    case gitFailed(repo: String, command: String, stderr: String)
    case unrecognizedRemote(String)
    case openFailed(url: String, stderr: String)
    case featureBlocked(reasons: [String])
    case localBlocked(reasons: [String])

    public var description: String {
        switch self {
        case .wsHomeNotSet:
            return "WS_HOME is not set. Point it at your workspace, e.g. export WS_HOME=~/TestWorkspace"
        case .wsHomeNotADirectory(let path):
            return "WS_HOME is not a directory: \(path)"
        case .manifestNotFound(let path):
            return "no manifest at \(path) — run 'ws init' first"
        case .gitFailed(let repo, let command, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git \(command) failed in \(repo): \(detail)"
        case .unrecognizedRemote(let url):
            return "don't know how to turn this remote into a web URL: \(url)"
        case .openFailed(let url, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "could not open \(url): \(detail)"
        case .featureBlocked(let reasons):
            return (["cannot start feature:"] + reasons.map { "  - \($0)" }).joined(separator: "\n")
        case .localBlocked(let reasons):
            return (["cannot apply local overrides:"] + reasons.map { "  - \($0)" }).joined(separator: "\n")
        }
    }
}
