#!/usr/bin/env bash
# Rebuild `assets/rive/streak_flame.riv` from its source.
#
# **The `.riv` in `assets/` is a build artifact, and `rive/streak_flame/scene.rml`
# is the source.** That is the whole reason Rive was acceptable here: the
# objection to it was that a binary blob is un-greppable and un-reviewable, and
# a committed-text scene with a one-command build voids that -- a reviewer reads
# the markup, and `git diff` on a geometry change is a diff.
#
# The built file is committed anyway, because `flutter build` cannot run this and
# a missing asset degrades silently (see `lib/ui/widgets/streak/streak_flame.dart`).
# So: edit the RML, run this, commit both.
#
#     ./rive/streak_flame/build.sh
#
# Requires the Rive CLI (`brew install rive-app/rive/rive`, or see `rive doctor`).
# No login needed -- `--once` writes an unsigned file, and unsigned only matters
# to web runtimes rejecting unsigned *scripts*. There are no scripts here.
set -euo pipefail

cd "$(dirname "$0")"
root=$(cd ../.. && pwd)

if ! command -v rive >/dev/null 2>&1; then
    echo "error: the rive CLI is not on PATH. See rive/streak_flame/AGENTS.md." >&2
    exit 1
fi

# Both checks, because neither is a superset of the other: --verify compiles
# scripts and shaders, `inspect` resolves bind paths and state machines and is
# the only one that reports a `problems` list. Neither looks at a pixel, which
# is what `sheet.py` is for.
rive . --verify
rive inspect . --summary >/dev/null

rive . --once
cp build/streak_flame.riv "$root/assets/rive/streak_flame.riv"
echo "wrote assets/rive/streak_flame.riv ($(wc -c < build/streak_flame.riv | tr -d ' ') bytes)"
