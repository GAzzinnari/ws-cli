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

`init`, `status`, `pulls`, `feature`, `local`, `clean`, `prune`, `test`.
`README.md` documents what each does.

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
| `Workspace` | `configURL(env:)` → `$WS_CONFIG` or `~/.ws.json`; `load(env:)` reads the manifest, resolves its `root`, checks it exists → `(Workspace, Manifest)`; `url(for:)` per-repo URL |
| `Manifest` / `Repo` | Codable models for `.ws.json`. `Manifest.root` is the absolute workspace path. `Repo.defaultBranch` / `Repo.packageName` are optional |
| `ManifestStore` | load / save the manifest at a given URL (pretty-printed, sorted keys, trailing newline) |
| `RepoScanner` | Direct children of the root containing a `.git` entry, sorted |
| `BuildCleaner` | Recursive walk of a root for `.build` dirs (no exclusions, no symlink follow); size + delete for `ws clean` |
| `BranchPruner` | Per repo for `ws prune`: delete local branches except current + default; soft (`-d`) keeps unmerged as `keptUnmerged`, force (`-D`) with `-f` |
| `ProcessRunning` (protocol) / `ProcessRunner` | Run an external command → `CommandResult`. `ProcessRunner.runCombined` merges stdout+stderr into one pipe (for `jarvis test`'s xcodebuild-sized output) |
| `TestOutputParser` / `TestReport` | Pure: scrape `jarvis test` console text → errors, deduped warnings, test totals, failing tests. Used by `ws test` |
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
- Manifest-based commands (`status`, `feature`, `local`, `clean`) call
  `Workspace.load()` — it reads `$WS_CONFIG` or `~/.ws.json` and resolves the
  recorded `root`. `ws init` is the only command that takes the *current
  directory* as the workspace and writes the manifest. Repo-local commands
  (`pulls`, `test`) inspect the current directory and ignore the manifest.
  `local` is both — manifest for the module paths, plus repo-local git on the
  Package.swift's own repo when `-b` is passed. `clean` reads only `root` from the manifest, then
  walks the tree with no exclusions. State which kind a new command is.
- There is no `WS_HOME`. The workspace root lives *in* the manifest (`root`),
  recorded from `ws init`'s cwd. The manifest file is never inside the workspace.
- **Mutating multi-repo commands preflight hard.** `feature` and `local` validate
  every target and collect *all* the failures first, then throw
  `WorkspaceError.featureBlocked` / `.localBlocked` with the full list and change
  nothing. New mutating commands follow the same shape.

## Known limitations / deferred

- `ProcessRunner.run` reads stdout then stderr sequentially. Fine for git's small
  output; a command streaming megabytes to both pipes could deadlock. `runCombined`
  (one merged pipe) is the workaround, used by `ws test`; the general
  concurrent-read fix is still deferred.
- `TestOutputParser` is regex line-scraping. jarvis pipes xcodebuild through
  **xcbeautify**, so the primary shapes are xcbeautify's (`❌`/`⚠️` diagnostics,
  `✔`/`✖ [Target] name … (N seconds)` test lines, ANSI colour stripped first);
  raw-xcodebuild patterns remain as a fallback. Verified against
  `example1.txt` / `example2.txt` (captured xcbeautify output). An `❌` line with
  `file:line:col:` is treated as a build error, one with only `file:line:` as an
  XCTest assertion.
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
`ws unlocal` (revert what `ws local` did).

`ws prune` shipped: it deletes every local branch except the current one and the
default branch (not a merged-into check); `-d` keeps unmerged branches, `-f`
forces `-D`.

## Build / run

```sh
swift build && swift run ws status     # dev
make install                           # release → ~/.local/bin/ws
```

`swift-tools-version: 6.2`, `swiftLanguageModes: [.v6]`. Single dependency:
swift-argument-parser.
