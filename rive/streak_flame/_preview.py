#!/usr/bin/env python3
"""Shared plumbing for looking at the flame.

Two jobs, both awkward enough to be worth centralising.

**A cream ground.** `rive --screenshot` composites onto its own opaque #1D1D1D and
there is no flag to change it: a `kind="fragment"` document may not declare a
`<Backboard>`, and `rive.yaml`'s `artboard.background` applies only to projects
with no RML. A chroma key cannot recover an alpha it was never given -- the first
attempt at one reported the glow as a solid black disc that does not exist. So
these scripts build a *patched copy* of the project with a cream rectangle behind
everything, and the shipped scene stays transparent. An earlier version of this
shipped a preview-only rectangle inside `scene.rml` and switched it on with a
bound number; that stopped being possible when the state machine went away, and
it is better this way -- no preview scaffolding in the asset at all.

**Time, not a scrub.** The choreography is an ordinary timeline now, so a frame is
addressed by `--advance=<n>ms`. Note `--advance=0` renders the *authored* values
rather than frame 0 of the animation, which looks like a finished flame and is a
convincing way to think the whole thing is broken. Anything asking for time zero
gets a single frame instead.

**Choosing which timeline plays.** There is no `--animation` flag: `rive --help`
offers `--artboard` and nothing below it, and what the previewer plays is the
artboard's *first* animation. So `Idle` can only be watched by building a copy
whose animations are in the other order, which is what `first_animation` does.

There used to be a third job here -- patching the book's authored transform to
where `Ignite` leaves it, because `Idle` keys only the flame and everything else
fell back to the authored *shut* pose, so the loop played over a closed book. That
was the wrong place to fix it: it made the preview right and left the file wrong,
which a human scrubbing `Idle` in the Rive Editor found immediately. `scene.rml`
now authors the open pose and `Ignite` keys the shut one at frame 0, so there is
nothing left to patch.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).parent
BUILD = HERE / "build"

# kCandleGlow, the ground `streak_celebration.dart` paints behind the artboard.
GROUND = (255, 232, 196)
GROUND_HEX = "FFFFE8C4"

# The previewer's own canvas, for the strips that judge silhouette instead of colour.
CANVAS = (29, 29, 29)

FPS = 60


def preview_project(
    *,
    name: str = "preview",
    first_animation: str | None = None,
) -> Path:
    """A copy of the project, patched for looking at rather than for shipping."""
    out = BUILD / name
    out.mkdir(parents=True, exist_ok=True)
    shutil.copy(HERE / "rive.yaml", out / "rive.yaml")

    scene = (HERE / "scene.rml").read_text()

    if first_animation:
        blocks = re.findall(
            r"[ \t]*<LinearAnimation\b.*?</LinearAnimation>\n", scene, re.S
        )
        if len(blocks) < 2:
            raise SystemExit("expected more than one timeline to reorder")
        wanted = [b for b in blocks if f'name="{first_animation}"' in b]
        if len(wanted) != 1:
            raise SystemExit(f"no single timeline named {first_animation!r}")
        rest_blocks = [b for b in blocks if b is not wanted[0]]
        for block in blocks:
            scene = scene.replace(block, "", 1)
        scene = scene.replace(
            "    </Artboard>", "".join(wanted + rest_blocks) + "    </Artboard>", 1
        )

    # The ground goes immediately before the first interpolator, which is after every
    # shape and therefore backmost: draw order is declaration order, front first.
    ground = (
        f'        <Shape x="152" y="152" name="__ground">\n'
        f'            <Rectangle width="304" height="304" name="P"/>\n'
        f'            <Fill name="Fill"><SolidColor colorValue="{GROUND_HEX}" name="C"/></Fill>\n'
        f"        </Shape>\n\n"
    )
    scene, count = re.subn(
        r"(?=        <CubicEaseInterpolator)", ground, scene, count=1
    )
    if count != 1:
        raise SystemExit("could not find where to insert the preview ground")

    (out / "scene.rml").write_text(scene)
    return out


def shot(project: Path, out: Path, ms: float) -> Path:
    """Render one frame of `project` at `ms` into `out`."""
    # `--advance=0` applies no animation at all and shows the authored pose. One
    # frame is the closest addressable thing to t=0.
    advance = f"{max(ms, 1000 / FPS):.3f}ms"
    subprocess.run(
        ["rive", ".", f"--screenshot={out}", f"--advance={advance}"],
        cwd=project,
        check=True,
        capture_output=True,
    )
    return out
