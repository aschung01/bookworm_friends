#!/usr/bin/env python3
"""Turn the Rive flame's silhouette into an icon path, in Dart, Swift and SVG.

    ../../.venv/bin/python rive/streak_flame/icon.py           # the Dart tables
    ../../.venv/bin/python rive/streak_flame/icon.py --swift   # the Swift tables
    ../../.venv/bin/python rive/streak_flame/icon.py --svg     # an SVG, for the record
    ../../.venv/bin/python rive/streak_flame/icon.py --sheet   # render it and look

**Why this exists.** The app's flame was `kReadingStreakIcon`, a Phosphor font glyph, in
four places: the streak chip, the streak page's hero, the record button, and the
celebration's fallback. The celebration's *real* flame is this project's artboard. So the
app drew two unrelated flames and called them the same feature -- and the design record had
already flagged exactly that risk, in reverse, as the reason not to add a vector flame
beside the glyph. The resolution is not two flames kept in step by discipline; it is one
silhouette with two renderings, generated from one source.

**Which is why this generates rather than traces.** `smooth.py` owns `FLAME_OUTER`,
`FLAME_INNER`, `CORNERS`, `RADII` and `CORE_RADII`; this imports them. Move a vertex there,
re-run both scripts, and the artboard and the icon move together. A traced copy would be a
second silhouette with a promise attached.

**The one thing that is reimplemented, and how to tell if it drifted.** Rive rounds a
corner from a `StraightVertex`'s `radius` attribute, and the renderer does that internally;
there is no path data to import. So the fillet is computed here -- trim both edges back by
`r / tan(theta/2)` and bridge them with a cubic approximation of the arc. `--sheet` renders
the generated path beside the artboard's own frame so the two can be compared by eye, which
is the only check that means anything: the numbers agreeing proves nothing about a curve.

**The icon keeps the body and the core and drops everything else** -- no book, no glow, no
sparks, no gradients. At 18pt on a button those are invisible at best and mud at worst. Two
shapes is what survives being small, and it is what makes the mark read as *this* flame
rather than as any flame: the notch on the left shoulder and the low fat core are the two
things a reader would recognise.
"""

from __future__ import annotations

import math
import sys

from smooth import (
    CORE_RADII,
    CORNERS,
    FLAME_INNER,
    FLAME_OUTER,
    RADII,
    core,
    scaled,
    tangent,
)

# How close a fillet may come to eating a whole edge. A `radius` larger than the edges it
# sits between is legal in Rive and is clamped by the renderer; without the same clamp here
# a generous radius produces a self-crossing loop instead of a lobe.
MAX_EDGE_SHARE = 0.45

# The box the emitted path is normalised into. 1.0 means the *taller* axis fills it and the
# other is centred, so a consumer can treat one number as the mark's size and get the
# flame's real 1:1.7 aspect inside it without doing arithmetic.
BOX = 1.0


def unit(dx: float, dy: float) -> tuple[float, float]:
    h = math.hypot(dx, dy)
    return (dx / h, dy / h) if h else (0.0, 0.0)


def fillet(
    prev: tuple[float, float],
    v: tuple[float, float],
    nxt: tuple[float, float],
    r: float,
) -> tuple[tuple[float, float], tuple[float, float], float]:
    """Where a rounded corner at `v` starts and ends, and the handle length for its arc.

    Returns `(enter, exit, handle)`. `enter` is where the incoming edge stops, `exit` is
    where the outgoing edge resumes, and `handle` is how far each of the arc's two control
    points sits from its endpoint *along the line toward `v`* -- which is the standard cubic
    approximation of a circular arc and is exact to about one part in a thousand for the
    turns here.
    """
    d1 = unit(prev[0] - v[0], prev[1] - v[1])
    d2 = unit(nxt[0] - v[0], nxt[1] - v[1])
    # The interior angle at `v`, between the two edges leaving it.
    cos = max(-1.0, min(1.0, d1[0] * d2[0] + d1[1] * d2[1]))
    theta = math.acos(cos)
    if theta <= 1e-6 or abs(math.pi - theta) <= 1e-6:
        return (v, v, 0.0)
    t = r / math.tan(theta / 2)
    t = min(
        t,
        MAX_EDGE_SHARE * math.dist(prev, v),
        MAX_EDGE_SHARE * math.dist(nxt, v),
    )
    enter = (v[0] + d1[0] * t, v[1] + d1[1] * t)
    exit_ = (v[0] + d2[0] * t, v[1] + d2[1] * t)
    # The turn the path makes through the corner is the exterior angle.
    turn = math.pi - theta
    handle = (4 / 3) * (t * math.tan(theta / 2)) * math.tan(turn / 4)
    return (enter, exit_, handle)


