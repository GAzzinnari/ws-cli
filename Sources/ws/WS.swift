import ArgumentParser

@main
struct WS: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ws",
        abstract: "Multi-repo workspace helper.",
        subcommands: [Init.self, Status.self, Pulls.self, Feature.self, Local.self, Clean.self]
    )
}
