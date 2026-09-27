#!/usr/bin/env python3
"""Draw the splat and stamp mask stencils for the streaks mockup.

The first cut of `patch-splat` and `patch-stamp` was CSS primitives — a
border-radius blob with box-shadow beads, and a plain border ring — and the
review said what one look said: primitives cannot hold an irregular
silhouette, so the splat read as a pebble and the stamp as a <circle>.

This generator draws the two objects properly, as SVG paths:

  - splat: a polar blob with narrow tendril spikes and a few radial
    satellite droplets, smoothed Catmull-Rom -> cubic Bezier;
  - stamp: a band between two noisy ellipse radii with pressure nicks
    (windows where the band thins to nearly nothing) and ink speckles,
    fill-rule evenodd.

Everything is seeded, so like the patch tilt the shapes are stable across
runs and a screenshot can be compared with the last one. Output is a JS
block to paste into index.html (mask data-URIs; the mark is tinted by its
own background colour, which is the empty-state stencils' logic at mark
size) and a proof sheet at _marks_proof.html — look at it; a passing
verifier is not a look.

    python3 docs/mockups/streaks/gen_patch_marks.py
"""

import base64
import importlib
import io
import math
import random
from pathlib import Path
from urllib.parse import quote

HERE = Path(__file__).parent

# The Card's own blind-embossing die — `kCardSealMarkAsset` in
# card_furniture.dart. The mockup cannot reference the file directly:
# Chromium fetches mask-image with CORS semantics, and a file:// page is an
# opaque origin, so a cross-file mask silently paints nothing (the frame
# rendered BLANK; a look caught it, the harness could not). So the die is
# embedded — downscaled to 96px, which is 2× the drawn size — and it is
# still the one shipped asset, read at generation time, never redrawn.
BRAND_DIE = HERE / "../../../assets/branding/app_icon_mark.png"


def brand_uri():
    # Imported by name, and lazily, for two reasons: only this one die needs Pillow, and
    # Pillow lives in the repo's venv rather than the default interpreter — so run this
    # as `../../.venv/bin/python docs/mockups/streaks/gen_patch_marks.py` when
    # regenerating the brand die. The other four dies are pure arithmetic and need
    # nothing.
    try:
        image = importlib.import_module("PIL.Image")
    except ModuleNotFoundError:  # pragma: no cover - environment, not logic
        raise SystemExit(
            "Pillow is needed to embed the Card's seal. Run this with the repo venv:\n"
            "    ../../.venv/bin/python docs/mockups/streaks/gen_patch_marks.py"
        ) from None

    m = image.open(BRAND_DIE)
    small = m.resize((96, 96), image.LANCZOS)
    buf = io.BytesIO()
    small.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def catmull_path(pts):
    """Closed smooth path through pts via Catmull-Rom -> cubic Bezier."""
    n = len(pts)
    d = [f"M{pts[0][0]:.1f},{pts[0][1]:.1f}"]
    for i in range(n):
        p0 = pts[(i - 1) % n]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        d.append(
            f"C{c1[0]:.1f},{c1[1]:.1f} {c2[0]:.1f},{c2[1]:.1f} "
            f"{p2[0]:.1f},{p2[1]:.1f}"
        )
    return "".join(d) + "Z"


def splat(seed):
    """One splat: blob body + tendrils + flung droplets."""
    rng = random.Random(seed)
    cx, cy, base = 20.0, 20.0, 11.5
    n = 18
    tendrils = sorted(rng.sample(range(n), 3))
    pts = []
    for i in range(n):
        a = (i / n) * 2 * math.pi + rng.uniform(-0.06, 0.06)
        r = base * rng.uniform(0.78, 1.12)
        if i in tendrils:
            r = base * rng.uniform(1.45, 1.75)
        elif (i - 1) % n in tendrils or (i + 1) % n in tendrils:
            r = base * rng.uniform(0.72, 0.85)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a) * 0.92))
    body = catmull_path(pts)
    drops = []
    for _ in range(rng.randint(3, 4)):
        a = rng.uniform(0, 2 * math.pi)
        dist = base * rng.uniform(1.45, 1.75)
        x = cx + dist * math.cos(a)
        y = cy + dist * math.sin(a) * 0.9
        rr = rng.uniform(0.7, 1.6)
        # droplets elongate along their flight line
        drops.append(
            f"<ellipse cx='{x:.1f}' cy='{y:.1f}' rx='{rr * 1.35:.1f}' "
            f"ry='{rr:.1f}' transform='rotate({math.degrees(a):.0f} "
            f"{x:.1f} {y:.1f})'/>"
        )
    return (
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40' "
        f"fill='black'><path d='{body}'/>{''.join(drops)}</svg>"
    )


def stamp(seed, rx=16.8, ry_ratio=0.9):
    """One stamp ring: noisy band, pressure nicks, ink speckles.

    `rx`/`ry_ratio` shape the die: the default is the round date stamp,
    an `rx` up with `ry_ratio` down is the oval band a real due-date
    stamp usually is."""
    rng = random.Random(seed)
    cx, cy = 20.0, 20.0
    n = 72
    nicks = [rng.uniform(0, 2 * math.pi) for _ in range(rng.randint(2, 3))]
    outer, inner = [], []
    # low-frequency wobble so the ring is hand-eccentric, not noisy-per-point
    ph1, ph2 = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
    for i in range(n):
        a = (i / n) * 2 * math.pi
        wob = 0.8 * math.sin(2 * a + ph1) + 0.5 * math.sin(3 * a + ph2)
        ro = rx + wob + rng.uniform(-0.25, 0.25)
        w = 2.1 + 0.7 * math.sin(4 * a + ph2) + rng.uniform(-0.2, 0.2)
        for nk in nicks:
            gap = abs((a - nk + math.pi) % (2 * math.pi) - math.pi)
            if gap < 0.16:
                w *= max(0.08, gap / 0.16)  # pressure failed here
        ri = ro - max(0.15, w)
        outer.append((cx + ro * math.cos(a), cy + ro * math.sin(a) * ry_ratio))
        inner.append((cx + ri * math.cos(a), cy + ri * math.sin(a) * ry_ratio))
    ring = catmull_path(outer) + catmull_path(list(reversed(inner)))
    dots = []
    for _ in range(6):
        a = rng.uniform(0, 2 * math.pi)
        dist = rng.uniform(rx * 0.78, rx * 1.15)
        dots.append(
            f"<circle cx='{cx + dist * math.cos(a):.1f}' "
            f"cy='{cy + dist * math.sin(a) * ry_ratio:.1f}' "
            f"r='{rng.uniform(0.25, 0.5):.2f}'/>"
        )
    return (
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40' "
        f"fill='black' fill-rule='evenodd'><path d='{ring}'/>"
        f"{''.join(dots)}</svg>"
    )


