#!/usr/bin/env python3
"""Measure a widget out of a device screenshot, in points, against what it was drawn to be.

    python3 scripts/measure_widget_shot.py SHOT.png --seed X Y [--scale 3]

Exists because "the simulator looks different from the spec" is not a diagnosis, and the
two defects that produced it are both invisible to the review page: the page draws the
14pt inset directly, so it cannot see iOS adding content margins of its own, and it crops
the cat with `overflow: hidden`, so it cannot see the cut-out being handed a box smaller
than the tile. Both show up immediately as numbers.

Reports, for the recorded tile (cream ground, amber flame, grey cat):

    tile          the ground's own bounding box -- the widget's real size
    content       the flame's top-left, which is the content inset iOS actually applied
    cat           the cut-out's box, and whether its bottom reaches the tile's

`--seed` is any pixel on the tile's own ground, with the tile's edges then walked out from
it rather than assumed -- so the only thing that has to be right by hand is "this point is
inside the widget".
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib


def decode(path: str) -> tuple[int, int, bytearray]:
    """8-bit RGB/RGBA PNG to (width, height, rows) with no dependencies."""
    raw = open(path, "rb").read()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n", f"{path} is not a PNG"
    header = None
    idat = b""
    i = 8
    while i < len(raw):
        (length,) = struct.unpack(">I", raw[i : i + 4])
        kind = raw[i + 4 : i + 8]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", raw[i + 8 : i + 8 + length])
        elif kind == b"IDAT":
            idat += raw[i + 8 : i + 8 + length]
        i += 8 + length + 4
    assert header, "no IHDR"
    width, height, depth, colour, _, _, interlace = header
    assert depth == 8 and interlace == 0, f"unsupported PNG {header}"
    channels = {2: 3, 6: 4}.get(colour)
    assert channels, f"unsupported colour type {colour}"

    data = zlib.decompress(idat)
    stride = width * channels
    out = bytearray(width * height * 3)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        filt = data[pos]
        pos += 1
        line = bytearray(data[pos : pos + stride])
        pos += stride
        if filt == 1:
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 0xFF
        elif filt == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 0xFF
        elif filt == 3:
            for x in range(stride):
                left = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 0xFF
        elif filt == 4:
            for x in range(stride):
                a = line[x - channels] if x >= channels else 0
                b = prev[x]
                c = prev[x - channels] if x >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[x] = (line[x] + pred) & 0xFF
        elif filt != 0:
            raise AssertionError(f"bad filter {filt}")
        prev = line
        for x in range(width):
            src = x * channels
            dst = (y * width + x) * 3
            out[dst : dst + 3] = line[src : src + 3]
    return width, height, out


# The recorded ground is #FFFDF8 at the top to #FFE8C4 at the bottom: white-hot and warm,
# never neutral, and *never* as dull as a wallpaper. A single global threshold turned out
# not to separate the two -- this device's default wallpaper is a beige silk that reaches
# (213, 201, 190), which any test loose enough to admit the ground's warm bottom stop
# (255, 232, 196) also admits. So the tile is found by walking out from a seed instead, and
# this test only has to hold *along that walk*: `r` is the channel where the two part
# company, because the ground is pinned at 255 across the whole gradient and the wallpaper
# never gets there.
def is_ground(r: int, g: int, b: int) -> bool:
    return r >= 244 and g >= 200 and b >= 150 and r >= g >= b


def tile_box(pixels: bytearray, width: int, height: int, seed: tuple[int, int]):
    """The tile's edges, walked out from a point inside it.

    **The extreme over every scan line, not one probe line**, and both reasons a single
    line fails are worth keeping. A row or column near an edge is cut short by the tile's
    22pt corner radius, which is how a 170pt tile first measured 151pt wide and 14pt tall.
    And a line through the middle runs into the tile's own content -- the cat stops a
    downward walk, the flame stops an upward one. Taking the longest run found on any line
    is immune to both: the corners only shorten lines near the edges, and an obstruction
    only shortens the lines it sits on.
    """
    sx, sy = seed

    def at(x: int, y: int) -> bool:
        i = (y * width + x) * 3
        return is_ground(pixels[i], pixels[i + 1], pixels[i + 2])

    if not at(sx, sy):
        sys.exit(f"--seed {sx},{sy} is not on the tile's ground")

    def run(fixed: int, start: int, limit: int, horizontal: bool):
        """The contiguous ground run through `start`, as (low, high_exclusive)."""
        lo = start
        while lo > 0 and at(lo - 1 if horizontal else fixed, fixed if horizontal else lo - 1):
            lo -= 1
        hi = start
        while hi + 1 < limit and at(hi + 1 if horizontal else fixed, fixed if horizontal else hi + 1):
            hi += 1
        return lo, hi + 1

    x0, x1 = run(sy, sx, width, horizontal=True)
    y0, y1 = run(x0 + (x1 - x0) // 2, sy, height, horizontal=False)
    # Two refinement passes: the first row gave a span narrowed by the corners, which then
    # gave a column span, which now admits rows nearer the tile's vertical middle -- where
    # the corners take nothing. Converges immediately at these sizes.
    for _ in range(2):
        for y in range(y0, y1):
            if at(sx, y):
                lo, hi = run(y, sx, width, horizontal=True)
                x0, x1 = min(x0, lo), max(x1, hi)
        for x in range(x0, x1):
            if at(x, sy):
                lo, hi = run(x, sy, height, horizontal=False)
                y0, y1 = min(y0, lo), max(y1, hi)
    return x0, y0, x1, y1


# `Palette.flame` #F2A93F, plus the sticker ring's copies of it.
def is_amber(r: int, g: int, b: int) -> bool:
    return 205 <= r <= 255 and 135 <= g <= 200 and 30 <= b <= 120 and r > g > b


# The cat is a cool mid grey with a white belly. Only the grey is matched: the belly is
# within a few points of the ground and cannot be told from it in a screenshot.
#
# **Near-neutral, within 8 -- not within 26.** The looser test reported the cut-out as 100%
# of the tile, because the tile's bounding *rectangle* includes its four rounded corners,
# and a corner is a blend from cream to a dark wallpaper that passes straight through
# plausible greys like (170, 160, 150). The cut-out's own grey is flatter than any blend:
# (208, 208, 208) measured, i.e. neutral to within 2.
def is_cat_grey(r: int, g: int, b: int) -> bool:
    return max(r, g, b) - min(r, g, b) <= 8 and 110 <= (r + g + b) / 3 <= 215


def bbox(pixels: bytearray, width: int, rect, test):
    x0, y0, w, h = rect
    minx, miny, maxx, maxy = 10**9, 10**9, -1, -1
    count = 0
    for y in range(y0, y0 + h):
        row = y * width
        for x in range(x0, x0 + w):
            i = (row + x) * 3
            if test(pixels[i], pixels[i + 1], pixels[i + 2]):
                count += 1
                minx, miny = min(minx, x), min(miny, y)
                maxx, maxy = max(maxx, x), max(maxy, y)
    if maxx < 0:
        return None
    return minx, miny, maxx + 1, maxy + 1, count


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("shot")
    ap.add_argument(
        "--seed",
        nargs=2,
        type=int,
        required=True,
        metavar=("X", "Y"),
        help="any pixel on the tile's ground, above the cat -- its top strip is ideal",
    )
    ap.add_argument("--scale", type=float, default=3.0, help="screen scale; 3 for a Pro")
    args = ap.parse_args()

    width, height, pixels = decode(args.shot)
    tx0, ty0, tx1, ty1 = tile_box(pixels, width, height, tuple(args.seed))
    s = args.scale

    def pt(v: float) -> str:
        return f"{v / s:.1f}pt"

    print(f"tile      {tx1 - tx0}x{ty1 - ty0}px  =  {pt(tx1 - tx0)} x {pt(ty1 - ty0)}")
    print(f"          box {tx0},{ty0}..{tx1},{ty1}px  (sips -c {ty1 - ty0} {tx1 - tx0} --cropOffset {ty0} {tx0})")

    inner = (tx0, ty0, tx1 - tx0, ty1 - ty0)
    flame = bbox(pixels, width, inner, is_amber)
    if flame:
        fx0, fy0, fx1, fy1, _ = flame
        left, top = (fx0 - tx0) / s, (fy0 - ty0) / s
        verdict = (
            "as drawn"
            if max(left, top) < 20
            else "iOS is adding content margins on top of the tile's own padding"
        )
        print(
            f"flame     inset left {left:.1f}pt, top {top:.1f}pt"
            f"   (the tile asks for 14.0pt -- {verdict})"
        )
        print(f"          box {pt(fx1 - fx0)} x {pt(fy1 - fy0)}")

    cat = bbox(pixels, width, inner, is_cat_grey)
    if cat:
        cx0, cy0, cx1, cy1, count = cat
        tall = (cy1 - cy0) / (ty1 - ty0)
        gap = ty1 - cy1
        print(
            f"cat       {pt(cx1 - cx0)} x {pt(cy1 - cy0)}"
            f"   {tall:.0%} of the tile's height ({count} px of grey)"
        )
        print(
            f"          bottom gap {pt(gap)}"
            + (
                "  -- CROPPED, which is the design"
                if gap / s <= 1.5
                else "  -- NOT cropped: the cut-out is in a box smaller than the tile"
            )
        )
        # **How much of the cut-out's last row is actually grey**, which is the difference
        # between a crop that reads as one and a crop nobody can see. A tail crossing the
        # bottom edge satisfies every measurement above while the cat's body still floats
        # clear of it, and that is exactly the complaint "the cat is not cropped" describes.
        for label, y in (("last row", cy1 - 1), ("8pt up", cy1 - 1 - int(8 * s))):
            if y < cy0:
                continue
            row = bbox(pixels, width, (tx0, y, tx1 - tx0, 1), is_cat_grey)
            if row:
                rx0, _, rx1, _, _ = row
                print(
                    f"          {label:<9} grey spans {pt(rx1 - rx0)}"
                    f" = {(rx1 - rx0) / (cx1 - cx0):.0%} of the cut-out's width"
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
