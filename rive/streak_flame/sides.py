#!/usr/bin/env python3
"""Side curvature: how angular the flame's left and right runs read, as one contact sheet.

    ../../.venv/bin/python rive/streak_flame/sides.py

**Why this exists.** A reader's verdict on the widened flame was "looks too fat .. maybe bc the
left and right sides are too angled? maybe we could round the sides a bit". The diagnosis in
that sentence is the correct one, and the obvious reading of it -- a fat shape needs narrowing
-- is wrong and would have undone the widening that had just been asked for. So this varies only
the *side* vertices, leaves the apex, the notch, the foot and the height alone, and prints the
numbers that say whether a candidate is actually rounder rather than merely narrower.

**Why the sides read as angled.** The widest vertex (index 2 on the right, 6 on the left) is
where the outline stops going out and starts coming in, and its Catmull-Rom tangent is taken
from its two neighbours -- at bow 3 those were (30,-70) and (19,2), a chord that is almost
vertical. So the curve passed the widest point going straight down and the run above it was a
nearly straight 20-degree diagonal off the apex. Out at 20 degrees, then down, then in at the
foot: three directions, which is what an eye reads as planes rather than as a curve. Bowing the
upper side vertex outward spreads that turn over the whole run.

**Anisotropic scale is why the problem appeared at all**, and it is the thing to remember.
`SCALE_X` is 2.39 against `SCALE_Y`'s 1.8, and stretching one axis does not preserve a tangent's
angle -- it flattens every slope toward the horizontal. The same point list read fine at
1.8/1.8. So a silhouette has to be re-judged after the aspect changes, and judged *through* the
scale: this renders via `icon.py`'s fit for exactly that reason, not via the raw point list.

**The vertex count is fixed at ten and must stay there.** `Idle`'s lick keyframes address
vertices by id (`0:286`, `0:287`, `0:293`, `0:299`, and the core's), and `paste.py` matches ids
to emitted lines positionally. Inserting a point to buy smoother sides would re-key the
animation onto the wrong vertices, and nothing would report it.

**What the sheet settled and what it left.** A reader picked **bow 6**, the mildest of the four
changes offered, and it ships. Bow 12 pushes max width from 0.814 to 0.834 and starts swallowing
the notch, so the bow has a ceiling well under that. And the last cell is the lever for "fat"
specifically rather than for "angled": lifting the widest pair moves the mass up the shape and
narrows the foot as a proportion without touching max width. It was offered and not taken; it is
where to start if the complaint returns.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

import icon
import smooth

BODY = (0xF2, 0xA9, 0x3F)
CORE = (0xFF, 0xD4, 0x79)
GROUND = (0xFF, 0xFF, 0xFF)
RULE = (0xD0, 0xD0, 0xD0)
INK = (0x40, 0x40, 0x40)
BAD = (0xD0, 0x30, 0x30)

CELL = 300
PAD = 18
LABEL = 34

# Index map for `FLAME_OUTER`:
#   0 apex  1 right-upper  2 right-widest  3 right-foot  4 foot-centre
#   5 left-foot  6 left-widest  7 left-upper  8 notch tip  9 notch valley
SHIPPED = list(smooth.FLAME_OUTER)


def swap(**kw):
    out = list(SHIPPED)
    for k, v in kw.items():
        out[int(k[1:])] = v
    return out


# The bow is how far vertex 1 sits outside the straight chord from the apex to the widest point,
# in the point list's own units: that chord passes through x=26.7 at y=-70, so x=30 is a bow of
# 3 and x=33 is a bow of 6.
CANDIDATES = [
    ("A bow 3 (retired)", swap(i1=(30, -70), i7=(-25, -74))),
    ("B bow 6 (ships)", SHIPPED),
    ("C bow 9", swap(i1=(36, -74), i7=(-31, -78))),
    ("D bow 12", swap(i1=(39, -76), i7=(-34, -80))),
    ("E bow 9 + shoulder", swap(i1=(36, -76), i2=(40, -40), i6=(-37, -44), i7=(-31, -80))),
]


def fitted(outer):
    body = icon.path(smooth.scaled(outer), smooth.CORNERS, dict(smooth.RADII))
    core = icon.path(
        smooth.scaled(smooth.core(smooth.FLAME_INNER)),
        frozenset(),
        dict(smooth.CORE_RADII),
    )
    x0, y0, x1, y1 = icon.bounds(body)
    w, h = x1 - x0, y1 - y0
    k = 1.0 / max(w, h)
    ox = (1.0 - w * k) / 2 - x0 * k
    oy = (1.0 - h * k) / 2 - y0 * k

    def poly(s):
        return [(x * k + ox, y * k + oy) for x, y in icon.flatten(s)]

    return poly(body), poly(core), w / h


def inside(poly, pt) -> bool:
    """Ray cast. The core must be entirely within the body or the mark has a bite in it."""
    x, y = pt
    hit = False
    n = len(poly)
    for i in range(n):
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < x1 + (y - y1) / (y2 - y1) * (x2 - x1):
            hit = not hit
    return hit


def profile(poly):
    """`(max width, where it sits as a fraction up, how round the upper right side is)`.

    The last one is the largest distance from the sampled outline to the straight chord between
    the apex and the widest point, as a fraction of that chord -- so 0 is a plank and bigger is
    rounder. It is the number the complaint was about, and the one to compare across cells.
    """
    ys = [y for _, y in poly]
    lo, hi = min(ys), max(ys)
    band = (hi - lo) / 40
    best, best_y = 0.0, hi
    for i in range(40):
        y = lo + (i + 0.5) * (hi - lo) / 40
        xs = [x for x, yy in poly if abs(yy - y) <= band]
        if len(xs) > 1 and max(xs) - min(xs) > best:
            best, best_y = max(xs) - min(xs), y

    right = [(x, y) for x, y in poly if y <= best_y and x > 0.5]
    if len(right) < 3:
        return best, (hi - best_y) / (hi - lo), 0.0
    a = min(right, key=lambda p: p[1])
    b = max(right, key=lambda p: p[1])
    dx, dy = b[0] - a[0], b[1] - a[1]
    span = (dx * dx + dy * dy) ** 0.5 or 1.0
    bulge = max(((x - a[0]) * dy - (y - a[1]) * dx) / span for x, y in right)
    return best, (hi - best_y) / (hi - lo), bulge / span


def main() -> int:
    cells = []
    for label, outer in CANDIDATES:
        body, core, aspect = fitted(outer)
        mw, at, bulge = profile(body)
        ok = all(inside(body, p) for p in core)
        print(
            f"  {label:22} aspect 1:{1 / aspect:.3f}  max width {mw:.3f}  "
            f"widest at {at * 100:.0f}% up  side bulge {bulge * 100:4.1f}%  "
            f"core {'inside' if ok else 'OUTSIDE THE BODY'}"
        )
        cells.append((label, body, core, ok))

    out = Image.new(
        "RGB", (PAD + len(cells) * (CELL + PAD), PAD + CELL + LABEL), GROUND
    )
    draw = ImageDraw.Draw(out)
    span = CELL - 2 * PAD
    for i, (label, body, core, ok) in enumerate(cells):
        ox = PAD + i * (CELL + PAD)
        draw.rectangle([ox, PAD, ox + CELL, PAD + CELL], outline=RULE)
        for poly, colour in ((body, BODY), (core, CORE)):
            draw.polygon(
                [(ox + PAD + x * span, PAD + PAD + y * span) for x, y in poly],
                fill=colour,
            )
        draw.text((ox + 4, PAD + CELL + 6), label, fill=INK if ok else BAD)
    dest = Path(smooth.__file__).parent / "build" / "sides.png"
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    print(f"\nwrote {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
