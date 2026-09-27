#!/usr/bin/env python3
"""Test one hypothesis: grey looks bad because the tile does not LIGHT the cat.

The reference sheet shows two things this mockup does not do.

  1. The ground is a radial GLOW, not a wash. Bright behind the character,
     vignetted into the corners, so the character reads as standing in a lit space.
     index.html currently emits `linear-gradient(top, bottom)` for every unrecorded
     hour -- a two-stop vertical wash, which reads as a flat card.

  2. The character is AMBIENT-SHADED by that ground. Duo is dark olive on the
     crimson tile and bright fresh green on the pastel mint -- same bird, lit
     differently. Our cut-out is pasted identically onto cream and onto near-black.

And a third thing worth naming: Duo is green in all fourteen reference tiles. The
mascot's colour never varies. Every bit of the variation is ground, shading and
expression -- which is an argument that the fur hunt was the wrong question and
the lighting is where the money is.

This script applies both effects locally so the claim can be judged rather than
argued. Throwaway.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image, ImageDraw, ImageFilter
from PIL.Image import Resampling

from _fur_sheets import GROUNDS, font, hexr, lum
from recolor_mascot_fur import CANDIDATES, recolour


def mix(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return (
        round(a[0] + (b[0] - a[0]) * t),
        round(a[1] + (b[1] - a[1]) * t),
        round(a[2] + (b[2] - a[2]) * t),
    )


WHITE = (255, 255, 255)
BLACK = (0, 0, 0)


def glow_ground(size: int, base: tuple[int, int, int], radius: int) -> Image.Image:
    """A radial glow: a lighter tint of the ground behind the character, falling off
    into a darker vignette at the corners. Built by drawing concentric ellipses into
    a small buffer and scaling up, which is cheap and smooth enough at tile size."""
    centre = mix(base, WHITE, 0.26)
    edge = mix(base, BLACK, 0.20)
    small = 64
    buf = Image.new("RGB", (small, small), edge)
    draw = ImageDraw.Draw(buf)
    # Centre of the glow sits above the middle, where the character's head is.
    cx, cy = small * 0.5, small * 0.42
    steps = 28
    for i in range(steps, 0, -1):
        t = i / steps
        r = small * 0.78 * t
        colour = mix(centre, edge, (1.0 - t) ** 1.4)
        draw.ellipse([cx - r, cy - r * 0.92, cx + r, cy + r * 0.92], fill=colour)
    buf = buf.filter(ImageFilter.GaussianBlur(2.0))
    glow = buf.resize((size, size), Resampling.LANCZOS).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=255
    )
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(glow, (0, 0), mask)
    return out


def ambient_shade(
    cat: Image.Image, ground: tuple[int, int, int], strength: float = 1.0
) -> Image.Image:
    """Light the character with the ground -- CORRECTED after v1 failed.

    v1 did two things and both were wrong. It multiplied hard toward the ground
    colour (up to 0.52) and then screened a "top light" into the character. The
    combination pulled the cat toward the ground's own hue and lightness, so on the
    yellow and blue tiles it dissolved -- contrast went DOWN, which is the opposite
    of what the reference does. On Duolingo's crimson tile Duo is dark olive: further
    from the ground than his base colour, not closer.

    So: no top lift at all, and the multiply is capped low. What is left is a faint
    ambient tint plus a contact shadow, which grounds the character without
    surrendering its silhouette. The glow in the ground does the rest of the work --
    that part of the hypothesis held up on its own.
    """
    cat = cat.convert("RGBA")
    width, height = cat.size
    g_lum = lum(ground)
    k = max(0.0, min(0.20, 0.20 * (1.0 - g_lum) ** 0.85)) * strength
    if k <= 0.001:
        return cat
    ambient = mix(WHITE, ground, k)
    raw = bytearray(cat.tobytes())
    for p in range(width * height):
        i = p * 4
        if raw[i + 3] == 0:
            continue
        for c in range(3):
            raw[i + c] = max(0, min(255, round(raw[i + c] * ambient[c] / 255.0)))
    return Image.frombytes("RGBA", cat.size, bytes(raw))


def seat(cat: Image.Image, tile: Image.Image, frac: float = 0.72) -> Image.Image:
    tile = tile.copy()
    height = int(tile.height * frac)
    width = round(cat.width * height / cat.height)
    scaled = cat.resize((width, height), Resampling.LANCZOS)
    tile.alpha_composite(
        scaled,
        (int((tile.width - width) / 2), tile.height - height + int(tile.height * 0.06)),
    )
    return tile


def flat_tile(size: int, base: tuple[int, int, int], radius: int) -> Image.Image:
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=radius, fill=base + (255,)
    )
    return tile


def main() -> int:
    """Three treatments, and a hue-opposition row.

    The treatments separate the two halves of the hypothesis so they can be judged
    apart: the glow ground, and the ambient shading. v1 bundled them and the
    ambient's failure hid the glow's success.

    The last two rows test the thing the reference sheet actually reveals: Duo can
    be one colour forever because GREEN sits opposite the entire purple -> magenta ->
    red arc Duolingo chose for its ladder. Hue opposition, not shading, is what makes
    him pop. Our `stages` ramp walks the whole wheel including yellow, so a green cat
    should separate beautifully on the pink and red tiles and clash on the yellow --
    which is a fact about the RAMP, not about the fur.
    """
    cats = Path("docs/mockups/streak-widget/cats")
    reading = Image.open(cats / "m03-reading.png").convert("RGBA")
    rows: list[tuple[str, str, str]] = [
        ("grey", "flat", "grey"),
        ("grey", "glow", "grey"),
        ("grey", "glow+amb", "grey"),
        ("tuxedo", "flat", "tuxedo"),
        ("tuxedo", "glow+amb", "tuxedo"),
        ("brandmuted", "flat", "green: hue test"),
        ("brandmuted", "glow+amb", "green: hue test"),
    ]

    size, pad, lab, hdr = 168, 12, 26, 40
    width = 150 + len(GROUNDS) * (size + pad) + pad
    sheet = Image.new(
        "RGB", (width, hdr + len(rows) * (size + pad + lab) + pad), "white"
    )
    draw = ImageDraw.Draw(sheet)
    fh, fr = font(15), font(15)
    for gi, (gname, _) in enumerate(GROUNDS):
        draw.multiline_text(
            (150 + gi * (size + pad), 6), gname, fill="black", font=fh, spacing=2
        )

    cache: dict[str, Image.Image] = {}
    for ri, (key, mode, note) in enumerate(rows):
        if key not in cache:
            cache[key] = recolour(reading, CANDIDATES[key][1])
        coloured = cache[key]
        y = hdr + ri * (size + pad + lab)
        draw.multiline_text(
            (6, y + size // 2 - 26), f"{note}\n{mode}", fill="black", font=fr, spacing=3
        )
        for gi, (_, ghex) in enumerate(GROUNDS):
            base = hexr(ghex)
            radius = int(size * 0.22)
            if mode == "flat":
                tile, body = flat_tile(size, base, radius), coloured
            elif mode == "glow":
                tile, body = glow_ground(size, base, radius), coloured
            else:
                tile = glow_ground(size, base, radius)
                body = ambient_shade(coloured, base)
            sheet.paste(seat(body, tile), (150 + gi * (size + pad), y))

    out = Path("docs/mockups/streak-widget/_fur_g_lighting.png")
    sheet.save(out)
    print("->", out, sheet.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
