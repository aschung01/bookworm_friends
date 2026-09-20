#!/usr/bin/env python3
"""Render the flame across the whole scrub, not just at the poses it blends between.

`sheet.py` renders the six keyed poses. That is where a *geometry* defect lives,
but it is not where an *animation* defect lives: a blend state interpolates every
property independently and linearly between neighbouring poses, so two poses that
are each fine can still pass through something that is not. Anything keyed in a
straight line through an arc -- or two properties whose midpoints disagree --
shows up here and nowhere else.

    ../../../../.venv/bin/python between.py

Writes one contact sheet per row of the scrub to build/between.png.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).parent
BUILD = HERE / "build"

# Every 4%, so each gap between keyed poses gets several samples rather than one.
STEP = 4
PER_ROW = 13

# kCandleGlow, via the scene's own preview-only `ground` rectangle.
GROUND = (255, 232, 196)

PAD = 6
LABEL_H = 14


def render(pose: int) -> Image.Image:
    out = BUILD / f"b{pose:03d}.png"
    subprocess.run(
        [
            "rive",
            ".",
            f"--screenshot={out}",
            "--advance=1",
            f"--data=progress={pose}",
            "--data=ground=1",
        ],
        cwd=HERE,
        check=True,
        capture_output=True,
    )
    return Image.open(out).convert("RGB")


def main() -> int:
    BUILD.mkdir(exist_ok=True)
    values = list(range(0, 101, STEP))
    frames = [render(v) for v in values]

    # Halve them: the whole scrub on one sheet matters more than fine detail,
    # which is what sheet.py is for.
    small = [f.resize((f.width // 2, f.height // 2), Image.LANCZOS) for f in frames]
    w, h = small[0].size

    rows = (len(small) + PER_ROW - 1) // PER_ROW
    sheet = Image.new(
        "RGB",
        (PAD + PER_ROW * (w + PAD), rows * (PAD + h + LABEL_H)),
        GROUND,
    )
    draw = ImageDraw.Draw(sheet)

    for i, (value, frame) in enumerate(zip(values, small)):
        col, row = i % PER_ROW, i // PER_ROW
        x = PAD + col * (w + PAD)
        y = PAD + row * (PAD + h + LABEL_H)
        sheet.paste(frame, (x, y))
        draw.text((x + 2, y + h + 1), str(value), fill=(90, 70, 40))

    out = BUILD / "between.png"
    sheet.save(out)
    print(f"wrote {out} ({len(values)} frames, every {STEP}%)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
