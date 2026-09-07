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

`cd` to the directory that holds your repo checkouts and run `ws init`:

```sh
cd ~/Developer/MyApp
ws init
```

No environment variable to set. `ws init` takes the current directory as the
workspace, scans its direct children for git repos, and writes the manifest to
`~/.ws.json` (or `$WS_CONFIG`, if set, treated as an exact file path). The
manifest records the workspace path, so every other command works from anywhere.

For each repo it stores:

- `defaultBranch` — `main` or `master`, whichever exists locally (omitted if
  neither does)
- `packageName` — for a repo named `ios-<x>`, the value `<x>` (omitted otherwise);
  used by `ws local`

```json
{
  "root": "/Users/me/Developer/MyApp",
  "repos": [
    { "defaultBranch": "main", "name": "MainApp", "path": "MainApp" },
    { "defaultBranch": "main", "name": "ios-networking", "packageName": "networking", "path": "ios-networking" },
    { "name": "scratch", "path": "scratch" }
  ]
}
```

`path` is relative to `root`. Re-run `ws init` (from the workspace directory)
whenever you add or remove a repo.

## Commands

### `ws init`

Take the current directory as the workspace, scan it, and (re)write the manifest
(`~/.ws.json` or `$WS_CONFIG`). Prints each repo with its default branch and
package name.

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
command ignores the manifest entirely). Reads `git remote get-url origin`,
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

### `ws feature -b <branch> --repos a,b,c [-f] [-g]`

Start one branch across several repos at once. For every listed repo it fetches,
fast-forwards that repo's default branch to the remote, and cuts `<branch>` from
there.

Every repo is checked before any is touched: valid branch name, repo is in the
manifest and on disk, a default branch is recorded, `<branch>` doesn't already
exist, the local default branch is fast-forwardable, and — unless `-f` — the
working tree is clean. Any failure lists every reason and changes nothing.

`-f` / `--force` runs `git stash push --include-untracked` in each dirty repo
instead of refusing. Stashed changes stay stashed; they do not follow onto the
new branch.

`-g` / `--generate` runs `jarvis generate` in each repo after branching (needs
`jarvis` on `PATH`, checked during preflight).

```
$ ws feature -b feature/login --repos CoreNetworking,FeatureLogin
CoreNetworking  fetched · branched from origin/main
FeatureLogin  fetched · branched from origin/main
2 repos on feature/login
```

### `ws local <package-swift-path> -p a,b,c [-b <branch>]`

Rewrite a `Package.swift` so chosen packages resolve to local checkouts in the
workspace instead of remote versions. Package names are given in stripped form —
`networking` for the repo `ios-networking`. A directory is accepted in place of
the file path.

Line by line, for each named package:

- a line with `.dependency(` that mentions the package →
  `.dependency(path: "<absolute path to the repo in the workspace>")`
- a line with `.package(id:` that mentions the package (a SwiftPM registry
  dependency, e.g. `.package(id: "acme.networking", exact: "1.5.0")`) →
  `.package(path: "<absolute path to the repo in the workspace>")`
- a line with `.product(` that mentions the package → its `package:` argument
  becomes `"ios-networking"` (the full repo name)

A `.product(` line is not required: a package that is only referenced by a
`.dependency(` or `.package(id:` line is still redirected.

Indentation and trailing commas are kept. If a named package isn't in the
manifest, or isn't referenced anywhere in the file, the command lists the reason
and writes nothing.

`-b` / `--branch` first stashes any changes, fetches, and checks out `<branch>`
in the Package.swift's repo, then applies the edit.

```
$ ws local App/Package.swift -p networking,login
networking  1 dependency · 0 registry · 1 product
login  1 dependency · 0 registry · 1 product
updated /Users/me/Developer/MyApp/App/Package.swift
```

### `ws clean [-n | --dry-run]`

Walk the whole workspace tree and delete every directory named `.build`, nested
ones included. It only reads `root` from the manifest, then walks the tree
directly — nothing is excluded from the walk (`.git` and everything else is
descended into, just never matched).

`-n` / `--dry-run` lists what would be removed and its size, and deletes nothing.
A deletion that fails (permissions) doesn't stop the rest — the failed paths are
listed and the command exits `1`.

```
$ ws clean -n
would remove  App/.build       (412 MB)
would remove  Core/.build      (1.1 GB)
would remove  Core/Examples/Demo/.build  (88 MB)
3 .build directories · 1.6 GB — dry run, nothing deleted

$ ws clean
removing  App/.build       (412 MB)
removing  Core/.build      (1.1 GB)
removing  Core/Examples/Demo/.build  (88 MB)
removed 3 .build directories · freed 1.6 GB
```

### `ws prune [-n | --dry-run] [-f | --force]`

In every repo, delete local branches — keeping only the branch currently checked
out and the repo's default branch.

- Default is a **soft** delete (`git branch -d`): a branch git considers not
  fully merged is left in place and reported as `kept unmerged`. That's not an
  error — the command carries on and still exits `0`.
- `-f` / `--force` uses `git branch -D`, removing branches regardless of merge
  state.
- `-n` / `--dry-run` lists the candidates per repo and deletes nothing.
- A repo with no recorded default branch, or a missing directory, is skipped and
  noted. A real git error (not an unmerged refusal) is reported and makes the
  command exit `1`.

```
$ ws prune -n
ios-networking  would delete feature/old-thing, spike/idea
MainApp         nothing to prune
2 branches would be deleted — dry run

$ ws prune
ios-networking  deleted feature/old-thing · kept unmerged spike/idea
MainApp         nothing to prune
deleted 1 branch
```

### `ws test [-v | --verbose] [-- <jarvis args>]`

Run `jarvis test` (xcodebuild under the hood) for the repo **in the current
directory** — like `ws pulls`, this one ignores the manifest — capture its
output, and print a summary:

- `build` — error and warning counts (compiler warnings deduped)
- `tests` — total run, failed, skipped, wall-clock; or `did not run` if the
  build failed first
- `failing` — each failing test as `Suite.testName`, with `file:line` and the
  assertion message when they're in the output
- `warnings` — the unique warning messages (capped)

Anything after `--` is forwarded to `jarvis test` (scheme, `-only-testing:`,
etc.). `-v` echoes the raw output before the summary. The full log is always
written to a temp file, path printed on stderr. `ws test` exits with `jarvis`'s
own exit code.

```
$ ws test
running jarvis test…
full log: /var/folders/…/ws-test-1788737854.log

jarvis test · ios-login

build   0 errors · 3 warnings
tests   142 run · 2 failed · 1 skipped · 47.2s

failing
  ✘ LoginViewModelTests.test_invalid_email
      LoginViewModelTests.swift:88
      XCTAssertEqual failed: ("nil") is not equal to ("Invalid email")
  ✘ NetTests.test_timeout
      NetTests.swift:20
      Asynchronous wait failed: Exceeded timeout of 5 seconds

warnings  (3 total, 2 unique)
  · 'foo(_:)' is deprecated: use 'bar(_:)'
  · variable 'x' was never used
```

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | a runtime error (no manifest — run `ws init`, recorded workspace gone, git failure, blocked `feature` / `local` preflight, unrecognized remote) |
| `64` | usage error — bad flag, missing argument, no `Package.swift` at the given path, `jarvis` not on `PATH` (from ArgumentParser) |
| other | `ws test` exits with `jarvis`'s own exit code (e.g. `65` when tests fail) |

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
