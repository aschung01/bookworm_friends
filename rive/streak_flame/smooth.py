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
from collections.abc import Callable, Mapping, Sequence

TAU = math.tau

# Clockwise from the apex. The apex itself is a corner, not a smooth point, so it is listed
# here for the neighbours' tangents but emitted as a `StraightVertex`.
#
# The shape: a sharp leaning tip, a shoulder that lets the upper two thirds taper gradually,
# the widest point about a quarter of the way up, and a base wide enough to sit *down in* the
# gutter rather than balance on it.
#
# **The last two points are the notch, and they are what stops this being a generic almond.**
# Duolingo's flame carries one kink in its upper left: a small step rising beside the main tip
# with a crease between them. Ours was a single smooth ogive, which is competent and anonymous
# -- the silhouette of every flame icon ever drawn. A secondary lick costs two vertices and is
# the whole difference between a shape someone recognises and one they don't.
#
# **The notch is 18 units below the main tip with a 12-unit crease, and the first attempt used
# almost exactly those same depths and still came out as a crown.** That is the useful part of
# this note, because the obvious diagnosis was wrong. Attempt one put the secondary tip 22
# below the apex and creased it 12 -- within a few units of what is here -- and it read as two
# horns with a deep V between them. Making the nick shallower was not the fix, and in fact the
# secondary tip ended up *higher* than it was (54 units below the apex in shipped units, where
# the first try was 66).
#
# What was actually wrong: attempt one *replaced* the tuned shoulder point (-25,-74) with
# (-30,-78) on the way to adding the notch, which left (-37,-34), (-30,-78), (-24,-104)
# **nearly collinear**. A Catmull-Rom fit through three points on a line is a line, so the whole
# left belly went flat, and a sharp tip on top of a straight diagonal edge is a horn no matter
# how shallow you crease it. The curve was never lost to the corner vertices; it was lost to
# the point placement.
#
# So the notch sits *above* the original shoulder rather than in place of it, and the belly
# curve is the one that was already tuned over three passes. The lesson generalises: when a
# silhouette goes wrong after adding detail, check what the addition displaced before
# adjusting the detail itself.
#
# Both notch vertices are in `CORNERS`, which makes the crease two short straight segments. A
# Catmull-Rom valley is a *dimple*: the fit rounds it into a soft wobble that reads as a lumpy
# outline. Fire has sharp tips.
#
# **These are the shape at its original size and are not what ships.** `SCALE_X` / `SCALE_Y`
# below blow them up, and the numbers in `scene.rml` are the scaled output. Keeping the small
# list as the source is the point: the silhouette was arrived at over several passes (four
# mirrored vertices gave an egg, six evenly spaced ones gave a gothic leaf) and the scale is a
# separate, later decision that should not be baked into it.
#
# **The two upper side points are bowed outward, and that is an answer to one verdict on the
# widened flame: "looks too fat .. maybe bc the left and right sides are too angled".** The
# diagnosis in that sentence is the correct one and is worth keeping, because the obvious
# reading -- that a fat shape needs narrowing -- is wrong here and would have undone the
# widening that had just been asked for. Nothing about the *width* changed: max width is 0.815
# of the height before and 0.814 after.
#
# What was wrong is where the turn happened. The widest vertex is where the outline stops going
# out and starts coming in, and its Catmull-Rom tangent is taken from its two neighbours -- with
# 1 at (30,-70) and 3 at (19,2) that chord is almost vertical, so the curve passed the widest
# point going straight down and the run above it was a nearly straight 20-degree diagonal off
# the apex. Out at 20 degrees, then down, then in at the foot: three directions, which is what
# an eye reads as planes rather than as a curve. Measured as the outline's deviation from the
# apex-to-widest chord, the side bulge was **5.5%** of that chord -- a plank with a kink. Moving
# 1 and 7 out and up puts it at **8.7%**, which spreads that turn over the whole run.
#
# **Three stronger candidates were rendered and a reader picked this one, which is the mildest.**
# `sides.py`'s sheet had bow 6 (this), bow 9, bow 12, and bow 9 plus a ten-unit lift of the
# widest pair -- that last one moves the mass up and the shoulder in, and reads least fat of the
# five. It was not chosen. Two things the rejected ones establish anyway: bow 12 pushes max
# width to 0.834 and starts swallowing the notch, so the bow has a ceiling well under that; and
# lifting the widest pair is the lever for "fat" specifically, if the complaint comes back after
# this.
#
# **Anisotropic scale is why any of this was needed, and that is not obvious.** `SCALE_X` is 2.38
# against `SCALE_Y`'s 1.8, and stretching one axis does not preserve a tangent's angle -- it
# flattens every slope toward the horizontal. This same point list read fine at 1.8/1.8. So a
# silhouette tuned at uniform scale has to be re-judged after the aspect changes, and judged
# *through* the scale, which is what `sides.py` does -- it renders candidates via `icon.py`'s
# fit rather than plotting the raw point list.
#
# **Ten vertices, and it has to stay ten.** `Idle`'s lick keyframes address vertices by id
# (`0:286`, `0:287`, `0:293`, `0:299`, and the core's), and `paste.py` matches ids to emitted
# lines positionally. Inserting a point to buy smoother sides would re-key the animation onto
# the wrong vertices, and nothing would report it.
FLAME_OUTER = [
    (8, -126),
    (33, -72),
    (40, -30),
    (19, 2),
    (0, 8),
    (-19, 0),
    (-37, -34),
    (-28, -76),
    (-22, -108),
    (-10, -96),
]

