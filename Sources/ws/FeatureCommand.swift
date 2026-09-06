import ArgumentParser
import Foundation
import WorkspaceKit

struct Feature: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "feature",
        abstract: "Start a branch across modules: fetch, fast-forward the default branch, branch from it."
    )

    @Option(name: [.customShort("b"), .customLong("branch")], help: "Name of the new branch.")
    var branch: String

    @Option(name: .long, help: "Comma-separated module names from the manifest.")
    var modules: String

    @Flag(name: [.customShort("f"), .customLong("force")],
          help: "Stash uncommitted changes in each module instead of refusing to start.")
    var force = false

    @Flag(name: [.customShort("g"), .customLong("generate")],
          help: "Run `jarvis generate` in each module after branching.")
    var generate = false

    func run() throws {
        let names = modules
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !names.isEmpty else {
            throw ValidationError("--modules needs at least one module name")
        }

        let workspace = try Workspace.fromEnvironment()
        let starter = FeatureStarter(
            workspace: workspace,
            runner: ProcessRunner(),
            branch: branch,
            moduleNames: names,
            force: force,
            generate: generate
        )

        let outcomes = try starter.run()

        for outcome in outcomes {
            let stash = outcome.stashed ? "stashed · " : ""
            let gen = outcome.generated ? " · generated" : ""
            print("\(outcome.module)  \(stash)fetched · branched from \(outcome.base)\(gen)")
        }
        print("\(outcomes.count) module\(outcomes.count == 1 ? "" : "s") on \(branch)")
    }
}