def band(rng, cx, cy, rx, ry_ratio, width, nicks):
    """One noisy ring band between two radii, as an evenodd path pair.

    Returns `(d, outer, inner)`: the path, and the two point rings it was
    built from. The rings are returned rather than discarded so `coverage()`
    can measure the die that ships from the SAME arithmetic that draws it —
    a second copy of this loop written to measure it is exactly how a
    measurement comes to describe a shape nobody is looking at.
    """
    n = 72
    ph1, ph2 = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
    outer, inner = [], []
    for i in range(n):
        a = (i / n) * 2 * math.pi
        wob = 0.55 * math.sin(2 * a + ph1) + 0.35 * math.sin(3 * a + ph2)
        ro = rx + wob + rng.uniform(-0.2, 0.2)
        w = width + 0.35 * math.sin(4 * a + ph2) + rng.uniform(-0.15, 0.15)
        for nk in nicks:
            gap = abs((a - nk + math.pi) % (2 * math.pi) - math.pi)
            if gap < 0.14:
                w *= max(0.08, gap / 0.14)
        ri = ro - max(0.12, w)
        outer.append((cx + ro * math.cos(a), cy + ro * math.sin(a) * ry_ratio))
        inner.append((cx + ri * math.cos(a), cy + ri * math.sin(a) * ry_ratio))
    d = catmull_path(outer) + catmull_path(list(reversed(inner)))
    return d, outer, inner


def double(seed, shapes=None):
    """The official seal: two concentric bands sharing their nicks, so
    both fail where the one press failed."""
    rng = random.Random(seed)
    cx, cy = 20.0, 20.0
    nicks = [rng.uniform(0, 2 * math.pi) for _ in range(2)]
    d1, o1, i1 = band(rng, cx, cy, 17.6, 0.9, 1.5, nicks)
    d2, o2, i2 = band(rng, cx, cy, 14.4, 0.9, 0.8, nicks)
    if shapes is not None:
        shapes += [(o1, i1), (o2, i2)]
    return (
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40' "
        f"fill='black' fill-rule='evenodd'><path d='{d1 + d2}'/></svg>"
    )


def disc(seed):
    """The pad pressed solid: an even round mass with a rough edge — the
    patch's area in the stamp's shape. No tendrils; a pad is not a splash."""
    rng = random.Random(seed)
    cx, cy, base = 20.0, 20.0, 16.2
    n = 26
    ph = rng.uniform(0, 6.28)
    pts = []
    for i in range(n):
        a = (i / n) * 2 * math.pi + rng.uniform(-0.04, 0.04)
        r = base * (1 + 0.045 * math.sin(3 * a + ph)) * rng.uniform(0.94, 1.04)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a) * 0.9))
    return (
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40' "
        f"fill='black'><path d='{catmull_path(pts)}'/></svg>"
    )


# ---- the mascot's own paw ----
#
# Measured off `docs/mockups/streak-widget/cats/m01-flex.png` — the cat's raised
# paw — rather than drawn as a generic cat print, for the reason `cp-f-tab`
# gives about the bookmark: a mark the reader already knows carries its meaning
# for free, and a *second* paw drawn beside the mascot's is how one character
# comes to have two paws. Two things a generic print gets wrong here: the
# mascot's paw has THREE toes, not four, and its pad is wider than tall
# (40×31px against a toe's 16×19px), so the print is nearly square rather than
# the tall keyhole a stock paw icon draws.
#
# `cx, cy, rx, ry` in the source PNG's own pixels, so re-measuring is a
# re-measure of the same file rather than a re-derivation of these numbers.
# Caveat worth keeping next to them: that cat is the *provisional* grey, so
# these proportions are borrowed from an undecided asset.
PAW_PAD = (80.6, 287.5, 20.0, 15.5)
PAW_TOES = (
    (67.0, 257.0, 8.0, 9.5),
    (90.9, 254.2, 8.5, 10.0),
    (107.8, 268.6, 7.5, 9.0),
)
# The flat peach the asset fills both pad and toes with, sampled from the PNG.
PAW_PEACH = "#FEBC90"


def paw_toes(sym=False):
    """The toes, either as measured or symmetrised about the paw's own axis.

    **The tidy variants exist because the measured paw looks like it missed the
    cell.** The mascot's third toe sits low and right, so the print has no axis:
    its bounding box centres in the cell while its visible mass does not, and at
    42pt that reads as a mark applied carelessly rather than as a paw. A reader
    asked for a cleaner version and this is the lever.

    Symmetrising is **derived from the measurement, not drawn by hand**: the three
    toes keep their mean radius and mean size, and their angular spread is
    preserved and re-centred on the vertical. So a re-measure of the cat moves the
    tidy paw too, and the tidy paw is still this cat's paw rather than a generic
    one wearing its dimensions.
    """
    px, py = PAW_PAD[0], PAW_PAD[1]
    polar = []
    for cx, cy, rx, ry in PAW_TOES:
        dx, dy = cx - px, cy - py
        polar.append((math.hypot(dx, dy), math.degrees(math.atan2(dx, -dy)), rx, ry))
    if not sym:
        return tuple(PAW_TOES)
    r = sum(p[0] for p in polar) / len(polar)
    rx = sum(p[2] for p in polar) / len(polar)
    ry = sum(p[3] for p in polar) / len(polar)
    spread = max(p[1] for p in polar) - min(p[1] for p in polar)
    half = spread / 2
    out = []
    for a in (-half, 0.0, half):
        t = math.radians(a)
        out.append((px + r * math.sin(t), py - r * math.cos(t), rx, ry))
    return tuple(out)


