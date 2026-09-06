# ws

A small command-line helper for working across a multi-repo setup — a main app
plus feature and core modules, each in its own git repository, all sitting in one
directory.

Built with Swift Package Manager and
[swift-argument-parser](https://github.com/apple/swift-argument-parser).

## Install

```sh
make install          # builds release, copies to ~/.local/bin/ws
```

Other locations:

```sh
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
stores the default branch (`main` or `master`, whichever exists locally).

```json
{
  "repos" : [
    { "defaultBranch" : "main",   "name" : "CoreNetworking", "path" : "CoreNetworking" },
    { "defaultBranch" : "master", "name" : "LegacyKit",      "path" : "LegacyKit" },
    { "name" : "Oddball", "path" : "Oddball" }
  ]
}
```

`path` is relative to `WS_HOME`. A repo with neither `main` nor `master` locally
gets no `defaultBranch` key. Re-run `ws init` whenever you add or remove a repo.

## Commands

### `ws init`

Scan `WS_HOME` and (re)write `.ws.json`. Prints each repo and its default branch.

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

## Exit codes

| Code | Meaning |
|---|---|
| `0` | success |
| `1` | a runtime error (`WS_HOME` unset, no `.ws.json`, git failure, unrecognized remote) |
| `64` | usage error — bad flag or argument (from ArgumentParser) |

## Development

```sh
swift build           # debug build
swift run ws status   # run without installing
```

Layout:

- `Sources/ws/` — the executable. `@main` in `WS.swift`, one file per subcommand.
  Thin: it only wires ArgumentParser to `WorkspaceKit`.
- `Sources/WorkspaceKit/` — all the logic (manifest, scanning, git queries,
  process running). No ArgumentParser dependency.