# Which vertices are corners rather than smooth points. Index 0 is always one.
CORNERS = frozenset({8, 9})

# How much to round each corner, in final artboard units, keyed by index into `FLAME_OUTER`.
#
# **Sharp tips are the single least cute thing a flame shape can have**, and a reader's verdict
# on the pointed version was blunt. `StraightVertex` carries a `radius`, so the corner topology
# that makes the notch a notch survives while the points themselves become lobes -- which is
# the whole trick, because rounding by moving vertices instead would soften the crease as well
# and turn the notch back into the dimple it started as.
#
# The main tip is rounded hardest and the crease least: a lobe wants to be round, a crease
# wants to stay legible. Set any of these to 0 to get the pointed version back.
RADII = {0: 18, 8: 14, 9: 9}

# The core: **a symmetric teardrop, and deliberately NOT a copy of the body's silhouette.**
#
# This reverses the oldest note about this shape, which said the core had to be the same
# outline so the two would read as one flame rather than as a shape with a dagger inside it.
# The premise was sound and the conclusion inverted: reusing the outline is exactly what made
# it read as a dagger, because the body's silhouette is a tall tapering leaf with a lean in it,
# and shrunk to 40% that stops being a flame and becomes a spine. A reader supplied Duolingo's
# mark and the difference was immediate -- theirs is a fat round belly low down, tapering to a
# small rounded point, and nothing about it echoes the outline it sits in.
#
# **The size did not change and was never the problem.** Measured against the reference, their
# core is about 39% of the body's width and 44% of its height; ours was 37% and 43.5% before
# this change and is 39% and 46% after. Three options were rendered -- the old mini-flame, this
# teardrop, and this teardrop lifted clear of the base -- and the lift was rejected: the core
# stays planted on the body's foot.
#
# **No notch on this one.** The secondary lick is a feature of the outline, and repeating it on
# an inner shape at under half the size reads as a printing misregistration.
#
# The widest pair sits at y=-25, about a third of the way up, which is what makes it a belly
# rather than an ellipse. These raw numbers are round rather than exact because this list is
# meant to stay hand-editable; they were chosen so that after `core()` and `scaled()` the shape
# lands within a unit of the measured target in every direction.
FLAME_INNER = [
    (0, -89),
    (16, -59),
    (23, -25),
    (15, -1),
    (0, 6),
    (-15, -1),
    (-23, -25),
    (-16, -59),
]