def paw_parts(
    spread=1.0,
    shrink=1.0,
    pad=True,
    box=36.0,
    top=None,
    lift=0.0,
    sym=False,
    pad_scale=1.0,
):
    """The mascot's paw as `(cx, cy, rx, ry, rot)` blobs in the 40-unit die box.

    `spread` splays the toes away from the pad the way a paw spreads under
    weight. It is applied about the PAD rather than about the print's centroid,
    because that is the joint the toes actually pivot on; spreading about the
    centroid drags the pad upwards and the print stops being a paw.

    **`spread` alone cannot open a hole for the numeral, and that is worth
    knowing before reaching for it.** Splaying grows the print's bounding box by
    very nearly what it grows the gap, and the box is then fitted back to the
    cell — so the two cancel and the measured void moves by a unit. What opens a
    void is `lift`: the pad set back and the toes carried forward, which grows
    the gap along one axis only.

    Each toe's long axis points away from the pad, which is the one piece of
    anatomy the measurement cannot supply — the source gives bounding boxes,
    not rotations — and it is derived rather than typed so a re-measure moves
    it too.
    """
    px, py = PAW_PAD[0], PAW_PAD[1]
    parts = []
    if pad:
        # `pad_scale` grows the pad alone. It exists for one variant: blown up far
        # enough, the pad's OUTLINE is a ring the numeral fits inside, which is the
        # shipped date stamp's own trick with three toes sitting over it. That is
        # the closest this family gets to the mark it is trying to replace.
        parts.append(
            (
                px,
                py + lift,
                PAW_PAD[2] * shrink * pad_scale,
                PAW_PAD[3] * shrink * pad_scale,
                0.0,
            )
        )
    for cx, cy, rx, ry in paw_toes(sym):
        dx, dy = cx - px, cy - py
        rot = math.degrees(math.atan2(dy, dx)) + 90
        parts.append(
            (
                px + dx * spread,
                py + dy * spread - lift * 0.5,
                rx * shrink,
                ry * shrink,
                rot,
            )
        )

    # Fit: the rotated half-extents, so a leaning toe is measured by the room
    # it actually takes rather than by its unrotated box.
    def extent(p):
        _, _, rx, ry, rot = p
        t = math.radians(rot)
        return (
            math.hypot(rx * math.cos(t), ry * math.sin(t)),
            math.hypot(rx * math.sin(t), ry * math.cos(t)),
        )

    xs = [(p[0] - extent(p)[0], p[0] + extent(p)[0]) for p in parts]
    ys = [(p[1] - extent(p)[1], p[1] + extent(p)[1]) for p in parts]
    x0, x1 = min(a for a, _ in xs), max(b for _, b in xs)
    y0, y1 = min(a for a, _ in ys), max(b for _, b in ys)
    s = box / max(x1 - x0, y1 - y0)
    ox = 20.0 - s * (x0 + x1) / 2
    # `top` anchors the group's top edge instead of its centre — what the
    # toes-only die needs, since a canopy centred in the cell sits on the digit.
    oy = (top - s * y0) if top is not None else 20.0 - s * (y0 + y1) / 2
    return [
        (ox + s * cx, oy + s * cy, s * rx, s * ry, rot)
        for cx, cy, rx, ry, rot in parts
    ]


def blob(rng, cx, cy, rx, ry, rot, amp=0.055, n=22):
    """One pressed bean: an ellipse with low-frequency wobble.

    Same reasoning as the ring's rim. A paw print drawn from four exact
    ellipses is a *diagram* of a paw — the charge `cp-f-stamp-double` levels at
    the `BoxDecoration` circle — so every blob is sampled and smoothed, and the
    wobble is low-frequency rather than per-point so the bean reads as pressed
    by a soft pad rather than as noisy.
    """
    ph1, ph2 = rng.uniform(0, 6.28), rng.uniform(0, 6.28)
    t = math.radians(rot)
    ct, st = math.cos(t), math.sin(t)
    pts = []
    for i in range(n):
        a = (i / n) * 2 * math.pi + rng.uniform(-0.03, 0.03)
        k = (
            1
            + amp * math.sin(2 * a + ph1)
            + 0.6 * amp * math.sin(3 * a + ph2)
            + rng.uniform(-amp * 0.3, amp * 0.3)
        )
        x, y = rx * k * math.cos(a), ry * k * math.sin(a)
        pts.append((cx + x * ct - y * st, cy + x * st + y * ct))
    return pts


def blob_ring(rng, cx, cy, rx, ry, rot, width, amp=0.055, n=22):
    """The same bean as an outline: one wobbled rim and its inset twin.

    The inset is proportional per axis rather than a true normal offset, which
    makes the line breathe — thinner across the bean's waist than at its ends —
    and that is wanted for the same reason `band()` modulates its width: a
    constant-width outline is a drawn stroke, and this is a print.
    """
    outer = blob(rng, cx, cy, rx, ry, rot, amp, n)
    kx, ky = max(0.1, (rx - width) / rx), max(0.1, (ry - width) / ry)
    t = math.radians(rot)
    ct, st = math.cos(t), math.sin(t)
    inner = []
    for x, y in outer:
        # back into the bean's own frame, shrink, and out again
        lx, ly = x - cx, y - cy
        bx, by = lx * ct + ly * st, -lx * st + ly * ct
        bx, by = bx * kx, by * ky
        inner.append((cx + bx * ct - by * st, cy + bx * st + by * ct))
    return outer, inner


def svg_of(paths, shapes=None):
    d = "".join(paths)
    return (
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40' "
        f"fill='black' fill-rule='evenodd'><path d='{d}'/></svg>"
    )


