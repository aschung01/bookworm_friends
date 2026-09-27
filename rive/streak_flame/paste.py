#!/usr/bin/env python3
"""Splice `smooth.py`'s output into `scene.rml`, keeping the ids a push wrote in.

    ../../.venv/bin/python rive/streak_flame/paste.py          # show what would change
    ../../.venv/bin/python rive/streak_flame/paste.py --write   # do it

**Why this is not "just paste it".** `smooth.py` prints the two flame paths and the `Idle`
lick's keyframes, and the instruction has always been to paste them into `scene.rml` by hand —
which is right about the scene being the source of truth and readable on its own, and which
also means every geometry change is a three-region manual edit across ~400 lines. Worse, the
committed scene carries `id="0:NNN"` on every object because `rive push` writes them in (that
is how it matches objects up to update the same file rather than creating a new one), and the
generator does not emit them. A literal paste therefore *drops 400 ids*, and the next push
reports everything as created-and-deleted instead of updated.

So this transplants values while keeping ids, positionally: the generator and the scene have
the same objects in the same order, so line `i` of one corresponds to line `i` of the other.
Every pair is checked to be the same tag before anything is written, and the script refuses to
write if any pair disagrees — which is what makes "positionally" safe rather than a guess.

**It is a paste helper, not a build step.** Nothing runs it automatically and the scene stays
the thing you read and edit. Run it after changing `smooth.py`, then `build.sh`, then look at
`sheet.py` and `motion.py`.
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).parent
SCENE = HERE / "scene.rml"

# The three regions of `smooth.py`'s output that live in `scene.rml`, and how to find each in
# the scene. The striations are skipped deliberately: they depend on none of the flame's
# scale constants, so re-splicing them is churn with no possible change.
#
# `start` is a literal that appears exactly once in the scene and marks the first line of the
# region; the region's length is taken from the generated block, and every line is then
# checked tag-for-tag.
REGIONS = [
    ("flame_outer", "flame_inner", 'name="flame_outer"'),
    ("flame_inner", "leaf striations", 'name="flame_inner"'),
    ("Idle: the tips' lick", None, "<!-- the body's tips -->"),
]


def generated() -> str:
    out = subprocess.run(
        [sys.executable, str(HERE / "smooth.py")],
        cwd=HERE,
        check=True,
        capture_output=True,
        text=True,
    )
    return out.stdout


def section(gen: str, name: str, nxt: str | None) -> list[str]:
    a = gen.index(f"<!-- {name}")
    a = gen.index("\n", a) + 1
    b = gen.index(f"<!-- {nxt}") if nxt else len(gen)
    return [ln for ln in gen[a:b].rstrip("\n").split("\n") if ln.strip()]


def tag(line: str) -> str:
    m = re.match(r"\s*<!?/?([A-Za-z-]+)", line)
    return m.group(1) if m else line.strip()


def ids(line: str) -> str:
    m = re.search(r'\s(id="[^"]*")', line)
    return m.group(1) if m else ""


def transplant(scene_line: str, gen_line: str) -> str:
    """`gen_line` at `scene_line`'s indentation, carrying `scene_line`'s id."""
    indent = scene_line[: len(scene_line) - len(scene_line.lstrip())]
    body = gen_line.strip()
    keep = ids(scene_line)
    if keep and keep not in body:
        # Ids go last, immediately before the tag closes. Both `/>` and `>` occur here.
        if body.endswith("/>"):
            body = body[:-2].rstrip() + f" {keep}/>"
        elif body.endswith(">"):
            body = body[:-1].rstrip() + f" {keep}>"
    return indent + body


def main(argv: list[str]) -> int:
    gen = generated()
    scene = SCENE.read_text()
    lines = scene.split("\n")

    edits: list[tuple[int, int, list[str]]] = []
    for name, nxt, anchor in REGIONS:
        block = section(gen, name, nxt)
        hits = [i for i, ln in enumerate(lines) if anchor in ln]
        if len(hits) != 1:
            print(f"error: {anchor!r} appears {len(hits)} times in scene.rml")
            return 1
        at = hits[0]
        # The path regions anchor on the `<Shape>` tag, so step forward to the first vertex.
        if "Vertex" in block[0]:
            while "Vertex" not in lines[at]:
                at += 1
        want = [ln for ln in lines[at : at + len(block)]]
        for i, (have, new) in enumerate(zip(want, block)):
            if tag(have) != tag(new):
                print(
                    f"error: {name} line {i} is <{tag(have)}> in the scene and "
                    f"<{tag(new)}> in the generator — the structure moved, so a "
                    f"positional splice would scramble it"
                )
                return 1
        replaced = [transplant(h, n) for h, n in zip(want, block)]
        changed = sum(1 for h, r in zip(want, replaced) if h != r)
        print(f"{name}: {len(block)} lines, {changed} changed")
        edits.append((at, len(block), replaced))

    if "--write" not in argv:
        print("\n(dry run — pass --write to apply)")
        return 0

    # Applied back-to-front so earlier indices stay valid.
    for at, n, replaced in sorted(edits, reverse=True):
        lines[at : at + n] = replaced
    SCENE.write_text("\n".join(lines))
    print(f"\nwrote {SCENE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
