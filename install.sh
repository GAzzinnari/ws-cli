#!/bin/sh
# Install `ws` from source: clone the repo, run `make install`, discard the checkout.
#
#   curl -fsSL https://raw.githubusercontent.com/GAzzinnari/ws-cli/master/install.sh | sh
#
# Environment overrides:
#   WS_CLI_REPO  git URL to clone       (default: https://github.com/GAzzinnari/ws-cli.git)
#   WS_CLI_REF   branch / tag / commit  (default: master)
#   PREFIX       install prefix         (default: ~/.local  ->  binary at ~/.local/bin/ws)
#   BINDIR       exact bin directory    (overrides PREFIX)

set -eu

REPO="${WS_CLI_REPO:-https://github.com/GAzzinnari/ws-cli.git}"
REF="${WS_CLI_REF:-master}"

for tool in git make swift; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "install.sh: '$tool' is required but not on PATH" >&2
        exit 1
    }
done

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ws-cli.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

echo "cloning $REPO ($REF)"
if ! git clone --quiet --depth 1 --branch "$REF" "$REPO" "$tmp" 2>/dev/null; then
    # REF is a commit SHA, not a branch or tag
    git clone --quiet --depth 1 "$REPO" "$tmp"
    git -C "$tmp" fetch --quiet --depth 1 origin "$REF"
    git -C "$tmp" checkout --quiet FETCH_HEAD
fi

echo "building release and installing"
make -C "$tmp" install
