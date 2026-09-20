#!/usr/bin/env python3
"""Render the flame on the timing it actually ships with, and write a GIF.

`sheet.py` samples the keyed poses and `between.py` samples the scrub evenly.
Neither is what a reader sees, because **the app does not scrub `progress`
linearly.** `streak_celebration.dart` drives it from `_flame`, a curve over a
fixed window, so a defect in the *timing* -- a beat nobody can see because the
curve races past it -- is invisible to the other two sheets by construction.

    ../../../../.venv/bin/python motion.py

Writes build/motion.gif plus build/motion_strip.png.

**This is the script that condemned the first curve.** `_ignite`'s `easeOutBack`
crossed 0 -> 100 in 185ms and then overshot to 108, and since a 1D blend clamps
past its last pose, 20 of 32 frames were the same held frame: the entire
choreography played in three frames and a reader saw the flame appear rather
than a book falling open. Hence `_flame`. Any value above 100 printed below
means that has regressed.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).parent
BUILD = HERE / "build"

# `_beat(0, 760, curve: Curves.easeInOutCubic)` -- the artboard's own drive, which is
# deliberately not the glyph's `_ignite`. See `_flame` in `streak_celebration.dart`.
WINDOW_MS = 760
FPS = 60

# Flutter's `Curves.easeInOutCubic`, which is `Cubic(0.645, 0.045, 0.355, 1.0)`.
CUBIC = (0.645, 0.045, 0.355, 1.0)

# Frames to hold the resting pose at the end, so the GIF reads as an event that
# finishes rather than a loop. Pose 100 is a resting pose; this is the proof.
HOLD_FRAMES = 30


def cubic(t: float) -> float:
    """Evaluate a Flutter `Cubic` at `t`, the way Flutter does.

    A CSS-style cubic bezier is a *parametric* curve, so `y` is not a direct
    function of `t`: Flutter binary-searches the parameter whose `x` equals `t`,
    then returns that point's `y`. Reimplemented rather than approximated
    because the whole point of this script is to match what ships.
    """

    x1, y1, x2, y2 = CUBIC

    def bezier(a: float, b: float, m: float) -> float:
        # The two endpoints are fixed at 0 and 1, so only the controls appear.
        return 3 * a * m * (1 - m) ** 2 + 3 * b * m**2 * (1 - m) + m**3

    start, end = 0.0, 1.0
    for _ in range(60):
        mid = (start + end) / 2
        if bezier(x1, x2, mid) < t:
            start = mid
        else:
            end = mid
    return bezier(y1, y2, (start + end) / 2)


def render(index: int, progress: float) -> Image.Image:
    out = BUILD / f"m{index:03d}.png"
    subprocess.run(
        [
            "rive",
            ".",
            f"--screenshot={out}",
            "--advance=1",
            # Unclamped on purpose -- see the module docstring.
            f"--data=progress={progress:.2f}",
            "--data=ground=1",
        ],
        cwd=HERE,
        check=True,
        capture_output=True,
    )
    return Image.open(out).convert("RGB")


def main() -> int:
    BUILD.mkdir(exist_ok=True)

    frame_ms = 1000 / FPS
    count = int(WINDOW_MS / frame_ms) + 1
    values = [cubic(min(1.0, i * frame_ms / WINDOW_MS)) * 100 for i in range(count)]

    frames = []
    for i, value in enumerate(values):
        frames.append(render(i, value))
        ms = i * frame_ms
        flag = "  <- clamped" if value > 100 else ""
        print(f"  {ms:6.1f}ms  progress={value:7.2f}{flag}")

    frames.extend([frames[-1]] * HOLD_FRAMES)

    gif = BUILD / "motion.gif"
    frames[0].save(
        gif,
        save_all=True,
        append_images=frames[1:],
        # GIF delays are in centiseconds, so 60fps rounds to 2cs (~50fps).
        duration=max(20, round(frame_ms / 10) * 10),
        loop=0,
        optimize=True,
    )

    # A strip too, because a GIF cannot be read frame by frame in a review.
    every = 3
    picked = frames[: count : every]
    w, h = picked[0].size
    small = [f.resize((w // 3, h // 3), Image.LANCZOS) for f in picked]
    sw, sh = small[0].size
    strip = Image.new("RGB", (len(small) * sw, sh), (255, 232, 196))
    for i, f in enumerate(small):
        strip.paste(f, (i * sw, 0))
    strip.save(BUILD / "motion_strip.png")

    over = sum(1 for v in values if v > 100)
    print(f"\n{count} frames over {WINDOW_MS}ms; {over} of them above 100 and clamped")
    print(f"wrote {gif} and {BUILD / 'motion_strip.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