def paw(
    seed,
    spread=1.0,
    shrink=1.0,
    pad=True,
    box=36.0,
    top=None,
    lift=0.0,
    sym=False,
    pad_scale=1.0,
    amp=0.055,
    centre_void=False,
    shapes=None,
):
    """One pressed paw: the pad and three toes, each with its own wobble."""
    rng = random.Random(seed)
    parts = []
    for cx, cy, rx, ry, rot in paw_parts(
        spread, shrink, pad, box, top, lift, sym, pad_scale
    ):
        parts.append((blob(rng, cx, cy, rx, ry, rot, amp), None))
    _maybe_centre_void(parts, centre_void)
    if shapes is not None:
        shapes += parts
    return svg_of([catmull_path(o) for o, _ in parts])


def paw_line(
    seed, width=1.35, amp=0.055, centre_void=False, shapes=None, **kw
):
    """The print as line art: every bean hollow, one press's worth of rim."""
    rng = random.Random(seed)
    parts = []
    for cx, cy, rx, ry, rot in paw_parts(**kw):
        parts.append(blob_ring(rng, cx, cy, rx, ry, rot, width, amp))
    _maybe_centre_void(parts, centre_void)
    if shapes is not None:
        shapes += parts
    paths = []
    for outer, inner in parts:
        paths.append(catmull_path(outer))
        paths.append(catmull_path(list(reversed(inner))))
    return svg_of(paths)


def _maybe_centre_void(parts, enabled):
    """Slide the print so its clear band is centred on the numeral.

    The fit puts the print's BOUNDING BOX in the middle of the cell, which is the
    right rule for a mark the digit sits on and the wrong one for a mark the digit
    sits inside: the gap between the toes and a set-back pad is not in the middle
    of the bounding box, so `paw-open` reported a 13.4-unit void and still inked a
    fifth of the numeral. Aligning the VOID rather than the box is one subtraction
    and it takes that to nearly nothing.

    Clamped to the 40-unit frame, because sliding a print that already fills the
    box would crop a toe off — and a cropped toe looks like a rendering bug rather
    than like a design decision.
    """
    if not enabled:
        return
    top, bottom = void_span(parts)
    if bottom <= top:
        return
    dy = 20 - (top + bottom) / 2
    ys = [y for outer, _ in parts for _, y in outer]
    dy = max(-min(ys), min(dy, 40 - max(ys)))
    _shift(parts, dy)


def _inside(poly, x, y):
    hit = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y) and x < xi + (y - yi) / (yj - yi) * (xj - xi):
            hit = not hit
        j = i
    return hit


def _ink_at(shapes, x, y):
    for outer, inner in shapes:
        if _inside(outer, x, y) and not (inner and _inside(inner, x, y)):
            return True
    return False


def coverage(shapes, n=240):
    """What fraction of the 40-unit box the stencil actually inks.

    The reason this exists rather than an eyeballed alpha: ink is `alpha ×
    coverage`, and the paw is a handful of filled masses where the shipped die
    is two hairlines, so carrying the die's 0.65 across to it would put roughly
    three times the colour in the cell. Sampled rather than integrated because
    the beans overlap and an analytic union of wobbled Catmull-Rom outlines is a
    much bigger job than a grid.
    """
    ink = 0
    for gy in range(n):
        y = (gy + 0.5) * 40 / n
        for gx in range(n):
            x = (gx + 0.5) * 40 / n
            if _ink_at(shapes, x, y):
                ink += 1
    return ink / (n * n)


def void_span(shapes, half=4.2, n=160):
    """Where the tallest clear band across the numeral's column sits, in units.

    Returned as `(top, bottom)`. `void` gives the height of this band; the span is
    what `centre_void` needs, because a tall gap in the wrong place is no use to a
    numeral that is centred in its cell. `paw-open` inked 21% of the digit's box
    while reporting a 13.4-unit void — the void was real and it was 4 units too
    high, which no single-number metric could show.
    """
    best = (0.0, 0.0)
    run_start = None
    for gy in range(n + 1):
        y = (gy + 0.5) * 40 / n
        clear = gy < n and not any(
            _ink_at(shapes, 20 - half + gx * (2 * half / 8), y) for gx in range(9)
        )
        if clear and run_start is None:
            run_start = y
        elif not clear and run_start is not None:
            if y - run_start > best[1] - best[0]:
                best = (run_start, y)
            run_start = None
    return best


def _shift(shapes, dy):
    for i, (outer, inner) in enumerate(shapes):
        shapes[i] = (
            [(x, y + dy) for x, y in outer],
            [(x, y + dy) for x, y in inner] if inner else None,
        )


def digit_soiled(shapes, w=8.4, h=13.2, n=120):
    """How much of the numeral's own box the mark inks, 0 to 1.

    **The metric the reader's own words ask for.** The ring was chosen partly
    because it is “clean and easy to read the stamped dates”, and `void` only
    answers that sideways — it reports the tallest clear band, so a mark that
    leaves a tall gap somewhere and still crosses the digit scores well. This is
    the direct question: of the pixels the digit occupies, what fraction has the
    mark's colour behind them.

    An 11px numeral at weight 800 in a 42.14px cell is about 8.4 x 13.2 units,
    centred. 0.00 is the ring's score and the thing to aim at; the filled print is
    over half.
    """
    hit = 0
    for gy in range(n):
        y = 20 - h / 2 + (gy + 0.5) * h / n
        for gx in range(n):
            x = 20 - w / 2 + (gx + 0.5) * w / n
            if _ink_at(shapes, x, y):
                hit += 1
    return hit / (n * n)


def asymmetry(shapes, n=160):
    """How lopsided the print is about the cell's vertical axis, 0 to 1.

    The other half of “cleaner”. The mascot's paw has no axis — its third toe sits
    low and right — so the bounding box centres in the cell while the visible mass
    does not, and at 42pt that reads as a mark that missed rather than as a paw.
    The measured print scores about a tenth; the symmetrised one is near zero.
    """
    left = right = 0
    for gy in range(n):
        y = (gy + 0.5) * 40 / n
        for gx in range(n):
            x = (gx + 0.5) * 40 / n
            if _ink_at(shapes, x, y):
                if x < 20:
                    left += 1
                else:
                    right += 1
    total = left + right
    return abs(left - right) / total if total else 0.0