def path(
    points: list[tuple[float, float]],
    corners: frozenset[int],
    radii: dict[int, float],
) -> tuple[tuple[float, float], list[tuple[float, float, float, float, float, float]]]:
    """The closed outline as a start point plus a list of cubic segments.

    Everything is a cubic, including the straight run into a corner and the arc through it.
    One uniform primitive means the Dart side is a `moveTo` and a loop of `cubicTo`, with no
    branching that could disagree with what was generated.
    """
    n = len(points)
    # Index 0 is always a corner in this family; `smooth.py` says so and relies on it.
    sharp = set(corners) | {0}

    enter: list[tuple[float, float]] = []
    exit_: list[tuple[float, float]] = []
    handle: list[float] = []
    for i, v in enumerate(points):
        if i in sharp and radii.get(i):
            a, b, h = fillet(points[(i - 1) % n], v, points[(i + 1) % n], radii[i])
        else:
            a, b, h = v, v, 0.0
        enter.append(a)
        exit_.append(b)
        handle.append(h)

    segments: list[tuple[float, float, float, float, float, float]] = []

    def out_control(i: int) -> tuple[float, float]:
        """The control point leaving vertex `i`, on the way to `i + 1`."""
        v, e = points[i], exit_[i]
        if i in sharp:
            # Straight: a third of the way to the next vertex's entry, which keeps a
            # straight edge straight whatever the neighbour does.
            t = enter[(i + 1) % n]
            return (e[0] + (t[0] - e[0]) / 3, e[1] + (t[1] - e[1]) / 3)
        _, _, rot, dist = tangent(points, i)
        return (v[0] + math.cos(rot) * dist, v[1] + math.sin(rot) * dist)

    def in_control(i: int) -> tuple[float, float]:
        """The control point arriving at vertex `i`, coming from `i - 1`."""
        v, a = points[i], enter[i]
        if i in sharp:
            t = exit_[(i - 1) % n]
            return (a[0] + (t[0] - a[0]) / 3, a[1] + (t[1] - a[1]) / 3)
        rot, dist, _, _ = tangent(points, i)
        return (v[0] + math.cos(rot) * dist, v[1] + math.sin(rot) * dist)

    for i in range(n):
        j = (i + 1) % n
        c1 = out_control(i)
        c2 = in_control(j)
        segments.append((c1[0], c1[1], c2[0], c2[1], enter[j][0], enter[j][1]))
        # Note the loop closes on itself: the last segment lands on `enter[0]` and the
        # fillet below then arcs to `exit_[0]`, which is where the path started. Starting at
        # `enter[0]` instead leaves the corner at index 0 drawn twice and the outline open
        # across it, which is what the first version of this did.
        if handle[j]:
            # The arc through the corner: both controls lie on the lines back to the
            # original vertex, which is what makes the join tangent-continuous with the
            # straight edges either side of it.
            v = points[j]
            a, b, h = enter[j], exit_[j], handle[j]
            da = unit(v[0] - a[0], v[1] - a[1])
            db = unit(v[0] - b[0], v[1] - b[1])
            segments.append(
                (
                    a[0] + da[0] * h,
                    a[1] + da[1] * h,
                    b[0] + db[0] * h,
                    b[1] + db[1] * h,
                    b[0],
                    b[1],
                )
            )
    return (exit_[0], segments)


