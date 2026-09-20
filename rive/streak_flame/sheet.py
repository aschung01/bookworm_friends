#!/usr/bin/env python3
"""Render the `Ignite` timeline as a contact strip and look at it.

`rive . --verify` and `rive inspect .` between them catch every *structural*
mistake and not one *visual* one. Neither looks at a pixel, so a scene that
compiles clean can still draw a bow tie instead of a book -- which earlier drafts
of this one did, along with an egg instead of a flame and a black peg under it.

    ../../../../.venv/bin/python sheet.py

Writes build/sheet.png (on the cream the celebration paints) and
build/sheet_dark.png (on the previewer's canvas, where a silhouette problem is
obvious and a warm palette is not flattered by a warm background).

**This replaces the old `sheet.py` + `between.py` pair.** Those existed because
the choreography used to be six single-frame poses in a 1D blend state, so the
keyed poses and the blends between them were two different things to check -- and
a defect could hide in the second, which is exactly what happened when a
half-transparent page cross-faded over a near-black cover and turned the first
fifth of the sequence into a grey slab. A timeline has no such split: sampling it
by time *is* sampling the in-betweens.
"""

from __future__ import annotations

import sys

from PIL import Image, ImageDraw

from _preview import BUILD, CANVAS, GROUND, preview_project, shot

# Even samples across the 900ms of `Ignite`, plus the last frame.
SAMPLES_MS = (0, 70, 140, 210, 280, 350, 420, 490, 560, 660, 780, 900)

PAD = 8
LABEL_H = 14


def strip(frames: list[Image.Image], bg: tuple[int, int, int], labels: bool) -> Image.Image:
    w, h = frames[0].size
    out = Image.new("RGB", (PAD + len(frames) * (w + PAD), PAD + h + LABEL_H + PAD), bg)
    draw = ImageDraw.Draw(out)
    for i, frame in enumerate(frames):
        x = PAD + i * (w + PAD)
        out.paste(frame.convert("RGB"), (x, PAD))
        if labels:
            draw.text((x + 2, PAD + h + 2), f"{SAMPLES_MS[i]}ms", fill=(90, 70, 40))
    return out


def main() -> int:
    BUILD.mkdir(exist_ok=True)

    lit_project = preview_project()
    lit = [
        Image.open(shot(lit_project, BUILD / f"s{ms:04d}.png", ms)) for ms in SAMPLES_MS
    ]
    dark = [
        Image.open(shot(BUILD.parent, BUILD / f"sd{ms:04d}.png", ms))
        for ms in SAMPLES_MS
    ]

    strip(lit, GROUND, labels=True).save(BUILD / "sheet.png")
    strip(dark, CANVAS, labels=False).save(BUILD / "sheet_dark.png")
    print(f"wrote {BUILD / 'sheet.png'} and {BUILD / 'sheet_dark.png'}")
    print(f"  {len(SAMPLES_MS)} samples across Ignite, {SAMPLES_MS[-1]}ms")
    return 0


if __name__ == "__main__":
    sys.exit(main())