def void(shapes, half=4.2, n=160):
    """The tallest clear band across the numeral's own column, in die units.

    **The claim this measures is "the digit sits in a hole rather than on the
    mark", and the first version of it measured something else.** It compared
    the pad's top against `max(cy + ry)` over the toes — which counts the low
    side toe, 14 units off the centre line and nowhere near the digit, and reads
    a leaning bean's major axis as its vertical reach. It reported −3u for a
    print whose real centre gap is 8u, and it would have reported the same
    number however far the pad was set back.

    So: sample the column the numeral actually occupies — `half` is half its
    width, 4.2u for an 11px digit in a 42px cell — and return the tallest run of
    rows with no ink anywhere in it. Under about 12u the digit is on the mark.
    """
    best = run = 0
    for gy in range(n):
        y = (gy + 0.5) * 40 / n
        clear = True
        for gx in range(9):
            x = 20 - half + gx * (2 * half / 8)
            if _ink_at(shapes, x, y):
                clear = False
                break
        run = run + 1 if clear else 0
        best = max(best, run)
    return best * 40 / n


def proof_png(variants, path, cell=42.14, gap=5, scale=3):
    """The contact sheet, with the numeral on it, as a PNG.

    `_marks_proof.html` shows the stencils at 84px and 40px on cream, which is
    the check that each die is a shape. It cannot show the two things the paw
    family turns on — whether an 11px numeral survives on top of a filled mass,
    and what a *run* of paws does — so this draws every die at the calendar's own
    42.14px cell with the digit over it at the real weight, and again as five
    consecutive days. Drawn from the polygons rather than by rasterising the SVG:
    the same points the mask is built from, and no new dependency.

    One row per die: the print alone, the print under a numeral, then the run.
    """
    image = importlib.import_module("PIL.Image")
    draw_mod = importlib.import_module("PIL.ImageDraw")
    font_mod = importlib.import_module("PIL.ImageFont")
    c = cell * scale
    step = (cell + gap) * scale
    pad = 12 * scale
    label_w = 64 * scale
    width = int(label_w + pad + 2 * (c + pad) + 5 * step + pad)
    height = int(pad + len(variants) * (c + pad))
    im = image.new("RGB", (width, height), "#faf6ec")
    dr = draw_mod.Draw(im, "RGBA")
    try:
        bold = font_mod.truetype(
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf", int(11 * scale)
        )
        plain = font_mod.truetype(
            "/System/Library/Fonts/Supplemental/Arial.ttf", int(8 * scale)
        )
    except OSError:  # pragma: no cover - environment, not logic
        bold = plain = font_mod.load_default()

    def press(shapes, ox, oy, colour, alpha, tilt=0.0, dy=0.0, flip=False):
        cx, cy = ox + c / 2, oy + c / 2
        t = math.radians(tilt)
        ct, st = math.cos(t), math.sin(t)

        def place(pts):
            out = []
            for px, py in pts:
                x = (40 - px if flip else px) * c / 40 + ox - cx
                y = py * c / 40 + oy - cy + dy * scale
                out.append((cx + x * ct - y * st, cy + x * st + y * ct))
            return out

        for outer, inner in shapes:
            dr.polygon(place(outer), fill=_rgba(colour, alpha))
            if inner:
                dr.polygon(place(inner), fill="#faf6ec")

    for row, v in enumerate(variants):
        y0 = pad + row * (c + pad)
        dr.text((pad, y0 + c / 2), v["label"], font=plain, fill="#6b6355", anchor="lm")
        x = label_w + pad
        press(v["shapes"](17), x, y0, v["colour"], v["alpha"], v.get("tilt", lambda d: 0)(17))
        x += c + pad
        press(v["shapes"](17), x, y0, v["colour"], v["alpha"], v.get("tilt", lambda d: 0)(17))
        dr.text((x + c / 2, y0 + c / 2), "17", font=bold, fill="#212529", anchor="mm")
        x += c + pad
        for i, d in enumerate((15, 16, 17, 18, 19)):
            ox = x + i * step
            press(
                v["shapes"](d),
                ox,
                y0,
                v["colour"],
                v["alpha"],
                v.get("tilt", lambda d: 0)(d),
                v.get("dy", lambda d: 0)(d),
                v.get("flip", lambda d: False)(d),
            )
            dr.text(
                (ox + c / 2, y0 + c / 2), str(d), font=bold, fill="#212529", anchor="mm"
            )
    im.save(path)


def _rgba(hex_colour, alpha):
    h = hex_colour.lstrip("#")
    return (
        int(h[0:2], 16),
        int(h[2:4], 16),
        int(h[4:6], 16),
        int(round(alpha * 255)),
    )


# The month's paper, its numerals, and the three jackets the record's own fixture
# uses (`LAMP_READING` in index.html). Literals here rather than parsed out of the
# page, but `verify.py` asserts each one still appears there — a jacket colour that
# has moved would otherwise make this whole table describe a month nobody draws.
CAL_PAPER = "#FFFFFF"
CAL_INK = "#212529"
CAL_JACKETS = ("#20242B", "#8C3B2E", "#6B4A7A")


