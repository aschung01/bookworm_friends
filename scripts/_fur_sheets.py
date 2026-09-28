#!/usr/bin/env python3
"""Build the two sheets the fur decision needed, and measure the part that is
measurable.

**The decision landed on 2026-09-27 and it was NEUTRAL GREY** -- see
`docs/mockups/mascot/CHARACTER.md`, "The fur is a neutral grey". This said
"Throwaway: delete once the colour is chosen"; it is kept anyway, because the
sheets are the record of what the twenty-seven candidates looked like and because
the one recommendation that did NOT ship -- widening the ears-to-belly step to
about 4:1, against the shipped palette's 2.07:1 -- would be judged on Sheet A
again. `recolor_mascot_fur.py` is the tool for that.

Sheet A  each candidate large, on the app's own cream tile -- for judging colour.
Sheet B  every candidate against every ground the widget can now draw -- for
         judging survival. This is the sheet that mattered, because the `stages`
         ramp put saturated blue, yellow, pink and deep red under the character
         alongside the existing cream and the dark lamp. Note the ramp has since
         been rebuilt dark at every hour precisely so the grey would survive it,
         so Sheet B's grounds are no longer the ones that ship.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image, ImageDraw, ImageFont
from PIL.Image import Resampling

from recolor_mascot_fur import CANDIDATES, recolour

CATS = Path("docs/mockups/streak-widget/cats")
OUT = Path("docs/mockups/streak-widget")

# The grounds, as the mid-tone each tile actually renders. Cream and lamp come from
# the stylesheet; the four saturated ones are `stages` interpolated at the hours
# that name its documented stages; mint is its recorded ground.
GROUNDS: list[tuple[str, str]] = [
    ("cream\n(candle)", "#FFF2DD"),
    ("mint\n(recorded)", "#E2F8CE"),
    ("blue\n07:00", "#3CBCF8"),
    ("yellow\n14:00", "#FFAF00"),
    ("pink\n18:00", "#FF74BA"),
    ("red\n23:00", "#B71822"),
    ("lamp\n(dark)", "#1C1308"),
]


def hexr(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def lum(rgb: tuple[int, int, int]) -> float:
    def f(v: float) -> float:
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

    r, g, b = rgb
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in (
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
    ):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def rounded(size: int, fill: tuple[int, int, int]) -> Image.Image:
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=fill + (255,)
    )
    return tile


def seat(cat: Image.Image, tile: Image.Image, frac: float = 0.72) -> Image.Image:
    """Place the character on the tile's bottom edge, cropped, as the widget does."""
    tile = tile.copy()
    height = int(tile.height * frac)
    width = round(cat.width * height / cat.height)
    scaled = cat.resize((width, height), Resampling.LANCZOS)
    tile.alpha_composite(
        scaled,
        (int((tile.width - width) / 2), tile.height - height + int(tile.height * 0.06)),
    )
    return tile


def sheet_a(cat: Image.Image) -> None:
    size, pad, lab = 300, 22, 40
    cols = 3
    rows = (len(CANDIDATES) + cols - 1) // cols
    sheet = Image.new(
        "RGB",
        (cols * (size + pad) + pad, rows * (size + pad + lab) + pad),
        "white",
    )
    draw = ImageDraw.Draw(sheet)
    f = font(17)
    for i, (key, (label, ramp)) in enumerate(sorted(CANDIDATES.items())):
        cx, cy = i % cols, i // cols
        x = pad + cx * (size + pad)
        y = pad + cy * (size + pad + lab)
        tile = seat(recolour(cat, ramp), rounded(size, hexr("#FFF2DD")))
        sheet.paste(tile, (x, y), tile)
        draw.text((x + 2, y + size + 10), label, fill="black", font=f)
    sheet.save(OUT / "_fur_a_colour.png")
    print("sheet A ->", OUT / "_fur_a_colour.png", sheet.size)


