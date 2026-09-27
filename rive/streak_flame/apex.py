#!/usr/bin/env python3
"""Track the flame's apex across the `Idle` loop and print how far it travels.

"The top bounces sideways more than up and down" is a measurable claim about one
point, and the whole history of this file says to measure instead of squinting at a
ten-cell strip where the motion is a couple of pixels. For each frame this finds the
topmost body pixel and reports its x and y, then summarises the two spans.

    ../../.venv/bin/python rive/streak_flame/apex.py
"""

from __future__ import annotations

import sys

from PIL import Image


from _preview import BUILD, preview_project, shot  # noqa: E402

BODY = (0xF2, 0xA9, 0x3F)
CORE = (0xFF, 0xD4, 0x79)
TOL = 12
IDLE_FRAMES = 72
STEP = 4
FPS = 60


def apex(img: Image.Image) -> tuple[int, int] | None:
    """Topmost body pixel, and the centre of that row's run.

    The centre rather than the leftmost, because a rounded tip's top row is several
    pixels wide and which end of it you pick would itself wobble.
    """
    px = img.load()
    w, h = img.size
    for y in range(h):
        xs = [
            x
            for x in range(w)
            if all(abs(px[x, y][i] - BODY[i]) <= TOL for i in range(3))
            or all(abs(px[x, y][i] - CORE[i]) <= TOL for i in range(3))
        ]
        if xs:
            return (xs[0] + xs[-1]) // 2, y
    return None


def is_body(px, x: int, y: int) -> bool:
    p = px[x, y]
    return all(abs(p[i] - BODY[i]) <= TOL for i in range(3)) or all(
        abs(p[i] - CORE[i]) <= TOL for i in range(3)
    )


def widest(img: Image.Image) -> int:
    """The body's widest row.

    The apex barely translates sideways -- it sits near the centreline, so `scaleX`
    hardly moves it. What a reader actually sees going sideways is the *belly*
    swelling and shrinking, which is a different number and the one worth reporting
    next to the apex's rise.
    """
    px = img.load()
    w, h = img.size
    best = 0
    for y in range(h):
        xs = [x for x in range(w) if is_body(px, x, y)]
        if xs:
            best = max(best, xs[-1] - xs[0] + 1)
    return best


def main() -> int:
    project = preview_project(name="apex", first_animation="Idle")
    xs, ys, ws = [], [], []
    print("frame    apex x   apex y   width")
    for f in range(0, IDLE_FRAMES + 1, STEP):
        ms = f * 1000 / FPS
        img = Image.open(shot(project, BUILD / f"ap{f:03d}.png", ms)).convert("RGB")
        found = apex(img)
        if not found:
            print(f"{f:5}    (no body pixels)")
            continue
        x, y = found
        wide = widest(img)
        xs.append(x)
        ys.append(y)
        ws.append(wide)
        print(f"{f:5}    {x:6}   {y:6}   {wide:5}")
    print()
    print(f"apex horizontal span  {max(xs) - min(xs):3}px   (x {min(xs)}..{max(xs)})")
    print(f"apex vertical span    {max(ys) - min(ys):3}px   (y {min(ys)}..{max(ys)})")
    print(f"belly width span      {max(ws) - min(ws):3}px   ({min(ws)}..{max(ws)})")
    print(
        f"rise : width-wobble = "
        f"{(max(ys) - min(ys)) / max(max(ws) - min(ws), 1):.2f} : 1"
    )
    print(f"seam: frame 0 apex {xs[0], ys[0]} w{ws[0]}   "
          f"frame {IDLE_FRAMES} apex {xs[-1], ys[-1]} w{ws[-1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
