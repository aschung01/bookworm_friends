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
    """One noisy ring band between two radii, as an evenodd path pair."""
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
    return catmull_path(outer) + catmull_path(list(reversed(inner)))


def double(seed):
    """The official seal: two concentric bands sharing their nicks, so
    both fail where the one press failed."""
    rng = random.Random(seed)
    cx, cy = 20.0, 20.0
    nicks = [rng.uniform(0, 2 * math.pi) for _ in range(2)]
    d = band(rng, cx, cy, 17.6, 0.9, 1.5, nicks) + band(
        rng, cx, cy, 14.4, 0.9, 0.8, nicks
    )
    return (
        "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40' "
        f"fill='black' fill-rule='evenodd'><path d='{d}'/></svg>"
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


def data_uri(svg):
    # Encode quotes, parens and spaces: the URI is inlined into an unquoted
    # CSS url() inside a style="..." attribute, so none of them may survive.
    return "data:image/svg+xml;utf8," + quote(svg, safe="<>=/,:;#")


SPLAT_SEEDS = [11, 23, 67]
STAMP_SEEDS = [7, 19, 31]
OVAL_SEEDS = [13, 29, 47]
DOUBLE_SEEDS = [5, 17, 37]
DISC_SEEDS = [3, 43, 59]

if __name__ == "__main__":
    splats = [splat(s) for s in SPLAT_SEEDS]
    stamps = [stamp(s) for s in STAMP_SEEDS]
    ovals = [stamp(s, rx=18.6, ry_ratio=0.68) for s in OVAL_SEEDS]
    doubles = [double(s) for s in DOUBLE_SEEDS]
    discs = [disc(s) for s in DISC_SEEDS]

    js = []
    for name, group in (
        ("PATCH_SPLAT_MASKS", splats),
        ("PATCH_STAMP_MASKS", stamps),
        ("PATCH_OVAL_MASKS", ovals),
        ("PATCH_DOUBLE_MASKS", doubles),
        ("PATCH_DISC_MASKS", discs),
    ):
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
