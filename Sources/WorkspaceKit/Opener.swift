import Foundation

/// Hands a URL to the OS to open in the default browser (macOS `open`).
public enum Opener {
    public static func open(_ target: String, runner: any ProcessRunning) throws {
        let result = try runner.run("open", [target], in: nil)
        guard result.succeeded else {
            throw WorkspaceError.openFailed(url: target, stderr: result.stderr)
        }
    }
}