def shapes() -> tuple[
    tuple[tuple[float, float], list[tuple[float, ...]]],
    tuple[tuple[float, float], list[tuple[float, ...]]],
]:
    """The body and the core, in the artboard's own units.

    `scaled()` and `core()` are applied in `smooth.py`'s own order, because `RADII` and
    `CORE_RADII` are documented as being in *final* artboard units -- rounding before
    scaling would round by the wrong amount and the tips would come out sharp at 1.8x.
    """
    body = path(scaled(FLAME_OUTER), CORNERS, dict(RADII))
    inner = path(scaled(core(FLAME_INNER)), frozenset(), dict(CORE_RADII))
    return body, inner


def flatten(
    shape: tuple[tuple[float, float], list[tuple[float, ...]]],
    steps: int = 48,
) -> list[tuple[float, float]]:
    """The path as a polygon. Used for measuring and for the proof render."""
    start, segs = shape
    pts = [start]
    cur = start
    for s in segs:
        p0, p1, p2, p3 = cur, (s[0], s[1]), (s[2], s[3]), (s[4], s[5])
        for q in range(1, steps + 1):
            t = q / steps
            u = 1 - t
            pts.append(
                (
                    u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0],
                    u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1],
                )
            )
        cur = p3
    return pts


def bounds(
    shape: tuple[tuple[float, float], list[tuple[float, ...]]],
) -> tuple[float, float, float, float]:
    """The box the curve actually occupies, by sampling it.

    **Not the control hull, which is what this did first and it cost 6% of the mark's size.**
    A cubic stays inside its hull, so the hull is safe and it is also wrong by however far
    the handles stick out past the curve -- here enough to report the flame as 1:1.58 when it
    is 1:1.67, which would have drawn the icon visibly smaller in its box than the glyph it
    replaces. Sampling is a few lines and is right.
    """
    pts = flatten(shape)
    xs = [x for x, _ in pts]
    ys = [y for _, y in pts]
    return (min(xs), min(ys), max(xs), max(ys))


def normalised() -> tuple[
    tuple[tuple[float, float], list[tuple[float, ...]]],
    tuple[tuple[float, float], list[tuple[float, ...]]],
    float,
]:
    """Both shapes fitted into a [0, BOX] square, and the aspect they came out at.

    Fitted against the **body's** box and not the union, so the core's placement inside the
    body is preserved exactly. They are the same box in practice -- the core is entirely
    inside -- but tying the fit to the silhouette says which shape defines the mark.
    """
    body, inner = shapes()
    x0, y0, x1, y1 = bounds(body)
    w, h = x1 - x0, y1 - y0
    k = BOX / max(w, h)
    # Centre the narrow axis, so one number can be the mark's size in both directions.
    ox = (BOX - w * k) / 2 - x0 * k
    oy = (BOX - h * k) / 2 - y0 * k

    def fit(shape):
        start, segs = shape
        return (
            (start[0] * k + ox, start[1] * k + oy),
            [
                tuple(
                    (c * k + ox) if idx % 2 == 0 else (c * k + oy)
                    for idx, c in enumerate(s)
                )
                for s in segs
            ],
        )

    return fit(body), fit(inner), w / h


def dart() -> str:
    body, inner, aspect = normalised()
    out = [
        "// Generated by `rive/streak_flame/icon.py` from the same point lists the Rive",
        "// artboard is built from. Do not hand-edit: edit `rive/streak_flame/smooth.py`",
        f"// and re-run. Aspect (width / height): {aspect:.4f}.",
    ]
    for name, shape in (("_kBody", body), ("_kCore", inner)):
        start, segs = shape
        out.append("")
        out.append(f"const List<double> {name} = <double>[")
        out.append(f"  {start[0]:.5f}, {start[1]:.5f}, // moveTo")
        for s in segs:
            out.append("  " + ", ".join(f"{c:.5f}" for c in s) + ",")
        out.append("];")
    return "\n".join(out)


