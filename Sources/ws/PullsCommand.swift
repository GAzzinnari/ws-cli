import ArgumentParser
import Foundation
import WorkspaceKit

struct Pulls: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pulls",
        abstract: "Open the pull requests page for the repo in the current directory."
    )

    @Flag(name: [.customShort("p"), .customLong("print")],
          help: "Print the URL instead of opening it.")
    var printURL = false

    func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let runner = ProcessRunner()
        let git = Git(runner: runner, repoURL: cwd, repoName: cwd.lastPathComponent)

        let remote = try git.remoteURL()
        guard let web = RemoteWebURL.web(from: remote) else {
            throw WorkspaceError.unrecognizedRemote(remote)
        }
        let target = web + "/pulls"

        if printURL {
            print(target)
        } else {
            FileHandle.standardError.write(Data("opening \(target)\n".utf8))
            try Opener.open(target, runner: runner)
        }
    }
}