def _lum(rgb):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = (ch(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = _lum(a), _lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def over(colour, alpha, ground):
    c = _rgba(colour, 1)[:3]
    g = _rgba(ground, 1)[:3]
    return tuple(round(alpha * c[i] + (1 - alpha) * g[i]) for i in range(3))


def _shapes(fn, seed):
    """The polygons one press is built from, for the PNG proof."""
    out = []
    fn(seed, out)
    return out


def data_uri(svg):
    # Encode quotes, parens and spaces: the URI is inlined into an unquoted
    # CSS url() inside a style="..." attribute, so none of them may survive.
    return "data:image/svg+xml;utf8," + quote(svg, safe="<>=/,:;#")


SPLAT_SEEDS = [11, 23, 67]
STAMP_SEEDS = [7, 19, 31]
OVAL_SEEDS = [13, 29, 47]
DOUBLE_SEEDS = [5, 17, 37]
DISC_SEEDS = [3, 43, 59]
# Three presses per paw die, indexed by `d % 3` like every other family, so no
# two neighbouring days are the same press and the month is still stable across
# renders. Distinct seed sets per die on purpose: sharing one set would make the
# print and its own outline the same wobble, and the pair is meant to be judged
# as two marks rather than as one mark with the middle removed.
PAW_SEEDS = [2, 53, 71]
PAW_LIFT_SEEDS = [61, 79, 89]
PAW_TOES_SEEDS = [41, 83, 97]
PAW_LINE_SEEDS = [73, 101, 103]
# The tidy family, added after a reader picked the full print and the corner print
# and asked for a cleaner version of both. Own seeds for the same reason as above.
PAW_TIDY_SEEDS = [107, 109, 113]
PAW_OPEN_SEEDS = [127, 131, 137]
PAW_THIN_SEEDS = [139, 149, 151]
PAW_RING_SEEDS = [157, 163, 167]
PAW_CREST_SEEDS = [173, 179, 181]

# What the page presses each stencil at. **This table used to be derived from ink
# parity and that was wrong, so the wrong rule is kept as one frame rather than
# deleted.**
#
# Ink parity — alpha x coverage, matched to the shipped die's — equalises how much
# colour is in the cell, and it is the obvious normalisation when the dies cover
# anything from 13% to 39%. It is also the wrong one, because a mark's contrast
# against the paper is a function of its ALPHA ALONE: spread the same ink over
# three times the area and every pixel of it is three times weaker. Under parity
# the filled paw came out at 0.20, which is **1.4:1 against the card** where the
# shipped die is 3.2-4.9:1 — and the first render of the month had one day's paw
# effectively invisible. Every number in the ink table looked correct.
#
# So the family presses at **the die's own 0.65**, which is contrast parity: the
# paw reads exactly as strongly as the ring it replaces. Two deliberate
# exceptions, both of which have a frame that owns them:
#
#   `paw`        0.20, the weight ink parity prescribed, kept as the refutation.
#   `paw-corner` and `paw-peach` are full strength for their own reasons (a 16px
#                mark can afford the jacket; one ink is the mascot's own peach).
PAW_DIE_ALPHA = 0.65
PAW_ALPHAS = {
    "paw": 0.2,
    "paw-strong": PAW_DIE_ALPHA,
    "paw-lift": PAW_DIE_ALPHA,
    "paw-toes": PAW_DIE_ALPHA,
    "paw-line": PAW_DIE_ALPHA,
    "paw-walk": PAW_DIE_ALPHA,
    # The tidy round. `paw-tidy` is the one member whose numeral still stands on
    # the mark, so it takes the 0.40 midpoint the last round named and left
    # undrawn -- the reader's "cleaner, and easy to read the date" is exactly the
    # constraint that picks a value out of that ramp. The rest leave the digit
    # alone and so can have the die's own alpha.
    "paw-tidy": 0.4,
    "paw-open": PAW_DIE_ALPHA,
    "paw-thin": PAW_DIE_ALPHA,
    "paw-ring": PAW_DIE_ALPHA,
    # The three small marks are full jacket strength: the dot tone's argument,
    # that 13px of a wash is nothing and a small mark can afford the real colour.
    "paw-under": 1.0,
    "paw-beside": 1.0,
    "paw-tracks": 1.0,
    # The (i) group's accent is always full jacket strength too -- same reasoning
    # as the three lane marks: small enough that a wash would read as nothing.
    "paw-crest": 1.0,
}

# The paw family, declared once. Masks, the HTML proof, the PNG proof and the
# ink report all read this table, because a die listed in four places is a die
# that will be four different dies by next week.
PAW_DIES = (
    {
        "name": "paw",
        "js": "PATCH_PAW_MASKS",
        "seeds": PAW_SEEDS,
        "kind": "fill",
        "kw": {},
        "alpha": PAW_ALPHAS["paw"],
        "tint": "#8C3B2E",
    },
    {
        "name": "paw-lift",
        "js": "PATCH_PAW_LIFT_MASKS",
        "seeds": PAW_LIFT_SEEDS,
        "kind": "fill",
        # One knob from `paw`: the pad set back, which is the only lever that
        # opens a void on the numeral's own column. `box` goes 36 -> 39 because
        # the taller print would otherwise be fitted smaller than its sibling
        # and the frame would be comparing two things.
        "kw": {"lift": 11.0, "box": 39.0},
        "alpha": PAW_ALPHAS["paw-lift"],
        "tint": "#8C3B2E",
    },
    {
        "name": "paw-toes",
        "js": "PATCH_PAW_TOES_MASKS",
        "seeds": PAW_TOES_SEEDS,
        "kind": "fill",
        "kw": {"pad": False, "box": 34.0, "top": 2.5},
        "alpha": PAW_ALPHAS["paw-toes"],
        "tint": "#8C3B2E",
    },
    {
        "name": "paw-line",
        "js": "PATCH_PAW_LINE_MASKS",
        "seeds": PAW_LINE_SEEDS,
        "kind": "line",
        "kw": {},
        "alpha": PAW_ALPHAS["paw-line"],
        "tint": "#8C3B2E",
    },
    # ---- the tidy round ----
    #
    # One lever: `sym`, which straightens the toe arc onto the paw's own axis, and
    # a halved wobble. Both are about the same complaint -- the measured print
    # reads as a mark that missed the cell -- and neither invents geometry: the
    # symmetric toes keep the measured mean radius, mean size and angular spread.
    {
        "name": "paw-tidy",
        "js": "PATCH_PAW_TIDY_MASKS",
        "seeds": PAW_TIDY_SEEDS,
        "kind": "fill",
        "kw": {"sym": True, "amp": 0.028, "box": 34.0},
        "alpha": PAW_ALPHAS["paw-tidy"],
        "tint": "#8C3B2E",
    },
    {
        "name": "paw-open",
        "js": "PATCH_PAW_OPEN_MASKS",
        "seeds": PAW_OPEN_SEEDS,
        "kind": "fill",
        "kw": {
            "sym": True,
            "amp": 0.028,
            "lift": 16.0,
            "box": 36.0,
            "centre_void": True,
        },
        "alpha": PAW_ALPHAS["paw-open"],
        "tint": "#8C3B2E",
    },
    {
        "name": "paw-thin",
        "js": "PATCH_PAW_THIN_MASKS",
        "seeds": PAW_THIN_SEEDS,
        "kind": "line",
        # A true hairline: 1.0 unit at a 42pt cell is a hair over 1px. Any thinner
        # and the bean loses its hole, which is the smudge failure the empty-state
        # record already paid for once.
        "kw": {"sym": True, "amp": 0.028, "width": 1.0, "box": 34.0},
        "alpha": PAW_ALPHAS["paw-thin"],
        "tint": "#8C3B2E",
    },
    {
        "name": "paw-ring",
        "js": "PATCH_PAW_RING_MASKS",
        "seeds": PAW_RING_SEEDS,
        "kind": "line",
        "kw": {
            "sym": True,
            "amp": 0.028,
            "width": 1.15,
            "pad_scale": 1.45,
            "box": 36.0,
            "centre_void": True,
        },
        "alpha": PAW_ALPHAS["paw-ring"],
        "tint": "#8C3B2E",
    },
    # ---- the (i) group's accent: toes only, small, for perching on a ring ----
    #
    # Used only as `.cmk2` in `cp-i-stamp-crest`, never as a standalone frame --
    # so it still goes through PAW_DIES/PAW_ALPHAS (the generic report and the
    # generic verify loop cover it for free) but there is no `cp-h-paw-crest`.
    # Tidy from the start (sym=True): a crest sitting on a ring is a badge, and a
    # lopsided badge reads as crooked rather than as hand-pressed.
    {
        "name": "paw-crest",
        "js": "PATCH_PAW_CREST_MASKS",
        "seeds": PAW_CREST_SEEDS,
        "kind": "fill",
        "kw": {"sym": True, "pad": False, "amp": 0.028, "box": 30.0},
        "alpha": PAW_ALPHAS["paw-crest"],
        "tint": "#8C3B2E",
    },
)


def paw_die(die, seed, shapes=None):
    fn = paw_line if die["kind"] == "line" else paw
    kw = dict(die["kw"])
    if die["kind"] == "line":
        # `paw_line` forwards **kw to `paw_parts`, so its own three knobs have to
        # be lifted out of the die's kwargs rather than passed through --
        # otherwise `paw_parts` gets a `width` it has never heard of and the whole
        # family fails to build.
        return fn(
            seed,
            width=kw.pop("width", 1.35),
            amp=kw.pop("amp", 0.055),
            centre_void=kw.pop("centre_void", False),
            shapes=shapes,
            **kw,
        )
    return fn(seed, shapes=shapes, **kw)


if __name__ == "__main__":
    splats = [splat(s) for s in SPLAT_SEEDS]
    stamps = [stamp(s) for s in STAMP_SEEDS]
    ovals = [stamp(s, rx=18.6, ry_ratio=0.68) for s in OVAL_SEEDS]
    doubles = [double(s) for s in DOUBLE_SEEDS]
    discs = [disc(s) for s in DISC_SEEDS]
    # The paw family. Every die is the same measured anatomy; what differs is
    # one number each -- the splay, the set-back, the pad, the fit -- so the
    # frames that draw them compare one knob, the way the rest of this record
    # does.
    paw_svgs = {
        d["name"]: [paw_die(d, s) for s in d["seeds"]] for d in PAW_DIES
    }

    js = []
    for name, group in (
        ("PATCH_SPLAT_MASKS", splats),
        ("PATCH_STAMP_MASKS", stamps),
        ("PATCH_OVAL_MASKS", ovals),
        ("PATCH_DOUBLE_MASKS", doubles),
        ("PATCH_DISC_MASKS", discs),
    ) + tuple((d["js"], paw_svgs[d["name"]]) for d in PAW_DIES):
        js.append(f"const {name} = [")
        js += [f'    "{data_uri(s)}",' for s in group]
        js.append("];")
    js.append(f'const PATCH_BRAND_MASK =\n    "{brand_uri()}";')
    (HERE / "_marks.js").write_text("\n".join(js) + "\n")

    tiles = "".join(
        f"<div class='t'><i style=\"background:{c};-webkit-mask-image:"
        f"url({data_uri(s)});-webkit-mask-size:100% 100%;\"></i>"
        f"<b>{lbl}</b></div>"
        for group, lbl0 in (
            (splats, "splat"),
            (stamps, "stamp"),
            (ovals, "oval"),
            (doubles, "double"),
            (discs, "disc"),
        )
        + tuple((paw_svgs[d["name"]], d["name"]) for d in PAW_DIES)
        for k, s in enumerate(group)
        for c, lbl in [
            ("#26243e", f"{lbl0} {k} dark"),
            ("#a4552f", f"{lbl0} {k} rust"),
        ]
    )
    (HERE / "_marks_proof.html").write_text(
        "<style>body{background:#faf6ec;display:flex;flex-wrap:wrap;"
        "gap:14px;padding:20px;font:11px sans-serif}.t{text-align:center}"
        ".t i{display:block;width:84px;height:84px}"
        ".t.small i{width:40px;height:40px}</style>"
        + tiles
        + tiles.replace("class='t'", "class='t small'")
    )
    print("wrote _marks.js and _marks_proof.html")

    # ---- how much ink each die spends, and whether the digit has a hole ----
    #
    # Printed rather than commented, because the alphas above are chosen off
    # these numbers and "looks about right" is how a mark family ends up three
    # times as loud as the one it replaces. `ink` is alpha x coverage normalised
    # to the shipped die's, so 1.00 means "as much colour in the cell as
    # `stamp-double` puts there today". `void` is the tallest clear band across
    # the numeral's own column: above ~12u the digit sits in a hole, below it the
    # digit sits on the mark and needs the mark to be a wash.
    def measure(fn, seeds):
        covs, voids, soils, asyms = [], [], [], []
        for s in seeds:
            shapes = []
            fn(s, shapes)
            covs.append(coverage(shapes))
            voids.append(void(shapes))
            soils.append(digit_soiled(shapes))
            asyms.append(asymmetry(shapes))
        n = len(seeds)
        return (
            sum(covs) / n,
            sum(voids) / n,
            sum(soils) / n,
            sum(asyms) / n,
        )

    ref = measure(lambda s, sh: double(s, shapes=sh), DOUBLE_SEEDS)
    rows = [("stamp-double (ships)", 0.65) + ref]
    for d in PAW_DIES:
        m = measure(lambda s, sh, d=d: paw_die(d, s, shapes=sh), d["seeds"])
        rows.append((d["name"], d["alpha"]) + m)
        if d["name"] == "paw":
            rows.append(("paw-strong", PAW_ALPHAS["paw-strong"]) + m)
    ref_ink = ref[0] * 0.65
    print("")
    print(
        f"{'die':22s} {'alpha':>6s} {'coverage':>9s} {'ink':>6s} "
        f"{'vs die':>7s} {'void':>7s} {'on digit':>9s} {'lopsided':>9s}"
    )
    for name, a, c, v, soil, asym in rows:
        print(
            f"{name:22s} {a:6.2f} {c * 100:8.1f}% {c * a:6.3f} "
            f"{c * a / ref_ink:6.2f}x {v:6.1f}u {soil * 100:8.1f}% {asym:9.3f}"
        )
    # The three small marks are the same tidy stencil placed by CSS rather than
    # re-drawn, so they have no row of their own here: their whole claim is that
    # the numeral's box is untouched, and a mark that does not overlap the digit
    # scores 0.0% by construction. `shot_paw.py` is where they get judged.

    # ---- and what parity does to CONTRAST, which is the catch ----
    #
    # Ink parity equalises how much colour is in the cell. It does NOT equalise
    # how strongly the mark reads, because a mark's contrast against the paper is
    # a function of its alpha alone -- spread the same ink over three times the
    # area and every pixel of it is three times weaker. This table is here
    # because the first render of the paw family looked correct on every measured
    # number above and had one day's paw effectively INVISIBLE on the page: the
    # quietest jacket at 0.20 lands at 1.4:1 against white, where the shipped die
    # at 0.65 lands near 4:1. Found by looking, then explained by this.
    #
    # `mark` is the mark against the card. `digit` is the numeral on top of the
    # mark, which is the other half of the trade -- the reason a filled print
    # cannot simply be turned up.
    print("")
    print(
        f"{'die':22s} {'alpha':>6s} "
        + " ".join(f"{j:>14s}" for j in CAL_JACKETS)
        + "   (mark:paper / ink:mark)"
    )
    for name, a, _c, _v, _s, _as in rows:
        cells = []
        for j in CAL_JACKETS:
            on = over(j, a, CAL_PAPER)
            cells.append(
                f"{contrast(on, _rgba(CAL_PAPER, 1)[:3]):5.2f}/"
                f"{contrast(_rgba(CAL_INK, 1)[:3], on):5.2f}"
            )
        print(f"{name:22s} {a:6.2f} " + " ".join(f"{c:>14s}" for c in cells))
    peach = over(PAW_PEACH, 1.0, CAL_PAPER)
    print(
        f"{'paw-peach (one ink)':22s} {1.0:6.2f} "
        f"{contrast(peach, _rgba(CAL_PAPER, 1)[:3]):5.2f}/"
        f"{contrast(_rgba(CAL_INK, 1)[:3], peach):5.2f}"
    )

    proof_png(
        [
            {
                "label": "stamp-double",
                "shapes": lambda d: _shapes(lambda s, sh: double(s, shapes=sh), DOUBLE_SEEDS[d % 3]),
                "alpha": 0.65,
                "colour": "#a4552f",
                "tilt": lambda d: ((d * 7) % 9) - 4,
            }
        ]
        + [
            {
                "label": d["name"],
                "shapes": lambda day, d=d: _shapes(
                    lambda s, sh, d=d: paw_die(d, s, shapes=sh), d["seeds"][day % 3]
                ),
                "alpha": d["alpha"],
                "colour": d["tint"],
                "tilt": lambda day: ((day * 7) % 9) - 4,
            }
            for d in PAW_DIES
        ]
        + [
            {
                "label": "paw-strong",
                "shapes": lambda day: _shapes(
                    lambda s, sh: paw(s, shapes=sh), PAW_SEEDS[day % 3]
                ),
                "alpha": PAW_ALPHAS["paw-strong"],
                "colour": "#8C3B2E",
                "tilt": lambda day: ((day * 7) % 9) - 4,
            },
            {
                "label": "paw-walk",
                "shapes": lambda day: _shapes(
                    lambda s, sh: paw(s, shapes=sh), PAW_SEEDS[day % 3]
                ),
                "alpha": PAW_ALPHAS["paw-walk"],
                "colour": "#8C3B2E",
                "tilt": lambda day: ((day * 7) % 9) - 4,
                "dy": lambda day: -4 if day % 2 else 4,
                "flip": lambda day: day % 2 == 0,
            },
            {
                "label": "paw-peach",
                "shapes": lambda day: _shapes(
                    lambda s, sh: paw(s, shapes=sh), PAW_SEEDS[day % 3]
                ),
                "alpha": 1.0,
                "colour": PAW_PEACH,
                "tilt": lambda day: ((day * 7) % 9) - 4,
            },
        ],
        HERE / "_paw_proof.png",
    )
    print("wrote _paw_proof.png -- LOOK at it")
