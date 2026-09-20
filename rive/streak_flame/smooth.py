#!/usr/bin/env python3
"""Turn a list of points into a smooth closed Rive path, and fit the page-edge hairlines.

**This exists because hand-writing cubic handles does not work.** `CubicMirroredVertex`
takes one `rotation` and one `distance` and uses them for both sides of the vertex, so a
smooth curve requires the incoming and outgoing tangents to be collinear *and* the handle
length to suit both neighbouring segments at once. Three drafts of the flame were tuned by
eye against that constraint and all three came out faceted: over-long handles bulged the
short segments, and a tangent chosen to suit one neighbour kinked the other. The visible
result was a gothic leaf with near-straight sides and a hard diamond point at its base.

`CubicDetachedVertex` gives each side its own angle and length, which makes the handles a
calculation rather than a guess. This uses the Catmull-Rom construction -- the tangent at a
point is half the vector between its two neighbours, and the control points sit a third of
that away on each side -- which is the standard way to fit a smooth curve through a fixed
set of points, and is what a design tool's "smooth" button does.

    ../../../../.venv/bin/python smooth.py

The output is pasted into `scene.rml` rather than generated at build time on purpose: the
scene is the source of truth and is meant to be readable and editable on its own, including
in the Rive Editor. Edit the point lists here, re-run, paste. Keeping the script means the
next person moving a vertex does not have to re-derive eight tangents by hand.
"""

from __future__ import annotations

import math
import sys

TAU = math.tau

# Clockwise from the apex. The apex itself is a corner, not a smooth point, so it is listed
# here for the neighbours' tangents but emitted as a `StraightVertex`.
#
# The shape: a sharp leaning tip, a shoulder that lets the upper two thirds taper gradually,
# the widest point about a quarter of the way up, and a base wide enough to sit *down in* the
# gutter rather than balance on it.
FLAME_OUTER = [
    (8, -126),
    (30, -70),
    (40, -30),
    (19, 2),
    (0, 8),
    (-19, 0),
    (-37, -34),
    (-25, -74),
]

# The core: the same silhouette at about 0.6, so the two read as one flame rather than as a
# shape with a dagger inside it.
FLAME_INNER = [
    (5, -84),
    (17, -48),
    (23, -22),
    (11, 2),
    (0, 6),
    (-11, 1),
    (-21, -24),
    (-14, -52),
]


def emit(points: list[tuple[float, float]], indent: str = " " * 20) -> str:
    """One `PointsPath` body: a sharp first vertex, smooth everywhere else."""
    n = len(points)
    lines = [f'{indent}<StraightVertex x="{points[0][0]}" y="{points[0][1]}"/>']
    for i in range(1, n):
        (px, py) = points[(i - 1) % n]
        (nx, ny) = points[(i + 1) % n]
        tx, ty = (nx - px) / 2, (ny - py) / 2
        out = math.atan2(ty, tx) % TAU
        dist = math.hypot(tx, ty) / 3
        x, y = points[i]
        lines.append(
            f'{indent}<CubicDetachedVertex x="{x}" y="{y}"'
            f' inRotation="{(out + math.pi) % TAU:.4f}" inDistance="{dist:.2f}"'
            f' outRotation="{out:.4f}" outDistance="{dist:.2f}"/>'
        )
    return "\n".join(lines)


# The page-edge hairlines. **They run ACROSS the block, not up it**, and getting that
# backwards is the most basic thing the drawing got wrong: the pages are sheets lying flat,
# stacked through the block's thickness, so what you see looking at the block's edge is one
# thin horizontal band per sheet. The lines between them are therefore horizontal -- parallel
# to the cover. Drawn vertically, as they were for several passes, they correspond to nothing
# physical at all; they read as a comb, or as a ruler's graduations, which is exactly how
# every review described them without anyone naming the cause.
#
# There is no attempt at one line per sheet. A half-block is a couple of hundred sheets in
# eleven points of screen, so these are suggestive: five per half, evenly spaced, with the
# alpha varied so the stack does not read as ruled notepaper.
#
# Numbers that have to agree with `base_pages` / `leaf_pages` in scene.rml.
BAND_TOP = -30  # the base half's page block, in book space
BAND_BOTTOM = -8
BAND_INSET = 3  # no line closer than this to either face
LINE_X = 55  # the band spans x 6..104; a line spans 12..98, centred here
LINE_W = 86
LINE_H = 1.2
# kCandleStockTop, at five different strengths. A uniform alpha reads as a manufactured
# grid; paper clumps.
LINE_ALPHA = ("30", "22", "2C", "1C", "28")


def striations(prefix: str, *, flipped: bool, indent: str = " " * 16) -> str:
    """One half's hairlines, in that half's own local space.

    `flipped` is for the leaf, whose 180-degree rotation about the hinge means its local y
    runs the other way: a line that must end up at book `y` has to be authored at
    `BAND_TOP - y` instead. The two halves' lines then land at the *same* heights once the
    book is open, which they should -- the halves are one block split, so their layers line
    up across the gutter. Shut, they stack into an evenly ruled slab for the same reason.
    """
    n = len(LINE_ALPHA)
    span = (BAND_BOTTOM - BAND_INSET) - (BAND_TOP + BAND_INSET)
    out = []
    for i, alpha in enumerate(LINE_ALPHA):
        book_y = BAND_TOP + BAND_INSET + span * i / (n - 1)
        y = BAND_TOP - book_y if flipped else book_y
        out.append(
            f'{indent}<Shape x="{LINE_X}" y="{y:g}" name="{prefix}{i + 1}">'
            f'<Rectangle width="{LINE_W}" height="{LINE_H}" name="P"/>\n'
            f'{indent}    <Fill name="Fill">'
            f'<SolidColor colorValue="{alpha}26190A" name="C"/></Fill></Shape>'
        )
    return "\n".join(out)


def main() -> int:
    for name, points in (("flame_outer", FLAME_OUTER), ("flame_inner", FLAME_INNER)):
        top = min(y for _, y in points)
        bottom = max(y for _, y in points)
        print(f"<!-- {name}: gradient startY={top} endY={bottom} -->")
        print(emit(points))
        print()
    print("<!-- leaf striations -->")
    print(striations("ls", flipped=True))
    print()
    print("<!-- base striations -->")
    print(striations("bs", flipped=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
