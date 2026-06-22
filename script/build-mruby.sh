#!/usr/bin/env bash
#
# Build DragonRuby's mruby-patched at a pinned commit and install the `mruby`
# interpreter to tmp/mruby/bin/mruby.
#
# mruby-patched is DragonRuby's open-source (MIT) interpreter source — the exact
# language runtime DR ships, minus the proprietary GTK engine. Building it lets
# the test suite run the framework without the paid `dragonruby` binary.
#
# Idempotent: once the binary exists this is a no-op. Delete tmp/mruby to force a
# rebuild; bump MRUBY_SHA to track a new DR release.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Pinned so the language runtime is reproducible across machines and CI.
MRUBY_SHA="${MRUBY_SHA:-e670a7f80689a9298595bf4ed15f905a89781856}"
MRUBY_REPO="https://github.com/DragonRuby/mruby-patched.git"

SRC="$ROOT/tmp/mruby-patched"
DEST="$ROOT/tmp/mruby"
BIN="$DEST/bin/mruby"

if [ -x "$BIN" ]; then
  echo "mruby already built: $BIN"
  exit 0
fi

mkdir -p "$ROOT/tmp"

if [ ! -d "$SRC/.git" ]; then
  echo "Cloning mruby-patched..."
  git clone "$MRUBY_REPO" "$SRC"
fi

echo "Checking out $MRUBY_SHA..."
if ! git -C "$SRC" checkout -q "$MRUBY_SHA" 2>/dev/null; then
  git -C "$SRC" fetch origin
  git -C "$SRC" checkout -q "$MRUBY_SHA"
fi

echo "Building mruby (build_config/default.rb)..."
# The stock default build config pulls the full default gembox (enum-ext,
# numeric-ext, struct, metaprog, ...) the framework relies on. Prefer `rake`;
# fall back to the bundled `minirake` when rake isn't on PATH (e.g. minimal CI).
if command -v rake >/dev/null 2>&1; then
  ( cd "$SRC" && MRUBY_CONFIG=default rake )
else
  ( cd "$SRC" && MRUBY_CONFIG=default ./minirake )
fi

mkdir -p "$DEST/bin"
cp "$SRC/build/host/bin/mruby" "$BIN"

echo "Installed: $BIN"
"$BIN" --version
