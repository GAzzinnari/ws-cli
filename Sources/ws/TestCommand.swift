import ArgumentParser
import Foundation
import WorkspaceKit

struct Test: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Run `jarvis test` in the current repo and summarize the result."
    )

    @Flag(name: [.customShort("v"), .customLong("verbose")],
          help: "Echo the raw jarvis output before the summary.")
    var verbose = false

    @Argument(parsing: .postTerminator,
              help: "Extra arguments passed through to `jarvis test` (after `--`).")
    var jarvisArgs: [String] = []

    func run() throws {
        let runner = ProcessRunner()
        guard (try? runner.run("which", ["jarvis"], in: nil))?.succeeded == true else {
            throw ValidationError("`jarvis` is not on PATH")
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        FileHandle.standardError.write(Data("running jarvis test…\n".utf8))

        let result = try runner.runCombined("jarvis", ["test"] + jarvisArgs, in: cwd)

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-test-\(Int(Date().timeIntervalSince1970)).log")
        try? result.stdout.write(to: logURL, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(Data("full log: \(logURL.path)\n".utf8))

        if verbose {
            print(result.stdout)
        }

        printSummary(TestOutputParser.parse(result.stdout), repo: cwd.lastPathComponent)

        if result.exitCode != 0 {
            throw ExitCode(result.exitCode)
        }
    }

    private func printSummary(_ report: TestReport, repo: String) {
        func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

        print("")
        print("jarvis test · \(repo)")
        print("")
        print("build   \(plural(report.errors.count, "error")) · \(plural(report.warningCount, "warning"))")

        if report.ranTests {
            var line = "tests   \(report.tests ?? 0) run"
            let failed = report.failed ?? 0
            line += failed > 0 ? " · \(failed) failed" : " · all passed"
            if let skipped = report.skipped { line += " · \(skipped) skipped" }
            if let duration = report.duration { line += " · \(String(format: "%.1f", duration))s" }
            print(line)
        } else {
            print("tests   did not run")
        }

        if !report.errors.isEmpty {
            print("\nerrors")
            for error in report.errors.prefix(20) { print("  · \(error)") }
            if report.errors.count > 20 { print("  … and \(report.errors.count - 20) more") }
        }

        if !report.failures.isEmpty {
            print("\nfailing")
            for failure in report.failures {
                print("  ✘ \(failure.test)")
                if let location = failure.location { print("      \(location)") }
                if let message = failure.message, !message.isEmpty { print("      \(message)") }
            }
        }

        if report.warningCount > 0 {
            print("\nwarnings  (\(report.warningCount) total, \(report.warnings.count) unique)")
            for warning in report.warnings.prefix(10) { print("  · \(warning)") }
            if report.warnings.count > 10 { print("  … and \(report.warnings.count - 10) more") }
        }
    }
}
