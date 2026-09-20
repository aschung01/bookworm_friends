#!/usr/bin/env python3
"""Render the flame's poses and lay them out as one contact sheet.

`rive . --verify` and `rive inspect .` between them catch every *structural*
mistake and not one *visual* one. Neither looks at a pixel, so a scene that
compiles clean can still draw a bow tie instead of a book -- which is exactly
what the first draft of `scene.rml` did. This renders the poses the blend state
is built from and writes a single strip to judge by eye.

    ../../../../.venv/bin/python sheet.py

PIL is not a dependency of this repo, so it comes from the main checkout's
`.venv` (a worktree gets no `.venv` of its own -- see AGENTS.md).

The ground is deliberately not white and not the previewer's near-black.
`kCandleGlow` #FFE8C4 is what `streak_celebration.dart` paints behind this
artboard, and a halo that reads beautifully on white can be invisible on it.
It comes from the scene's own `ground` rectangle, switched on by `--data`; see
the comment above that shape in `scene.rml` for why a chroma key could not do
the job.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).parent
BUILD = HERE / "build"

# The blend state's axis values. Every pose the animation interpolates
# between, so a defect that only exists between two of them is out of scope --
# but a defect *at* one of them cannot hide.
POSES = (0, 20, 35, 50, 70, 100)

# kCandleGlow, which the scene's `ground` rectangle is filled with.
GROUND = (255, 232, 196)

PAD = 12
LABEL_H = 18


def render(pose: int, ground: int) -> Path:
    out = BUILD / f"p{pose}.png" if ground else BUILD / f"p{pose}_dark.png"
    subprocess.run(
        [
            "rive",
            ".",
            f"--screenshot={out}",
            # Without --advance nothing has advanced and every frame is the
            # artboard's authored rest pose, which looks convincingly like a
            # working render right up until you notice all six are identical.
            "--advance=1",
            f"--data=progress={pose}",
            f"--data=ground={ground}",
        ],
        cwd=HERE,
        check=True,
        capture_output=True,
    )
    return out


def ink(img: Image.Image) -> float:
    """Fraction of the frame that is not bare ground.

    A number worth having next to the picture: the empty-state art went wrong
    once because one drawing sat at 7% coverage beside 21-35% siblings and so
    read as a smudge. Uneven coverage across poses means the animation changes
    weight, not just shape -- which a sequence that only ignites should not.
    """
    px = img.convert("RGB").load()
    drawn = 0
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y] != GROUND:
                drawn += 1
    return drawn / (img.width * img.height)


def strip(frames: list[Image.Image], bg: tuple[int, int, int], labels: bool) -> Image.Image:
    w, h = frames[0].size
    out = Image.new("RGB", (PAD + len(frames) * (w + PAD), PAD + h + LABEL_H + PAD), bg)
    draw = ImageDraw.Draw(out)
    for i, frame in enumerate(frames):
        x = PAD + i * (w + PAD)
        out.paste(frame.convert("RGB"), (x, PAD))
        if labels:
            draw.text(
                (x + 2, PAD + h + 2),
                f"progress={POSES[i]}   ink={ink(frame) * 100:.1f}%",
                fill=(90, 70, 40),
            )
    return out


def main() -> int:
    BUILD.mkdir(exist_ok=True)

    lit = [Image.open(render(p, 1)) for p in POSES]
    for pose, frame in zip(POSES, lit):
        print(f"  progress={pose:3d}  ink={ink(frame) * 100:5.1f}%")
    strip(lit, GROUND, labels=True).save(BUILD / "sheet.png")

    # A second strip on the previewer's own canvas. It answers a different
    # question: on the dark, a silhouette problem is obvious and the warm
    # palette's internal contrast is not flattered by a warm background.
    dark = [Image.open(render(p, 0)) for p in POSES]
    strip(dark, (29, 29, 29), labels=False).save(BUILD / "sheet_dark.png")

    print(f"wrote {BUILD / 'sheet.png'} and {BUILD / 'sheet_dark.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