def swift() -> str:
    """The same two tables as [dart], for the home-screen widget's SwiftUI `Path`.

    **A third rendering of one silhouette, not a third flame.** The widget cannot import
    `StreakFlameMark`, and the alternative -- tracing the SVG into a Swift path by hand, or
    shipping a PDF asset -- is exactly the "two unrelated flames called one feature" defect
    this whole script exists to have ended. Generated from the same `smooth.py` point lists,
    so moving a vertex there moves the artboard, the Dart painter and the widget together.

    Emitted as a flat `[CGFloat]` in the same layout the Dart table uses -- a `moveTo` pair
    followed by six numbers per cubic -- so the two readers are the same code in two
    languages and a reader who knows one can check the other.
    """
    body, inner, aspect = normalised()
    out = [
        "// Generated by `rive/streak_flame/icon.py --swift` from the same point lists the",
        "// Rive artboard and `StreakFlameMark` are built from. Do not hand-edit: edit",
        f"// `rive/streak_flame/smooth.py` and re-run. Aspect (width / height): {aspect:.4f}.",
        "",
        "import CoreGraphics",
        "",
        "enum StreakFlameGeometry {",
        f"  /// Width over height of the silhouette, for boxing the mark.",
        f"  static let aspect: CGFloat = {aspect:.5f}",
    ]
    for name, shape in (("body", body), ("core", inner)):
        start, segs = shape
        out.append("")
        out.append(f"  static let {name}: [CGFloat] = [")
        out.append(f"    {start[0]:.5f}, {start[1]:.5f}, // moveTo")
        for s in segs:
            out.append("    " + ", ".join(f"{c:.5f}" for c in s) + ",")
        out.append("  ]")
    out.append("}")
    return "\n".join(out)


def svg() -> str:
    body, inner, aspect = normalised()

    def d(shape) -> str:
        start, segs = shape
        parts = [f"M{start[0] * 100:.3f} {start[1] * 100:.3f}"]
        for s in segs:
            parts.append(
                "C"
                + " ".join(f"{c * 100:.3f}" for c in s[:2])
                + " "
                + " ".join(f"{c * 100:.3f}" for c in s[2:4])
                + " "
                + " ".join(f"{c * 100:.3f}" for c in s[4:])
            )
        return " ".join(parts) + "Z"

    return (
        f'<!-- aspect {aspect:.4f}; generated by rive/streak_flame/icon.py -->\n'
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" '
        'width="100" height="100">\n'
        f'  <path d="{d(body)}" fill="#F2A93F"/>\n'
        f'  <path d="{d(inner)}" fill="#FFD479"/>\n'
        "</svg>\n"
    )


def sheet() -> int:
    """Rasterise the generated path beside the artboard's own frame, and write both.

    The one check that matters. `--verify`, `inspect` and a table of matching numbers all
    say nothing about whether a curve came out as a flame; this file's whole history is that
    lesson. Writes to `build/flame_icon/`.
    """
    from pathlib import Path

    from PIL import Image, ImageDraw

    from _preview import BUILD, preview_project, shot

    body, inner, _ = normalised()
    size = 480
    pad = 24
    img = Image.new("RGB", (size, size), (0xFF, 0xFF, 0xFF))
    draw = ImageDraw.Draw(img)

    span = size - 2 * pad
    for shape, colour in ((body, (0xF2, 0xA9, 0x3F)), (inner, (0xFF, 0xD4, 0x79))):
        draw.polygon(
            [(pad + x * span, pad + y * span) for x, y in flatten(shape)],
            fill=colour,
        )
    out = Path(BUILD) / "flame_icon"
    out.mkdir(parents=True, exist_ok=True)
    img.save(out / "generated.png")

    # And the artboard's own `Idle`, frame 0, for the side-by-side. `Idle` is reachable only
    # by reordering the timelines -- there is no `--animation` flag -- which is what
    # `first_animation` does; see `_preview.py`.
    project = preview_project(name="icon_proof", first_animation="Idle")
    shot(project, out / "artboard.png", 1)
    print(f"wrote {out}")
    return 0


def main(argv: list[str]) -> int:
    if "--sheet" in argv:
        return sheet()
    if "--swift" in argv:
        print(swift())
        return 0
    print(svg() if "--svg" in argv else dart())
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