# The core's tip is rounded, like the body's. In final artboard units, as `RADII` is.
#
# A teardrop with a sharp point is a *leaf*, and the whole reason this shape changed was to stop
# the core looking like a blade. 9 is a little more rounding than the proportional equivalent of
# the body's 18, on purpose: the core is small enough that a hard point on it reads as an
# artefact rather than as a tip.
CORE_RADII = {0: 9}

# How much smaller the core is than the list above, shrunk about its own base so it stays
# planted while its tip drops.
#
# **It was effectively 1.0 and the flame read as an outline.** At that size the core was 57% of
# the body's width and 67% of its height -- about 38% of its area -- so the body survived only
# as a rim around a big pale fill, which is what an outlined icon looks like rather than what
# fire looks like. Duolingo's is a compact bright droplet sitting low inside a solid mass;
# theirs is maybe 15% of the area. 0.65 puts ours at roughly 17%, with its tip 52% of the way
# down from the apex instead of 31%.
#
# Note the mild circularity now that `FLAME_INNER` is a teardrop authored to a measured target:
# its raw numbers were picked knowing this factor. Changing it will rescale the core rather than
# reproportion it, which is fine -- but the target proportions above are the thing to re-measure
# against, not this number.
CORE_SHRINK = 0.65

# **The flame is drawn 1.8x the shape above, in both directions.** It was 3x for several
# revisions and a reader called it out: at 3x the body was 231 units across against a 209-wide
# book, so the fire overhung the thing it was burning on by 40% each side and the book read as
# a small stand rather than as the subject. 1.8x puts the body at 139, comfortably inside the
# covers, which is a flame *on* a book.
#
# **Shrinking the flame is not what made it smaller on screen, and it must not.** On-screen
# height is `(flame / artboard) x stageSize`, so a 40% smaller flame in the same frame is also
# a 40% smaller flame in the app -- which would have thrown away the whole reason the box went
# to 252. The artboard came down 480 -> 300 in the same change, so the flame holds about 80% of
# the frame either way and what actually changed is the *book*, which now fills 70% of the
# width instead of 44%. Same ratio, same on-screen flame. See the note on
# `StreakFlame.stageSize`.
#
# **`SCALE_X` and `SCALE_Y` are no longer equal, and the note here said for a long time that
# they must be.** That note read: they were 3 and 2 once, on the theory that a uniform belly is
# too wide against the book -- true, and the wrong lever, because the aspect went 1:1.7 to
# 1:2.4 and a reader called the ratio weird immediately; width against the book is a *scale*
# problem with a scale answer, and it was never the aspect's job to fix it.
#
# Every sentence of that is still true and none of it generalises. What was wrong there was
# using anisotropic scale to fix a width-against-the-book problem, and stretching the flame
# **taller**. This is the opposite move on purpose: the same reader asked for the flame to be
# *wider*, at the aspect of the Phosphor `fire` glyph the app used to draw beside it.
#
# 2.3869 is solved rather than chosen. Phosphor Fill's `fire` measures 704 x 864 in its 1024
# em, so **0.8148** wide-to-tall; `rive/streak_flame/icon.py` reports the aspect of the fitted
# curve including the corner radii, and this is the `SCALE_X` at which it reads 0.8148 to four
# places. For reference the shape was 1:1.607 at 1.8 and Duolingo's mark is about 1:1.15, so
# this lands between the two, nearer theirs.
#
# **Re-solve this whenever `FLAME_OUTER` moves.** It was 2.3849 until the side points were
# bowed; the bow adds a little width of its own, which dropped the aspect to 0.8142 and had to
# be given back. A hand-held value here is the one way the app's icon could quietly stop being
# Phosphor's proportion while every test still passed, since the pin in
# `streak_flame_mark_test.dart` follows whatever the generator emits.
#
# **What it costs, measured, because it is not free.** The body goes 138.6 -> 183.8 units wide
# against a 208-wide book, so flame/book goes 0.666 -> 0.880 -- and a reader explicitly asked
# for 0.663 two rounds ago ("shrink it just around 40%" from 1.10). That instruction is
# superseded by this one rather than forgotten. The sharper cost is at the *burst*: `Ignite`
# peaks at `fire.scaleX` 1.28, and with `flame_outer`'s own 1.14 squash on top of it the fire
# reaches 268 units, so it overhangs the book by about 30 units each side for a few frames
# where at 1.8 it stayed inside. The frame still holds it (the artboard is 300) and `aspect.py`
# prints the window, but note the obvious trim does not exist: holding 268 down to 208 needs an
# effective 1.13, which is less than the settled flame plus its squash.
SCALE_X: float = 2.3869
SCALE_Y: float = 1.8

