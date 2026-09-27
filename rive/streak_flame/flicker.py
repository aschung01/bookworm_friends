#!/usr/bin/env python3
"""A dense strip of consecutive `Idle` frames, to judge flicker rather than amplitude.

`apex.py` samples every fourth frame, which is fine for measuring a span and useless for
judging *rhythm*: the flicker now runs a beat roughly every six frames, so a stride of four
aliases it into something that looks regular. This renders consecutive frames, crops to the
tip, and stacks them in rows so the irregularity is visible in one picture.

    ../../.venv/bin/python rive/streak_flame/flicker.py 0 36

Also prints the apex height per frame, because a strip shows the shape of the motion and the
numbers show whether two neighbouring beats are actually different sizes.
"""

from __future__ import annotations

import sys

from PIL import Image, ImageDraw


from _preview import BUILD, GROUND, preview_project, shot  # noqa: E402

BODY = (0xF2, 0xA9, 0x3F)
CORE = (0xFF, 0xD4, 0x79)
TOL = 12
FPS = 60
PER_ROW = 12
# Crop to the flame's upper half only. The book never moves in `Idle` and the belly barely
# does; spending pixels on either is what hid the tip in every earlier strip.
TOP, BOTTOM = 10, 130
LEFT, RIGHT = 95, 215
ZOOM = 2
LABEL_H = 12


def is_body(p: tuple[int, ...]) -> bool:
    return all(abs(p[i] - BODY[i]) <= TOL for i in range(3)) or all(
        abs(p[i] - CORE[i]) <= TOL for i in range(3)
    )


def main(argv: list[str]) -> int:
    first, last = (int(a) for a in (argv or ["0", "35"]))
    project = preview_project(name="flicker", first_animation="Idle")
    frames, tops = [], []
    for f in range(first, last + 1):
        img = Image.open(
            shot(project, BUILD / f"fl{f:03d}.png", f * 1000 / FPS)
        ).convert("RGB")
        px = img.load()
        top = next(
            (y for y in range(img.height) if any(is_body(px[x, y]) for x in range(img.width))),
            -1,
        )
        tops.append((f, top))
        frames.append(img.crop((LEFT, TOP, RIGHT, BOTTOM)))

    w, h = frames[0].size
    cw, ch = w * ZOOM, h * ZOOM
    rows = (len(frames) + PER_ROW - 1) // PER_ROW
    out = Image.new("RGB", (PER_ROW * cw, rows * (ch + LABEL_H)), GROUND)
    draw = ImageDraw.Draw(out)
    for i, img in enumerate(frames):
        x, y = (i % PER_ROW) * cw, (i // PER_ROW) * (ch + LABEL_H)
        out.paste(img.resize((cw, ch), Image.NEAREST), (x, y))
        draw.text((x + 2, y + ch + 1), f"{tops[i][0]}:{tops[i][1]}", fill=(90, 70, 40))
    path = BUILD / "flicker.png"
    out.save(path)
    print(f"wrote {path}")
    print("frame:apex-y  " + "  ".join(f"{f}:{t}" for f, t in tops))
    deltas = [tops[i + 1][1] - tops[i][1] for i in range(len(tops) - 1)]
    print(f"per-frame deltas: {deltas}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
