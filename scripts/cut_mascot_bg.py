#!/usr/bin/env python3
"""Key the flat white plate off mascot renders, producing RGBA PNGs for mockups.

Why this exists separately from `scripts/cutout_bg.py`: that one calls Bedrock's
`stability.stable-image-remove-background-v1:0` and its docstring says the
machine has "neither PIL nor ImageMagick". That is stale -- Pillow 12 is in
`.venv` -- and the mascot renders do not need a segmentation model anyway. They
are flat vector art on a pure #FFFFFF field, so the plate can be keyed exactly,
locally, for free, with no credentials.

The two things that make it exact rather than approximate:

1. **Threshold the MINIMUM channel, not the average.** The background is 255
   white, but the belly patch is (253, 240, 232) -- its red channel is 253, so an
   average or a per-channel-any test eats the belly. min() is 232 there against
   255 for the plate, which separates them cleanly.

2. **Only key white that is CONNECTED to the border.** A global threshold would
   also punch holes through the eye whites and any enclosed highlight. Flooding
   inward from the edge leaves interior near-whites alone, because they are
   fenced in by charcoal pupils and grey fur.

Downscaling happens *before* the flood, because the renders are ~1776x2368 (4.2M
pixels) and a mockup needs ~720px. Keying the small version is ~6x less work and
the result is what actually ships into the page.

    .venv/bin/python scripts/cut_mascot_bg.py --dest <dir> [--width 720] NAME...

NAME is a manifest stem such as `m13-blush-widget-v2`, with or without `.png`.
"""

from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

REPO = Path(__file__).resolve().parent.parent
ART = REPO / "docs" / "mockups" / "mascot" / "art"

# Pixels at or above this on their minimum channel are plate candidates. The
# gap to the belly's 232 is wide, so this is not a tuned magic number -- 240 and
# 250 both work. Below ~236 it starts eating the belly.
WHITE = 246


def cut(src: Path, width: int) -> Image.Image:
    im = Image.open(src).convert("RGB")
    if im.width > width:
        im = im.resize(
            (width, round(im.height * width / im.width)), Image.Resampling.LANCZOS
        )
    w, h = im.size
    # Raw bytes rather than `im.load()`: the PixelAccess type is `| None` and its
    # __getitem__ is typed loosely enough that every read trips the checker, and
    # flat indexing into a bytes object is faster in pure Python anyway.
    buf = im.tobytes()

    def is_plate(i: int) -> bool:
        o = i * 3
        return min(buf[o], buf[o + 1], buf[o + 2]) >= WHITE

    # Flood inward from every border pixel that looks like plate. Four-connected
    # is enough and halves the work; the plate is one open region.
    bg = bytearray(w * h)
    q: deque[int] = deque()

    def seed(i: int) -> None:
        if not bg[i] and is_plate(i):
            bg[i] = 1
            q.append(i)

    for x in range(w):
        seed(x)
        seed((h - 1) * w + x)
    for y in range(h):
        seed(y * w)
        seed(y * w + w - 1)

    while q:
        i = q.popleft()
        x = i % w
        if x and not bg[i - 1]:
            seed(i - 1)
        if x < w - 1 and not bg[i + 1]:
            seed(i + 1)
        if i >= w and not bg[i - w]:
            seed(i - w)
        if i < (h - 1) * w and not bg[i + w]:
            seed(i + w)

    alpha = Image.frombytes(
        "L", (w, h), bytes(0 if v else 255 for v in bg)
    ).filter(ImageFilter.GaussianBlur(0.7))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    box = out.getbbox()
    return out.crop(box) if box else out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("names", nargs="+", metavar="NAME")
    ap.add_argument("--dest", required=True)
    ap.add_argument("--width", type=int, default=720)
    a = ap.parse_args()

    dest = Path(a.dest).resolve()
    dest.mkdir(parents=True, exist_ok=True)

    for raw in a.names:
        stem = raw.removesuffix(".png")
        src = ART / f"{stem}.png"
        if not src.exists():
            raise SystemExit(f"not found: {src}")
        # Drop the round infix and variant so the mockup refers to `m13-blush`
        # rather than `m13-blush-widget-v2` -- the page should not care which
        # sample won.
        short = stem.split("-widget-")[0]
        img = cut(src, a.width)
        out = dest / f"{short}.png"
        img.save(out, optimize=True)
        kb = out.stat().st_size // 1024
        print(f"{stem:28s} -> {out.name:18s} {img.size[0]}x{img.size[1]}  {kb} KB")


if __name__ == "__main__":
    main()
