# CLAUDE.md

Context for working on `ws-cli` in future sessions.

## What this is

`ws` is a Swift command-line tool for driving a multi-repo iOS workspace (main
app + feature/core modules, each its own git repo, all under one directory).

It is also a **learning project**. The owner is an experienced Swift / UIKit /
iOS engineer deliberately learning how to build terminal apps in Swift — process
spawning, SPM executables, git integration, distribution. Explanations of what is
different from app development are welcome; hand-holding on Swift the language is
not.

## Commands today

`init`, `status`, `pulls`, `feature`, `local`. `README.md` documents what each does.

## Working preferences (important)

- **No tests.** The owner explicitly does not want a test target, `Tests/`
  directory, or TDD on this project. Do not add them or propose them.
- **Keep process light.** Short design in chat, get a yes, build it. No spec
  docs or implementation-plan files for changes this size.

## Architecture

Two targets, and the split is deliberate — keep it:

- `Sources/ws/` — the executable (`@main` in `WS.swift`). One file per subcommand
  (`InitCommand`, `StatusCommand`, `PullsCommand`, `FeatureCommand`,
  `LocalCommand`). This target is **thin**: parse args, call into `WorkspaceKit`,
  format output. It is the only target that imports ArgumentParser.
- `Sources/WorkspaceKit/` — all logic. No ArgumentParser import. Public API.

Key types in `WorkspaceKit`:

| Type | Role |
|---|---|
| `Workspace` | Resolves `WS_HOME` → root URL; gives `.ws.json` path and per-repo URLs |
| `Manifest` / `Repo` | Codable models for `.ws.json`. `Repo.defaultBranch` and `Repo.packageName` are optional |
| `ManifestStore` | load / save `.ws.json` (pretty-printed, sorted keys, trailing newline) |
| `RepoScanner` | Direct children of the root containing a `.git` entry, sorted |
| `ProcessRunning` (protocol) / `ProcessRunner` | Run an external command → `CommandResult` |
| `Git` | Per-repo git via `ProcessRunning`: reads (branch, dirty, upstream delta, default branch), actions (fetch, stash, checkout, create branch, ff-merge), predicates (local/remote branch exists, is-ancestor) |
| `FeatureStarter` | Orchestrates `ws feature`: preflight every module, then execute (stash → checkout default → ff-merge → branch) |
| `PackageEditor` | Pure line-based `Package.swift` rewrite for `ws local`: `.dependency(…)` → `.dependency(path:)`, `.product` `package:` → full repo name |
| `RemoteWebURL` | Pure: git remote URL → `https://host/owner/repo` |
| `Opener` | Hand a URL to macOS `open` |
| `WorkspaceError` | Single error enum, `CustomStringConvertible`, human-readable messages |

## Conventions to follow when adding a command

- New subcommand = new file in `Sources/ws/`, registered in `WS.swift`'s
  `subcommands:` array. Give it a `CommandConfiguration` with `commandName` and
  `abstract`.
- Put anything beyond arg-parsing and printing into `WorkspaceKit`.
- `Git` runs commands through `ProcessRunning`, never `Process` directly. That
  protocol is the seam (currently unused since there are no tests, but keep it).
- `ProcessRunner` execs `/usr/bin/env <cmd> …` so `PATH` lookup works without
  hardcoding paths.
- **Degrade, don't abort.** `status` swallows per-repo git failures into a
  placeholder rather than failing the whole run. Batch commands should do the
  same and aggregate an exit code at the end.
- Errors the user should see: `throw` a `WorkspaceError` case. ArgumentParser
  prints `Error: <description>` to stderr and exits 1. Add a case rather than
  printing ad hoc.
- Diagnostics go to **stderr** (`FileHandle.standardError`), real output to
  stdout, so results stay pipeable. `pulls --print` is the reference: URL to
  stdout, "opening …" to stderr.
- `WS_HOME`-based commands (`init`, `status`, `feature`, `local`) go through
  `Workspace.fromEnvironment()`. Repo-local commands (`pulls`) inspect the current
  directory and ignore the manifest. `local` is both — manifest for the module
  paths, plus repo-local git on the Package.swift's own repo when `-b` is passed.
  State which kind a new command is.
- **Mutating multi-repo commands preflight hard.** `feature` and `local` validate
  every target and collect *all* the failures first, then throw
  `WorkspaceError.featureBlocked` / `.localBlocked` with the full list and change
  nothing. New mutating commands follow the same shape.

## Known limitations / deferred

- `ProcessRunner` reads stdout then stderr sequentially. Fine for git's small
  output; a command streaming megabytes to both pipes could deadlock. Real fix
  (concurrent reads) is deferred.
- `status` is sequential. Parallelizing across repos with `TaskGroup` is a
  planned step, not yet done.
- `feature` / `local` preflight hard, but do not roll back a failure that happens
  *during* execution — they stop and report which modules were already changed.
- `local`'s file edit is line-based and matches package names as a bare substring
  (a name inside a comment or a longer identifier on a `.dependency`/`.product`
  line would match). One call per line is assumed.
- macOS only (`open`, `expandingTildeInPath` behavior). No Linux support
  intended right now.

## Roadmap (owner's learning path, roughly in order)

`ws exec` → concurrent `ws status` → `ws sync` (fetch + ff-only pull) →
`ws prune` (delete branches merged into `defaultBranch`) → `ws unlocal`
(revert what `ws local` did).

## Build / run

```sh
swift build && swift run ws status     # dev
make install                           # release → ~/.local/bin/ws
```

Swift 6.3, `swiftLanguageModes: [.v6]`. Single dependency: swift-argument-parser.