# Where the flame's lowest vertex sits in `fire`'s local space, after scaling.
#
# **The flame may stand on the paper rather than down in the gutter**, which is the permission
# that makes a uniform 3x possible at all. The base is authored at y=+8, eight units *into* the
# page block, because at the original size that is what stopped it balancing on the gutter and
# meeting the book in a maroon pinch. Scaled with everything else that becomes 24 units, and
# the open page block is only 22 thick — so the foot would come out of the underside of the
# book. Sinking it proportionally is meaningless anyway: the bite is a contact detail with a
# physical size, not a feature of the flame that should grow with it.
#
# So the whole path is translated up by however much the scale added, leaving the lowest point
# here. The offset is computed from `FLAME_OUTER` and applied to *both* paths, so the core's
# foot keeps sitting the same 2 units above the body's instead of both being flattened onto
# one line.
BASE_Y = 4


def scaled(points: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
    drop = max(y for _, y in FLAME_OUTER) * SCALE_Y - BASE_Y
    return [(x * SCALE_X, y * SCALE_Y - drop) for x, y in points]


def tangent(points: Sequence[tuple[float, float]], i: int) -> tuple[float, float, float, float]:
    """The Catmull-Rom handles at `points[i]`, as `(inRot, inDist, outRot, outDist)`.

    Pulled out of `emit` so that `lick` can re-fit a neighbour whose tangent depends on a
    vertex the idle loop moves. Both callers must agree exactly or a keyed tangent would
    step away from the authored one at frame 0.
    """
    n = len(points)
    (px, py) = points[(i - 1) % n]
    (nx, ny) = points[(i + 1) % n]
    tx, ty = (nx - px) / 2, (ny - py) / 2
    out = math.atan2(ty, tx) % TAU
    dist = math.hypot(tx, ty) / 3
    return (out + math.pi) % TAU, dist, out, dist


def emit(
    points: Sequence[tuple[float, float]],
    indent: str = " " * 20,
    corners: frozenset[int] = frozenset(),
    radii: Mapping[int, float] | None = None,
) -> str:
    """One `PointsPath` body: sharp at index 0 and at `corners`, smooth everywhere else."""
    radii = radii or {}
    n = len(points)
    lines = []
    for i in range(n):
        x, y = points[i]
        if i == 0 or i in corners:
            r = f' radius="{radii[i]:g}"' if radii.get(i) else ""
            lines.append(f'{indent}<StraightVertex x="{x:g}" y="{y:g}"{r}/>')
            continue
        in_rot, in_dist, out_rot, out_dist = tangent(points, i)
        lines.append(
            f'{indent}<CubicDetachedVertex x="{x:g}" y="{y:g}"'
            f' inRotation="{in_rot:.4f}" inDistance="{in_dist:.2f}"'
            f' outRotation="{out_rot:.4f}" outDistance="{out_dist:.2f}"/>'
        )
    return "\n".join(lines)


def core(points: Sequence[tuple[float, float]]) -> list[tuple[float, float]]:
    base = max(y for _, y in points)
    return [
        (x * CORE_SHRINK, base + (y - base) * CORE_SHRINK) for x, y in points
    ]


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


# --- the idle flicker ------------------------------------------------------------------

# The tips' vertical excursion during `Idle`, as `(frame, dy)` in the **same raw units as
# `FLAME_OUTER` / `FLAME_INNER`** -- so a lick scales with `SCALE_Y` (and, for the core,
# `CORE_SHRINK`) like every other coordinate, and a future change of either cannot silently
# leave the loop behind. That has happened twice already with numbers a preview script kept
# a copy of (`IGNITE_FRAMES`, the 304x304 ground), and a keyframe is the same hazard: a
# hand-written -253.4 is correct at 1.8x and a mystery at any other scale.
#
# **Why vertices at all, when `Idle` already scales the shapes.** Measured, the first version
# of this loop moved the apex 25px up and down and swelled the belly 15px wide -- a ratio of
# 1.67:1, so the flame was breathing sideways almost as much as it was rising. Fire holds its
# width and does its moving at the tip. Cutting `scaleX` fixes the sideways half, but raising
# `scaleY` to compensate stretches the *whole* shape, belly included, and a uniformly pulsing
# silhouette is a throbbing logo. Keying the tips is the only way the top can move while the
# body stays put.
#
# **And these tables are irregular on purpose, which is the second and larger correction.**
# The first attempt gave each tip four evenly-eased beats, and a reader's verdict was exact:
# Duolingo's flame *flickers*, ours *bounced*. Both words are about rhythm, not amount. Four
# smooth symmetric beats over 1.2s is a 1.7Hz sine -- which is a bounce however tall it is,
# because the eye can predict where the tip goes next. So:
#
#   * roughly four times as many beats, at **irregular 3-to-5 frame gaps** so no two tips and
#     no two cycles line up;
#   * amplitudes that **vary from beat to beat** and straddle zero, instead of alternating
#     between one high and one low;
#   * `linear` interpolation rather than the eased curve the rest of `Idle` uses, so each beat
#     arrives with a corner in it. Same reasoning as the embers' opacity, which is linear
#     because an eased fade on something four pixels across reads as a curve where a flicker
#     is wanted. A flame's tip changes direction abruptly; easing every change is what made
#     this a bounce. At a beat every four frames each segment is under 70ms, where easing
#     would barely be perceptible anyway -- the irregularity does the work, not the curve.
#
# **Segments are checked for speed, not just for spacing** -- see `_check_lick`. The first
# irregular draft had gaps of 7 frames carrying only 4 units, and because the interpolation is
# linear that came out as the tip drifting at about 1px a frame for an eighth of a second: a
# visible stall, once per loop, which is exactly the sort of regular event a flicker must not
# have. It was obvious in `build/flicker.py`'s per-frame deltas and invisible in every
# amplitude measurement, because the span was unchanged. The check caught two more of these
# the first time it ran, in tables that had already been eyeballed as irregular.
#
# The tables are hand-written rather than generated from noise, because a seed that happens to
# read well is not reviewable and a loop has to seam. Every one starts and ends at 0, so
# position is continuous across the seam. *Velocity* is not, and that is fine for the same
# reason the beats are linear: with a corner at every one of seventeen keys, one more at the
# seam is indistinguishable from the rest. Under the old eased keys this mattered and the seam
# had to be a resting point.
#
# For the outer flame, index 0 is the main apex and index 8 the secondary lick above the
# notch; **9 is left alone** deliberately, being the bottom of the crease -- moving it with 8
# would slide the notch bodily instead of letting the lick rise out of it. The core is a
# plain ring of eight with no notch, so only its index 0 is a tip at all.
TIP_LICK = {
    0: (
        (0, 0), (4, -7), (8, 3), (12, -9), (17, -1), (21, -11), (25, -3),
        (30, -9), (34, 4), (38, -5), (43, -11), (47, -4), (52, -9), (56, 2),
        (61, -6), (65, -11), (69, -3), (72, 0),
    ),
    8: (
        (0, 0), (5, -5), (11, 3), (18, -6), (24, 1), (31, -6), (37, 2),
        (44, -7), (50, -1), (57, -8), (63, 3), (69, -3), (72, 0),
    ),
}

# The core's tip, on its own schedule again. **Raw amplitudes here buy less than the outer
# flame's**: a `dy` passes through `CORE_SHRINK` as well as `SCALE_Y`, so 1 raw unit is 1.17
# final units against the body's 1.8. The numbers look comparable and land smaller, which is
# right -- the core is the smaller shape and should not out-move the silhouette containing it.
#
# It exists because the reader's note was about the **inner** flame as well as the outer one.
# A core that only scales is a shape breathing inside a shape that flickers.
CORE_LICK = {
    0: (
        (0, 0), (3, -5), (9, 3), (14, -7), (20, 2), (26, -4), (32, -10),
        (39, 1), (45, -6), (51, 3), (58, -4), (64, -10), (70, -2), (72, 0),
    ),
}

# The slowest segment a flicker table may contain, in raw units per frame. Below this a linear
# segment reads as a drift rather than a beat.
#
# **It was 0.8 for one round and that was not tight enough.** At 0.8 a five-frame segment moves
# the tip one screen pixel per frame, and `build/flicker.py`'s delta row showed exactly that --
# a visible five-frame lull, in the same place every 1.2 seconds. 1.0 is the point where the
# slowest beat still moves about two pixels a frame, which no longer reads as a pause. The
# practical effect is a floor on amplitude: at a four-frame gap a beat has to carry at least
# four raw units, so the tables cannot contain a beat too small to see.
MIN_LICK_SPEED = 1.0


def _check_lick() -> None:
    """Refuse to emit a table that stalls, ends somewhere other than where it started, or
    runs past the loop. All three have been shipped by hand at least once."""
    for name, table in (("TIP_LICK", TIP_LICK), ("CORE_LICK", CORE_LICK)):
        for index, beats in table.items():
            if beats[0] != (0, 0) or beats[-1][1] != 0:
                raise SystemExit(f"{name}[{index}] must start and end at dy 0")
            for (f0, d0), (f1, d1) in zip(beats, beats[1:]):
                if f1 <= f0:
                    raise SystemExit(f"{name}[{index}] frames out of order at {f1}")
                speed = abs(d1 - d0) / (f1 - f0)
                if speed < MIN_LICK_SPEED:
                    raise SystemExit(
                        f"{name}[{index}] stalls between frames {f0} and {f1}: "
                        f"{speed:.2f} raw units/frame, minimum {MIN_LICK_SPEED}"
                    )

# Vertex ids in `scene.rml`, indexed like the point lists. Like `BAND_TOP` these are numbers
# that have to agree with the scene; unlike `BAND_TOP` a wrong one is caught, because
# `rive . --verify` rejects a `KeyedObject` pointing at nothing.
OUTER_IDS = (
    "0:286", "0:287", "0:288", "0:289", "0:290",
    "0:291", "0:292", "0:293", "0:299", "0:300",
)
INNER_IDS = (
    "0:272", "0:273", "0:274", "0:275",
    "0:276", "0:277", "0:278", "0:279",
)

# Property keys, per `rive schema StraightVertex` / `rive schema CubicDetachedVertex`.
VERTEX_Y = 25
TANGENT_KEYS = (("inRotation", 84), ("inDistance", 85), ("outRotation", 86), ("outDistance", 87))


def _keyframes(
    indent: str, key: int, beats: Sequence[tuple[int, float]], *, snap: bool
) -> list[str]:
    """One `KeyedProperty`. `snap` picks `linear` over the eased curve; see `TIP_LICK`."""
    out = [f'{indent}    <KeyedProperty propertyKey="{key}">']
    for i, (frame, value) in enumerate(beats):
        last = i == len(beats) - 1
        kind = "" if last else ' interpolationType="linear"' if snap else ""
        out.append(f'{indent}        <KeyFrameDouble frame="{frame}" value="{value:g}"{kind}/>')
    out.append(f"{indent}    </KeyedProperty>")
    return out


def _lick_one(
    indent: str,
    raw: Sequence[tuple[float, float]],
    place: Callable[[Sequence[tuple[float, float]]], list[tuple[float, float]]],
    corners: frozenset[int],
    ids: Sequence[str],
    table: Mapping[int, Sequence[tuple[int, float]]],
) -> list[str]:
    """One path's tip keys, plus the re-fitted handles of every vertex they drag.

    `place` is the path's own raw-to-artboard transform -- `scaled` for the body, `scaled` of
    `core` for the core -- so a `dy` in raw units lands wherever that path's pipeline puts it
    without this function knowing anything about `CORE_SHRINK`.
    """
    n = len(raw)
    out: list[str] = []

    for index, beats in table.items():
        values = []
        for frame, dy in beats:
            moved = list(raw)
            moved[index] = (moved[index][0], moved[index][1] + dy)
            values.append((frame, place(moved)[index][1]))
        out.append(f'{indent}<KeyedObject objectId="{ids[index]}">')
        out += _keyframes(indent, VERTEX_Y, values, snap=True)
        out.append(f"{indent}</KeyedObject>")

    # Every cubic vertex adjacent to a moved one. Index 0 and anything in `corners` is a
    # `StraightVertex` with no handles to fit, so those drop out on their own -- which is why
    # the body contributes two blocks (index 9 being a corner) and the core two.
    for index, beats in table.items():
        for j in ((index - 1) % n, (index + 1) % n):
            if j == 0 or j in corners:
                continue
            fits = []
            for frame, dy in beats:
                moved = list(raw)
                moved[index] = (moved[index][0], moved[index][1] + dy)
                fits.append((frame, tangent(place(moved), j)))
            out.append(f'{indent}<KeyedObject objectId="{ids[j]}">')
            for slot, (name, key) in enumerate(TANGENT_KEYS):
                out.append(f"{indent}    <!-- {name} -->")
                out += _keyframes(
                    indent, key, [(f, v[slot]) for f, v in fits], snap=True
                )
            out.append(f"{indent}</KeyedObject>")
    return out


def lick(indent: str = " " * 12) -> str:
    """The `Idle` keyframes for both flames' tips, and for the tangents they drag.

    Two kinds of block come out of here. The tips themselves are one `Vertex::y` per moved
    vertex. The rest are the **neighbouring** vertices' cubic handles, re-fitted at every
    keyframe -- because a Catmull-Rom tangent at `i` is computed from `i-1` and `i+1`, so
    moving a tip silently invalidates the fit of the point beneath it.

    Left unfitted, a tip *sharpened* as it rose: the apex climbed past stationary neighbours
    and the curve into it narrowed into a spike on every cycle, which quietly undoes the
    rounded tip a reader picked over the pointed one. The fix is not to shorten the lick but
    to let the fitter do at every keyframe what it already does once.
    """
    out = [f"{indent}<!-- the body's tips -->"]
    _check_lick()
    out += _lick_one(indent, FLAME_OUTER, scaled, CORNERS, OUTER_IDS, TIP_LICK)
    out.append(f"{indent}<!-- the core's tip -->")
    out += _lick_one(
        indent,
        FLAME_INNER,
        lambda p: scaled(core(p)),
        frozenset(),
        INNER_IDS,
        CORE_LICK,
    )
    return "\n".join(out)


def main() -> int:
    for name, points, corners, radii in (
        ("flame_outer", scaled(FLAME_OUTER), CORNERS, RADII),
        ("flame_inner", scaled(core(FLAME_INNER)), frozenset(), CORE_RADII),
    ):
        top = min(y for _, y in points)
        bottom = max(y for _, y in points)
        print(f"<!-- {name}: gradient startY={top:g} endY={bottom:g} -->")
        print(emit(points, corners=corners, radii=radii))
        print()
    print("<!-- leaf striations -->")
    print(striations("ls", flipped=True))
    print()
    print("<!-- base striations -->")
    print(striations("bs", flipped=False))
    print()
    print("<!-- Idle: the tips' lick -->")
    print(lick())
    return 0


if __name__ == "__main__":
    sys.exit(main())
