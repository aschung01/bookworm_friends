#!/usr/bin/env python3
"""Watch the flame move: a strip of the `Idle` loop, and a GIF of the whole sequence.

**`sheet.py` is not enough, and this is the third check rather than a nicety.** A
contact strip of `Ignite` says nothing at all about `Idle` -- the previewer plays
only the artboard's first animation, so until this script existed the loop had
never been rendered even once. It is also the only thing that shows the *seam*: a
looping timeline whose properties do not return to their frame-0 values jumps once
a second, forever, on a screen a reader opens nightly, and no still frame can
show that.

    ../../../../.venv/bin/python motion.py

Writes build/idle.png (a strip across one loop) and build/motion.gif (the ignition
at 30fps, then two loops, which is the thing to actually judge).

**This replaces the old `motion.py`, whose job no longer exists.** It used to
reimplement Flutter's cubic solve in Python, because the choreography was six
poses in a blend state scrubbed by a Dart curve and the only way to see the real
timing was to evaluate that curve here. The timeline owns its easing now and Dart
drives it linearly, so `--advance=<ms>` *is* the real timing and there is nothing
left to reimplement.
"""

from __future__ import annotations

import sys

from PIL import Image, ImageDraw

from _preview import BUILD, FPS, GROUND, preview_project, shot

# Must match `Ignite`'s duration in scene.rml. **This was 46 for two revisions after the
# timeline went to 54**, so the GIF quietly stopped at 767ms and the tail of the ignition --
# the part being iterated on -- was never in it. There is no way to read the duration out of
# the previewer, so the only defence is to change this line in the same commit as the RML.
IGNITE_FRAMES = 78
IDLE_FRAMES = 72

# Every other frame: 30fps is enough to judge choreography, and halves a render loop
# that spawns one process per frame.
STEP = 2

PAD = 8
LABEL_H = 14


def frames(project, tag: str, count: int, *, loops: int = 1) -> list[Image.Image]:
    out = []
    for loop in range(loops):
        for frame in range(0, count, STEP):
            ms = frame * 1000 / FPS + loop * count * 1000 / FPS
            path = BUILD / f"{tag}{loop}_{frame:03d}.png"
            out.append(Image.open(shot(project, path, ms)).convert("RGB"))
    return out


def strip(images: list[Image.Image], labels: list[str]) -> Image.Image:
    w, h = images[0].size
    out = Image.new(
        "RGB", (PAD + len(images) * (w + PAD), PAD + h + LABEL_H + PAD), GROUND
    )
    draw = ImageDraw.Draw(out)
    for i, image in enumerate(images):
        x = PAD + i * (w + PAD)
        out.paste(image, (x, PAD))
        draw.text((x + 2, PAD + h + 2), labels[i], fill=(90, 70, 40))
    return out


def main() -> int:
    BUILD.mkdir(exist_ok=True)

    ignite = preview_project(name="preview")
    # Reordered so the loop is what plays. It needs nothing else: the scene authors the open
    # book, so a timeline that only keys the flame leaves the rest of the drawing where the
    # ignition would have left it. That was not true once -- see `_preview.py`.
    idle = preview_project(name="preview_idle", first_animation="Idle")

    # A strip across one loop, for reading the seam: the first and last cells are the
    # same instant and must be the same picture.
    seam_frames = list(range(0, IDLE_FRAMES + 1, 8))
    seam = [
        Image.open(shot(idle, BUILD / f"idle_{f:03d}.png", f * 1000 / FPS)).convert(
            "RGB"
        )
        for f in seam_frames
    ]
    strip(seam, [f"f{f}" for f in seam_frames]).save(BUILD / "idle.png")

    gif = frames(ignite, "m_ig", IGNITE_FRAMES) + frames(
        idle, "m_id", IDLE_FRAMES, loops=2
    )
    gif[0].save(
        BUILD / "motion.gif",
        save_all=True,
        append_images=gif[1:],
        duration=int(1000 * STEP / FPS),
        loop=0,
    )

    print(f"wrote {BUILD / 'idle.png'} ({len(seam)} cells across one loop)")
    print(f"wrote {BUILD / 'motion.gif'} ({len(gif)} frames at {FPS // STEP}fps)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
