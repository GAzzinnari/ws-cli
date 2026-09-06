import ArgumentParser
import Foundation
import WorkspaceKit

struct Feature: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "feature",
        abstract: "Start a branch across repos: fetch, fast-forward the default branch, branch from it."
    )

    @Option(name: [.customShort("b"), .customLong("branch")], help: "Name of the new branch.")
    var branch: String

    @Option(name: .long, help: "Comma-separated repo names from the manifest.")
    var repos: String

    @Flag(name: [.customShort("f"), .customLong("force")],
          help: "Stash uncommitted changes in each repo instead of refusing to start.")
    var force = false

    @Flag(name: [.customShort("g"), .customLong("generate")],
          help: "Run `jarvis generate` in each repo after branching.")
    var generate = false

    func run() throws {
        let names = repos
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !names.isEmpty else {
            throw ValidationError("--repos needs at least one repo name")
        }

        let (workspace, manifest) = try Workspace.load()
        let starter = FeatureStarter(
            workspace: workspace,
            manifest: manifest,
            runner: ProcessRunner(),
            branch: branch,
            repoNames: names,
            force: force,
            generate: generate
        )

        let outcomes = try starter.run()

        for outcome in outcomes {
            let stash = outcome.stashed ? "stashed · " : ""
            let gen = outcome.generated ? " · generated" : ""
            print("\(outcome.module)  \(stash)fetched · branched from \(outcome.base)\(gen)")
        }
        print("\(outcomes.count) repo\(outcomes.count == 1 ? "" : "s") on \(branch)")
    }
}
