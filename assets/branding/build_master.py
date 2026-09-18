#!/usr/bin/env python3
"""Turn the chalk artwork in app_icon_source.png into the icon masters.

The chalk mark is raster, not vector, so the SVG geometry that used to drive
this directory cannot express it. What the platforms actually need, though, is
not vector -- it is a clean **alpha channel** plus a flat brand plate. This
script produces exactly that:

    app_icon.png             opaque, full bleed, brand plate + white mark
    app_icon_mark.png        white mark on transparency  (iOS dark / tinted)
    app_icon_foreground.png  same, inset for the launcher mask (Android)
    app_icon_maskable.png    opaque, inset          (web `purpose: maskable`)
    app_icon_macos.png       opaque, rounded body   (macOS icon grid)

Why the alpha has to be *derived* rather than key-colour matted: the generated
artwork's background is not a single flat colour (it ranges over roughly
(35..52, 179..186, 134..146)) and the chalk edges are soft, so a chroma-key
would leave a fringe of dirty green pixels around every stroke. Instead we take
alpha from how far each pixel has travelled from the background green toward
white, which keeps the soft chalk edge intact and lets us re-composite the mark
onto an exact #09BC8A plate.

Run via ./build_icons.sh -- it calls this first, then flutter_launcher_icons.
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFilter
except ModuleNotFoundError:
    sys.exit(
        "Pillow is required.\n"
        "    python3 -m venv .venv && .venv/bin/pip install Pillow\n"
        "then run ./assets/branding/build_icons.sh"
    )

HERE = Path(__file__).parent
SOURCE = HERE / "app_icon_source.png"

SIZE = 1024
BRAND = (9, 188, 138)

# Android's adaptive layer is 108dp but only the central ~72dp survives the
# launcher mask. Matches the scale previously baked into app_icon_foreground.svg.
SAFE_SCALE = 0.80
# Faint chalk-dust haze in the source plate can clear the noise floor below when
# the artwork is drawn on a smudged board rather than a clean one: m4 lifts ~16%
# of the canvas into alpha 26-49, which composites as a grey halo around the mark
# on the iOS dark/tinted layers. Telling dust from drawing by alpha *level* needs
# a hand-tuned threshold per artwork; telling it apart by *distance from a
# stroke* does not, so gate on that instead.
CORE_ALPHA = 128
CORE_REACH = 8
# macOS icons are not full bleed: Apple's grid is an 824/1024 body with
# transparent margins, and macOS applies no mask of its own.
MACOS_BODY = 824
MACOS_RADIUS = 185


def load_source() -> Image.Image:
    if not SOURCE.exists():
        sys.exit(f"missing {SOURCE.relative_to(HERE.parent.parent)}")
    im = Image.open(SOURCE).convert("RGB")
    return im if im.size == (SIZE, SIZE) else im.resize((SIZE, SIZE), Image.LANCZOS)


def estimate_background(im: Image.Image) -> tuple[int, int, int]:
    """Median of a 12px border ring: all background, no mark."""
    px, edge, band = im.load(), [], 12
    for i in range(0, SIZE, 4):
        for j in range(band):
            edge += [px[i, j], px[i, SIZE - 1 - j], px[j, i], px[SIZE - 1 - j, i]]
    mid = len(edge) // 2
    return tuple(sorted(c[k] for c in edge)[mid] for k in range(3))  # type: ignore[return-value]


def extract_alpha(im: Image.Image, bg: tuple[int, int, int]) -> Image.Image:
    """Alpha from distance travelled background -> white, per channel.

    The red channel does most of the work (bg ~40 vs white 255) but green and
    blue are included so pale-but-not-white chalk still lifts cleanly. Taking
    the per-pixel max keeps soft edges soft instead of clipping them.
    """
    alpha = None
    for chan, base in zip(im.split(), bg):
        span = 255 - base
        if span <= 0:
            continue
        lifted = ImageChops.subtract(chan, Image.new("L", im.size, base))
        scaled = lifted.point(lambda v, s=span: min(255, int(v * 255 / s)))
        alpha = scaled if alpha is None else ImageChops.lighter(alpha, scaled)

    assert alpha is not None, "background is already white; nothing to extract"

    # Gentle floor/ceiling: kill JPEG-ish noise in the plate, drive the chalk
    # body to fully opaque, leave the ramp between them untouched.
    alpha = alpha.point(lambda v: 0 if v < 26 else (255 if v > 214 else v))
    return gate_to_mark(alpha)


def gate_to_mark(alpha: Image.Image) -> Image.Image:
    """Zero any alpha more than CORE_REACH px from an unambiguous stroke.

    The soft chalk feather we want to keep hugs a stroke by definition, so
    dilating the confident core and masking with it preserves the edge while
    dropping haze that sits out in open plate. A no-op on artwork whose
    background is already clean.
    """
    core = alpha.point(lambda v: 255 if v >= CORE_ALPHA else 0)
    near = core.filter(ImageFilter.MaxFilter(2 * CORE_REACH + 1))
    return ImageChops.multiply(alpha, near)


def white_mark(alpha: Image.Image) -> Image.Image:
    mark = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 0))
    mark.putalpha(alpha)
    return mark


def on_plate(mark: Image.Image, plate: tuple[int, int, int] = BRAND) -> Image.Image:
    out = Image.new("RGB", (SIZE, SIZE), plate)
    out.paste(mark, (0, 0), mark)
    return out


def inset(img: Image.Image, scale: float) -> Image.Image:
    """Shrink about the centre, preserving canvas size and transparency."""
    side = int(SIZE * scale)
    small = img.resize((side, side), Image.LANCZOS)
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    out.paste(small, ((SIZE - side) // 2, (SIZE - side) // 2), small)
    return out


def rounded_body(mark: Image.Image) -> Image.Image:
    """macOS: brand-filled rounded square, transparent margin, mark on top."""
    out = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    off = (SIZE - MACOS_BODY) // 2

    body = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [off, off, off + MACOS_BODY - 1, off + MACOS_BODY - 1],
        radius=MACOS_RADIUS,
        fill=BRAND + (255,),
    )
    out.alpha_composite(body)

    scaled = mark.resize((MACOS_BODY, MACOS_BODY), Image.LANCZOS)
    layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    layer.paste(scaled, (off, off), scaled)

    # Clip the mark to the body so no chalk floats in the transparent margin.
    clip = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(clip).rounded_rectangle(
        [off, off, off + MACOS_BODY - 1, off + MACOS_BODY - 1],
        radius=MACOS_RADIUS,
        fill=255,
    )
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), clip))
    out.alpha_composite(layer)
    return out


def coverage(alpha: Image.Image) -> float:
    hist = alpha.histogram()
    return sum(hist[128:]) / float(SIZE * SIZE)


def main() -> None:
    src = load_source()
    bg = estimate_background(src)
    alpha = extract_alpha(src, bg)
    mark = white_mark(alpha)

    print(f"    source background : rgb{bg}  ->  plate rgb{BRAND}")
    print(f"    mark coverage     : {coverage(alpha) * 100:.1f}% of canvas")

    inset_mark = inset(mark, SAFE_SCALE)

    on_plate(mark).save(HERE / "app_icon.png")
    mark.save(HERE / "app_icon_mark.png")
    inset_mark.save(HERE / "app_icon_foreground.png")
    on_plate(inset_mark).save(HERE / "app_icon_maskable.png")
    rounded_body(mark).save(HERE / "app_icon_macos.png")

    # Verification previews. A white-on-transparent PNG is indistinguishable
    # from a blank file in most viewers, so these composite it the way the
    # platforms will.
    circle = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(circle).ellipse(
        [SIZE // 2 - 342, SIZE // 2 - 342, SIZE // 2 + 342, SIZE // 2 + 342], fill=255
    )
    squircle = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(squircle).rounded_rectangle([170, 170, 853, 853], radius=190, fill=255)

    fg_on_plate = on_plate(inset_mark).convert("RGBA")
    masks = Image.new("RGB", (SIZE * 2 + 52, SIZE), (33, 37, 41))
    for i, m in enumerate((circle, squircle)):
        tile = fg_on_plate.copy()
        tile.putalpha(m)
        masks.paste(tile, (i * (SIZE + 52), 0), tile)
    masks.save(HERE / "_mask_preview.png")

    dark = Image.new("RGB", (SIZE * 2 + 52, SIZE), (110, 110, 115))
    for i, back in enumerate(((28, 28, 30), (43, 50, 64))):
        tile = Image.new("RGB", (SIZE, SIZE), back)
        tile.paste(mark, (0, 0), mark)
        dark.paste(tile, (i * (SIZE + 52), 0))
    dark.save(HERE / "_dark_preview.png")


if __name__ == "__main__":
    main()
