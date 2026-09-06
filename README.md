# ws

A small command-line helper for working across a multi-repo setup — a main app
plus feature and core modules, each in its own git repository, all sitting in one
directory.

Built with Swift Package Manager and
[swift-argument-parser](https://github.com/apple/swift-argument-parser).

## Install

From anywhere — clones, builds a release, installs to `~/.local/bin/ws`, discards
the checkout:

```sh
curl -fsSL https://raw.githubusercontent.com/GAzzinnari/ws-cli/master/install.sh | sh
```

Overridable with environment variables:

```sh
curl -fsSL .../install.sh | WS_CLI_REF=v1.2.0 sh          # a tag or branch
curl -fsSL .../install.sh | PREFIX=/usr/local sudo -E sh  # system-wide
```

`WS_CLI_REPO`, `WS_CLI_REF`, `PREFIX`, `BINDIR` are all honored. Needs `git`,
`make`, and `swift` on `PATH`.

### From a local clone

```sh
make install                            # release → ~/.local/bin/ws
sudo make install PREFIX=/usr/local     # system-wide
make install BINDIR=$HOME/bin           # anywhere already on your PATH
make uninstall
```

`make` on its own just builds (`.build/release/ws`). `make help` lists targets.

## Setup

`ws` finds your repos through the `WS_HOME` environment variable — the directory
that contains all your module checkouts.

```sh
export WS_HOME=~/Developer/MyApp        # add to ~/.zshrc
ws init
```

`ws init` scans the direct children of `WS_HOME`, records every directory that
contains a `.git` entry, and writes `$WS_HOME/.ws.json`. For each repo it also
stores:

- `defaultBranch` — `main` or `master`, whichever exists locally (omitted if
  neither does)
- `packageName` — for a repo named `ios-<x>`, the value `<x>` (omitted otherwise);
  used by `ws local`

```json
{
  "repos" : [
    { "defaultBranch" : "main", "name" : "MainApp", "path" : "MainApp" },
    { "defaultBranch" : "main", "name" : "ios-networking", "packageName" : "networking", "path" : "ios-networking" },
    { "name" : "scratch", "path" : "scratch" }
  ]
}
```

`path` is relative to `WS_HOME`. Re-run `ws init` whenever you add or remove a
repo.

## Commands

### `ws init`

Scan `WS_HOME` and (re)write `.ws.json`. Prints each repo with its default branch
and package name.

### `ws status`

One row per repo: current branch, working-tree state, and how far ahead/behind
its upstream it is. Runs the repos sequentially. Always exits `0` — it is
informational. A repo whose directory is missing shows `missing`; a repo whose
git calls fail shows `?` / `clean` rather than aborting the whole table.

```
$ ws status
REPO            BRANCH         STATE
CoreNetworking  main           clean
FeatureLogin    main           clean  ↓1
MainApp         feature/login  dirty
```

### `ws pulls`

Open the pull-requests page for the repo **in the current directory** (this
command ignores `WS_HOME` / `.ws.json`). Reads `git remote get-url origin`,
converts it to an `https://host/owner/repo` URL, and opens `…/pulls`.

```
$ ws pulls                      # opens the browser
opening https://github.com/acme/MainApp/pulls

$ ws pulls --print              # -p: print the URL, open nothing
https://github.com/acme/MainApp/pulls
```

Handles `https://`, `ssh://`, and scp-like (`git@github.com:owner/repo.git`)
remotes, including enterprise hosts. `/pulls` is GitHub's path; GitLab and
Bitbucket use different ones and are not handled.

### `ws feature -b <branch> --modules a,b,c [-f]`

Start one branch across several modules at once. For every listed module it
fetches, fast-forwards that module's default branch to the remote, and cuts
`<branch>` from there.

Every module is checked before any is touched: valid branch name, module is in
the manifest and on disk, a default branch is recorded, `<branch>` doesn't
already exist, the local default branch is fast-forwardable, and — unless `-f` —
the working tree is clean. Any failure lists every reason and changes nothing.

`-f` / `--force` runs `git stash push --include-untracked` in each dirty module
instead of refusing. Stashed changes stay stashed; they do not follow onto the
new branch.

```
$ ws feature -b feature/login --modules CoreNetworking,FeatureLogin
CoreNetworking  fetched · branched from origin/main
FeatureLogin  fetched · branched from origin/main
2 modules on feature/login
```

### `ws local <package-swift-path> -p a,b,c [-b <branch>]`

Rewrite a `Package.swift` so chosen packages resolve to local checkouts under
`WS_HOME` instead of remote versions. Package names are given in stripped form —
`networking` for the repo `ios-networking`. A directory is accepted in place of
the file path.

Line by line, for each named package:

- a line with `.dependency(` that mentions the package →
  `.dependency(path: "<absolute path to $WS_HOME/ios-networking>")`
- a line with `.product(` that mentions the package → its `package:` argument
  becomes `"ios-networking"` (the full repo name)

Indentation and trailing commas are kept. If a named package isn't in the
manifest, or isn't referenced anywhere in the file, the command lists the reason
and writes nothing.

`-b` / `--branch` first stashes any changes, fetches, and checks out `<branch>`
in the Package.swift's repo, then applies the edit.

```
$ ws local App/Package.swift -p networking,login
networking  1 dependency · 1 product
login  1 dependency · 1 product
updated /Users/me/Developer/MyApp/App/Package.swift
```

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | a runtime error (`WS_HOME` unset, missing `.ws.json`, git failure, blocked `feature` / `local` preflight, unrecognized remote) |
| `64` | usage error — bad flag, missing argument, no `Package.swift` at the given path (from ArgumentParser) |

## Development

```sh
swift build           # debug build
swift run ws status   # run without installing
```

Layout:

- `Sources/ws/` — the executable. `@main` in `WS.swift`, one file per subcommand.
  Thin: it only wires ArgumentParser to `WorkspaceKit`.
- `Sources/WorkspaceKit/` — all the logic (manifest, scanning, git queries and
  actions, `Package.swift` editing). No ArgumentParser dependency.
