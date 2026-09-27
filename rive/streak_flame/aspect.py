#!/usr/bin/env python3
"""Width: the flame against Duolingo's squatter mark, and against its own book.

**The fork this script was written to hold open is closed, and the record of it is below.**
It used to render three variants -- current, squat, widen -- because there were two
non-equivalent ways to reach a squatter flame and picking one silently would have thrown
away a decision. The instruction that settled it was "a wider shape of similar ratio with
the phosphor icon", so `WIDEN` won and it went further than the 1.15 factor offered here:
`smooth.py`'s `SCALE_X` is now solved so the fitted curve lands on Phosphor Fill `fire`'s own
**0.8148** (704 x 864 in a 1024 em), which is 1:1.23 against the 1:1.61 it was at.

So what is left to measure is the cost `WIDEN` was always going to have, and it is the one
thing a still of the settled flame does not show: **the flame is widest at the burst, and the
book is a fixed 208 units.** `fire.scaleX` peaks above 1, so the question is not whether the
settled flame fits over its book -- it does -- but whether the flame is wider than the thing it
is burning on for the few frames where it is largest. This samples `Ignite` across that window
and reports the ratio at each, so the answer is a number rather than an impression.

**What overhangs is the belly, not the foot, and an earlier version of this said the opposite.**
At the burst peak the flame spans x 21..290 while the book spans 45..253 -- but measured at the
book's own top row the flame is only two pixels across, because the silhouette tapers to a
narrow contact point and the widest part of it is halfway up. So the flame never stands off the
paper; it bulges out *over* the book's edges like a canopy. That distinction decides what a fix
would even be: moving the foot is not available, because the foot is not the problem.

    ../../.venv/bin/python rive/streak_flame/aspect.py

**The book is found by darkness, not by hue, and that is a fix.** It used to look for
`BOARD = #067657` -- the *teal* cover that was built and then rejected -- so from the day the
covers went back to near-black it divided by zero on every run, which is how it came to ship
broken. See `BOOK_INK` for why the replacement is a hard threshold rather than the obvious
"anything that is neither ground nor fire": that reading admits the flame's own edge and then
reports the flame's width as the book's.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

from _preview import BUILD, GROUND, preview_project, shot  # noqa: E402

BODY = (0xF2, 0xA9, 0x3F)
CORE = (0xFF, 0xD4, 0x79)
TOL = 12

# The book's cover boards are near-black (`kCandleWellTop` / `kCandleWellBottom`) and run its
# full width; its pages are near-cream and the ground is white. So the book is the dark ink on
# the frame, and this separates it from everything else.
#
# **It has to be this dark, and the reason is the flame rather than the book.** `#F2A93F`
# averages 158 across its channels and the core `#FFD479` averages 196, so any threshold loose
# enough to admit a warm mid-tone admits the fire and measures the flame twice. On the burst
# frame every threshold from 160 to 240 returned 263-272px where the book is 209; at 120 it
# returns 209 on every frame in the window.
BOOK_INK = 120

# Duolingo's mark, measured off the reference.
REFERENCE = 1.15

# Frames across the burst and the settle. 767ms is the second failed grow, 900-1000 is the
# burst itself (`fire.scaleX` peaks at 1.28 in there), 1300 is where it comes to rest.
SAMPLES = (633, 767, 900, 950, 1000, 1100, 1300)

PAD = 10
LABEL_H = 16
ZOOM = 2


def near(p: tuple[int, ...], c: tuple[int, int, int]) -> bool:
    return all(abs(p[i] - c[i]) <= TOL for i in range(3))


def measure(img: Image.Image) -> tuple[int, int, int, int]:
    """`(flame width, flame height, book width, top gap)`, in rendered pixels.

    **The flame is the connected blob through the centre, not every warm pixel, and that is a
    fix.** The burst spray is drawn in the same two tokens as the flame -- deliberately; an
    ember the colour of what it left is an ember nobody can see -- so a plain colour match
    counts twelve confetti bits as part of the silhouette. It read as the flame growing from
    270 to 276 at the burst and from 189 to 212 at the settle, and flagged an overhang at
    1100ms that is really a spark out near the frame edge. Taking the component that contains a
    point known to be inside the body ignores anything that has left it.
    """
    px = img.load()
    w, h = img.size
    warm = [
        [near(px[x, y], BODY) or near(px[x, y], CORE) for y in range(h)]
        for x in range(w)
    ]
    book = [
        x
        for x in range(w)
        for y in range(int(h * 2 / 3), h)
        if sum(px[x, y]) / 3 < BOOK_INK
    ]
    bw = (max(book) - min(book) + 1) if book else 0

    # A seed the flame always covers: the centre column, a little above the book's top edge.
    # The flame's foot is a narrow contact point but it is always *on* the centre line.
    ytop = min(
        (y for y in range(int(h * 2 / 3), h) for x in range(w) if sum(px[x, y]) / 3 < BOOK_INK),
        default=h - 1,
    )
    cx = (min(book) + max(book)) // 2 if book else w // 2
    seed = next((y for y in range(ytop - 2, 0, -1) if warm[cx][y]), None)
    assert seed is not None, "no flame on the centre line"

    stack = [(cx, seed)]
    seen = {(cx, seed)}
    flame = []
    while stack:
        x, y = stack.pop()
        flame.append((x, y))
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and warm[nx][ny] and (nx, ny) not in seen:
                seen.add((nx, ny))
                stack.append((nx, ny))

    fw = max(x for x, _ in flame) - min(x for x, _ in flame) + 1
    fh = max(y for _, y in flame) - min(y for _, y in flame) + 1
    return fw, fh, bw, min(y for _, y in flame)


def main() -> int:
    project = preview_project(name="aspect")
    cells = []
    print(f"Duolingo's mark is about 1:{REFERENCE:.2f}\n")
    worst = 0.0
    for ms in SAMPLES:
        img = Image.open(shot(project, project / f"{ms}.png", ms)).convert("RGB")
        fw, fh, bw, gap = measure(img)
        ratio = fw / bw if bw else float("nan")
        worst = max(worst, ratio)
        over = "  OVERHANGS" if ratio > 1 else ""
        print(
            f"  {ms:5}ms  flame {fw:3}x{fh:3}  aspect 1:{fh / fw:.2f}  "
            f"flame/book {ratio:.3f}  top gap {gap:3}{over}"
        )
        cells.append((f"{ms}ms", img))

    print(
        f"\nwidest flame/book across the window: {worst:.3f} — "
        f"{'the belly overhangs the book' if worst > 1 else 'the flame stays within the book'}"
    )

    w, h = cells[0][1].size
    cw, ch = w * ZOOM, h * ZOOM
    out = Image.new(
        "RGB", (PAD + len(cells) * (cw + PAD), PAD + ch + LABEL_H + PAD), GROUND
    )
    draw = ImageDraw.Draw(out)
    for i, (label, img) in enumerate(cells):
        x = PAD + i * (cw + PAD)
        out.paste(img.resize((cw, ch), Image.NEAREST), (x, PAD))
        draw.text((x + 2, PAD + ch + 2), label, fill=(90, 70, 40))
    out.save(BUILD / "aspect.png")
    print(f"wrote {BUILD / 'aspect.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
