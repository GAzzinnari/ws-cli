import Foundation

/// The outcome of running an external command.
public struct CommandResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public var succeeded: Bool { exitCode == 0 }

    public var trimmedStdout: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Abstraction over "run a command and hand me back its output".
/// Kept as a protocol so `Git` can be driven without spawning real processes.
public protocol ProcessRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], in directory: URL?) throws -> CommandResult
}

/// The real implementation, backed by `Foundation.Process`.
public struct ProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: String, _ arguments: [String], in directory: URL?) throws -> CommandResult {
        let process = Process()
        // `/usr/bin/env` resolves the executable on PATH for us.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let directory {
            process.currentDirectoryURL = directory
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()

        // Fine for the small outputs git produces here. A command that streams
        // megabytes to both pipes at once could still deadlock — Phase 2 problem.
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self),
            exitCode: process.terminationStatus
        )
    }

    /// Like `run`, but stdout and stderr are merged into one stream. Safe for
    /// commands that pour a lot into both at once (one pipe, one drain, no
    /// two-pipe deadlock). `stderr` in the result is always empty.
    public func runCombined(_ executable: String, _ arguments: [String], in directory: URL?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let directory {
            process.currentDirectoryURL = directory
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return CommandResult(
            stdout: String(decoding: data, as: UTF8.self),
            stderr: "",
            exitCode: process.terminationStatus
        )
    }
}