def sheet_b(cat: Image.Image) -> None:
    size, pad, head, gut = 150, 10, 46, 120
    sheet = Image.new(
        "RGB",
        (gut + len(GROUNDS) * (size + pad) + pad, head + len(CANDIDATES) * (size + pad) + pad),
        "white",
    )
    draw = ImageDraw.Draw(sheet)
    fh, fr = font(15), font(14)
    for gi, (gname, _) in enumerate(GROUNDS):
        draw.multiline_text(
            (gut + gi * (size + pad) + 4, 6), gname, fill="black", font=fh, spacing=2
        )
    print("\nbody-vs-ground contrast (the character is a flat shape, so this is")
    print("how much of it is visible at all):\n")
    header = "            " + "".join(f"{g.splitlines()[0][:7]:>9}" for g, _ in GROUNDS)
    print(header)
    for ri, (key, (label, ramp)) in enumerate(sorted(CANDIDATES.items())):
        y = head + ri * (size + pad)
        draw.text((6, y + size // 2 - 8), key, fill="black", font=fr)
        ratios = []
        for gi, (_, ghex) in enumerate(GROUNDS):
            tile = seat(recolour(cat, ramp), rounded(size, hexr(ghex)))
            sheet.paste(tile, (gut + gi * (size + pad), y), tile)
            ratios.append(contrast(ramp.body, hexr(ghex)))
        worst = min(ratios)
        print(
            f"  {key:<10}" + "".join(f"{r:8.2f} " for r in ratios) + f"   worst {worst:.2f}"
        )
    sheet.save(OUT / "_fur_b_grounds.png")
    print("\nsheet B ->", OUT / "_fur_b_grounds.png", sheet.size)


FINALISTS = [
    "grey",
    "brand",
    "brandmuted",
    "moss",
    "taupe",
    "slate",
    "chocolate",
    "charcoal",
]

# Round 2, grouped by which lever it pulls. See the comment in recolor_mascot_fur.
ROUND2 = [
    ("A \u00b7 saturated", ["teal", "terracotta", "plum", "mustard", "indigo", "rust"]),
    ("B \u00b7 wide spread", ["tuxedo", "smoke", "sealpoint", "bluepoint"]),
    ("C \u00b7 both", ["tealpoint", "gingerpoint", "orchid"]),
]


def sheet_d(cat: Image.Image, reading: Image.Image) -> None:
    """Round 2, same layout as sheet C so the two are directly comparable.

    Grey is repeated at the top of every group as the control, because comparing a
    saturated candidate against the group above it rather than against what ships
    is how a sheet flatters itself.
    """
    big, small, pad, lab, hdr = 260, 118, 12, 30, 34
    width = pad + big + pad * 2 + len(GROUNDS) * (small + pad) + pad
    row = big + lab + pad
    total = sum(len(keys) + 1 for _, keys in ROUND2)
    height = lab + len(ROUND2) * hdr + total * row + pad
    sheet = Image.new("RGB", (width, height), "white")
    draw = ImageDraw.Draw(sheet)
    fh, fb, fg = font(14), font(18), font(20)
    for gi, (gname, _) in enumerate(GROUNDS):
        draw.multiline_text(
            (pad + big + pad * 2 + gi * (small + pad), 4),
            gname,
            fill="black",
            font=fh,
            spacing=1,
        )
    y = lab
    for group, keys in ROUND2:
        draw.text((pad, y + 8), group, fill="black", font=fg)
        y += hdr
        for key in ["grey"] + keys:
            label, ramp = CANDIDATES[key]
            tile = seat(recolour(cat, ramp), rounded(big, hexr("#FFF2DD")))
            sheet.paste(tile, (pad, y), tile)
            suffix = "   (control)" if key == "grey" else ""
            draw.text((pad + 4, y + big + 6), label + suffix, fill="black", font=fb)
            recoloured = recolour(reading, ramp)
            for gi, (_, ghex) in enumerate(GROUNDS):
                strip = seat(recoloured, rounded(small, hexr(ghex)))
                sheet.paste(
                    strip,
                    (pad + big + pad * 2 + gi * (small + pad), y + (big - small) // 2),
                    strip,
                )
            y += row
    sheet.save(OUT / "_fur_d_round2.png")
    print("sheet D ->", OUT / "_fur_d_round2.png", sheet.size)


def sheet_c(cat: Image.Image, reading: Image.Image) -> None:
    """The finalists: the five candidates that clear 3:1 on every app-native
    ground, plus the current grey as the control. Large colour read on the left,
    the ground survival strip on the right, one row each."""
    big, small, pad, lab = 260, 118, 12, 30
    width = pad + big + pad * 2 + len(GROUNDS) * (small + pad) + pad
    row = max(big, small) + lab + pad
    sheet = Image.new("RGB", (width, lab + len(FINALISTS) * row + pad), "white")
    draw = ImageDraw.Draw(sheet)
    fh, fb = font(14), font(18)
    for gi, (gname, _) in enumerate(GROUNDS):
        draw.multiline_text(
            (pad + big + pad * 2 + gi * (small + pad), 4),
            gname,
            fill="black",
            font=fh,
            spacing=1,
        )
    for ri, key in enumerate(FINALISTS):
        label, ramp = CANDIDATES[key]
        y = lab + ri * row
        tile = seat(recolour(cat, ramp), rounded(big, hexr("#FFF2DD")))
        sheet.paste(tile, (pad, y), tile)
        draw.text((pad + 4, y + big + 6), label, fill="black", font=fb)
        recoloured = recolour(reading, ramp)
        for gi, (_, ghex) in enumerate(GROUNDS):
            strip = seat(recoloured, rounded(small, hexr(ghex)))
            sheet.paste(
                strip,
                (pad + big + pad * 2 + gi * (small + pad), y + (big - small) // 2),
                strip,
            )
    sheet.save(OUT / "_fur_c_finalists.png")
    print("sheet C ->", OUT / "_fur_c_finalists.png", sheet.size)


def main() -> int:
    # Sheet A uses a prop-free pose deliberately. In `m03-reading` the book is drawn
    # in the *same* neutral greys as the fur, so it recolours along with it and a
    # ginger cat ends up holding a ginger book. That is a real finding -- the prop
    # shares the fur palette and would have to be re-specified for any coloured cat
    # -- but it is a confound when the question is only "what colour is the animal".
    blush = Image.open(CATS / "m13-blush.png").convert("RGBA")
    # Sheet B keeps the reading pose, because that is the actual daytime tile and the
    # question there is whether the *silhouette* survives the ground.
    reading = Image.open(CATS / "m03-reading.png").convert("RGBA")
    sheet_a(blush)
    sheet_b(reading)
    sheet_c(blush, reading)
    sheet_d(blush, reading)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
