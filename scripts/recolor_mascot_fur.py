#!/usr/bin/env python3
"""Recolour the mascot's fur in an already-rendered cut-out, locally.

Why this exists rather than a generation round: fur colour is the *only* thing
under test, and re-prompting the model changes the drawing as well as the
palette -- there is no seed, so two runs differ in pose, crop and expression.
That makes a colour comparison unreadable. Recolouring the shipped cut-outs
instead holds the drawing byte-identical and varies one axis, which is the whole
point of a comparison sheet. It is also free.

What makes it safe: the renders are flat-shaded and the fur is *neutral*. Sampled
across m03-reading, every fur pixel has a max-min channel spread of 0-8, while the
apricot (nose, inner ears, jelly) sits at 104 and is trivially excluded by chroma.
So the fur is separable from the rest of the palette without any hand-drawn mask.

The mapping is by LIGHTNESS rather than by nearest-colour, which is what keeps the
antialiased edges clean. Classifying each pixel into one of three flat greys would
quantise every boundary pixel to one side and leave a visible stair; interpolating
a continuous lightness ramp instead reproduces the original's own soft edges. The
three anchors are the character's three fur greys:

    ears and tail   #A4A4A6   mean 165   the darkest fur
    body and limbs  #D6D2D1   mean 210
    belly, eye whites #ECE8E5 mean 232   the lightest

Eyes and mouth (#54575B, mean 87) sit far below the darkest fur, so a lightness
floor excludes them without touching the fur. Anything outside the anchors is
clamped, not extrapolated -- extrapolation sent the odd stray highlight pixel
out of gamut and it showed up as confetti.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ModuleNotFoundError:  # pragma: no cover - environment guard
    sys.exit("Pillow is required: .venv/bin/python -m pip install Pillow")

# The character's own three fur greys, as lightness anchors. See module docstring.
EARS_L, BODY_L, BELLY_L = 165.0, 210.3, 232.3

# Below this mean-RGB the pixel is eye or mouth, not fur. The gap between the
# eyes (87) and the darkest fur (165) is wide, so the exact value is not delicate.
FUR_FLOOR = 125.0
# Above this max-min channel spread the pixel is the apricot, not fur. The
# apricot measures 104 and fur measures 0-8, so again there is room either side.
FUR_CHROMA_MAX = 45


def _hex(value: str) -> tuple[int, int, int]:
    value = value.lstrip("#")
    if len(value) != 6:
        raise ValueError(f"not a 6-digit hex colour: {value}")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16))


def _lerp(
    a: tuple[int, int, int], b: tuple[int, int, int], t: float
) -> tuple[int, int, int]:
    return (
        round(a[0] + (b[0] - a[0]) * t),
        round(a[1] + (b[1] - a[1]) * t),
        round(a[2] + (b[2] - a[2]) * t),
    )


class FurRamp:
    """A candidate fur, as the three colours the character already has.

    Given in the same order as the anchors: the ears/tail shadow, the body, and
    the belly highlight. Keeping all three means a candidate can change hue
    without flattening the drawing's internal value structure -- which is what
    happened the first time this was tried with a single body colour, and the
    result read as a paper cut-out rather than as an animal.
    """

    def __init__(self, ears: str, body: str, belly: str) -> None:
        self.ears = _hex(ears)
        self.body = _hex(body)
        self.belly = _hex(belly)

    def at(self, lightness: float) -> tuple[int, int, int]:
        if lightness <= EARS_L:
            return self.ears
        if lightness >= BELLY_L:
            return self.belly
        if lightness <= BODY_L:
            t = (lightness - EARS_L) / (BODY_L - EARS_L)
            return _lerp(self.ears, self.body, t)
        t = (lightness - BODY_L) / (BELLY_L - BODY_L)
        return _lerp(self.body, self.belly, t)

    def lut(self) -> list[tuple[int, int, int]]:
        """One entry per possible mean-RGB value, so the hot loop is a lookup."""
        return [self.at(float(i)) for i in range(256)]


# The candidates. Each holds the original's value structure and moves only hue and
# chroma, except `charcoal` and `white`, which deliberately move lightness too --
# those two exist to test whether the *value* of the fur matters more than its hue
# once the widget grounds span cream to deep red.
CANDIDATES: dict[str, tuple[str, FurRamp]] = {
    "grey": (
        "Grey \u2014 current, the control",
        FurRamp("#A4A4A6", "#D6D2D1", "#ECE8E5"),
    ),
    "cream": (
        "Cream \u2014 the candle family",
        FurRamp("#D9C9A8", "#F0E4CB", "#FBF4E6"),
    ),
    "apricot": (
        "Apricot \u2014 collapses into the nose colour",
        FurRamp("#E09A6E", "#F4C3A2", "#FBE4D4"),
    ),
    "ginger": (
        "Ginger \u2014 the obvious reading cat",
        FurRamp("#C9803F", "#E8A867", "#F7DCB8"),
    ),
    "chocolate": (
        "Chocolate \u2014 leather and paper",
        FurRamp("#6E5545", "#9A7C66", "#C9AE96"),
    ),
    "bluegrey": (
        "Blue grey \u2014 cooler than current",
        FurRamp("#8E9AA6", "#BCC7D2", "#E2E9F0"),
    ),
    "sage": (
        "Sage \u2014 nudged toward the brand green",
        FurRamp("#9AA79E", "#C9D2C8", "#E8EDE6"),
    ),
    "charcoal": (
        "Charcoal \u2014 a dark cat (value test)",
        FurRamp("#4A4E55", "#6E737C", "#9AA0A8"),
    ),
    "white": (
        "White \u2014 a pale cat (value test)",
        FurRamp("#C8C4C0", "#E8E4E0", "#FAF8F6"),
    ),
    # --- Derived, after measuring the nine above -------------------------------
    # The measurement said the choice is *value*, not hue: only `charcoal` and
    # `chocolate` keep the belly and the apricot as real features, and only those
    # two clear 3:1 against the candle cream and the recorded glow. Every pale
    # candidate reads by hue alone on a light ground, which is the reading that
    # does not survive small size, dim light or colour-vision deficiency.
    #
    # So these three take the *hue* question and ask it again at the value that
    # works -- body lightness held near 120-128 mean, matching charcoal and
    # chocolate -- rather than making the choice a choice between one warm dark
    # and one cool dark.
    "taupe": (
        "Taupe \u2014 warm dark, between the two",
        FurRamp("#5A4F48", "#8A7B71", "#BCAEA4"),
    ),
    "slate": (
        "Slate \u2014 cool dark, a deep Russian Blue",
        FurRamp("#444E5A", "#6F7D8A", "#A3AFBA"),
    ),
    "moss": (
        "Moss \u2014 sage taken to a working value",
        FurRamp("#4C554A", "#78826F", "#AEB6A4"),
    ),
    # --- The one the record already nominates ----------------------------------
    # CHARACTER.md is explicit that the grey is provisional: "the body hue is light
    # warm grey while form is being judged without brand colour interfering. Brand
    # green #09BC8A is parked; one early test showed a green body with the off-white
    # belly and apricot jelly does work, so the swap should be mechanical."
    #
    # Measured, the parked choice does NOT hold up, and it is worth recording why the
    # obvious arithmetic misleads. #09BC8A has a mean RGB of 112, which sits right
    # beside charcoal's 116 -- so by that reading it is already the working value.
    # But luminance is not the mean: green carries a 0.7152 coefficient against
    # red's 0.2126 and blue's 0.0722, and #09BC8A is 188 green. Perceptually it is a
    # *light* colour, and it measures 2.16:1 at worst against the app's own grounds
    # and 1.01:1 against the `stages` yellow -- the single worst saturated result of
    # any candidate here. The apricot nose also drops to 1.34:1 on it.
    #
    # None of which makes the swap wrong, but "mechanical" is not true: the early
    # test it cites predates both the dark lamp ground and the saturated ramp.
    "brand": (
        "Brand green \u2014 the parked choice, at full strength",
        FurRamp("#067657", "#09BC8A", "#CFEFE2"),
    ),
    "brandmuted": (
        "Brand green, muted \u2014 an animal rather than a logo",
        FurRamp("#3F7D6B", "#6FA695", "#C3DDD3"),
    ),
    # ===========================================================================
    # ROUND 2. The first fifteen were all low-chroma and narrow-spread, and they
    # read as tasteful mud. Two axes were never varied:
    #
    #   CHROMA -- every candidate above is desaturated. The reference's palette is
    #     not; a mascot meant to hold a home screen probably should not be either.
    #   INTERNAL SPREAD -- the gap between the ears/tail, the body and the belly
    #     stayed roughly where the render put it. Widening it is *point colouring*,
    #     and the character already has darker ears and a darker tail, so the
    #     structure exists and was simply not being used. It also gets visual
    #     interest without adding markings, which the identity rules forbid.
    #
    # The 3:1 contrast floor that produced the mud has also been relaxed. The cat is
    # decoration -- the run and the flame carry the information -- so the real bar is
    # "does not disappear", around 2:1, not a text-grade ratio.
    # ---------------------------------------------------------------------------
    # A. Saturated, at a body value that still works.
    "teal": (
        "Teal \u2014 deep petrol, not a cat colour and the better for it",
        FurRamp("#14565F", "#2A8A94", "#BFE3E3"),
    ),
    "terracotta": (
        "Terracotta \u2014 warm clay",
        FurRamp("#8A3E2A", "#C06A4A", "#F0CDB8"),
    ),
    "plum": (
        "Plum \u2014 aubergine, the reference's Beetle taken serious",
        FurRamp("#4A2F52", "#7B5285", "#D8C4DD"),
    ),
    "mustard": (
        "Mustard \u2014 deep ochre",
        FurRamp("#8A6512", "#C29A28", "#F0E0B0"),
    ),
    "indigo": (
        "Indigo \u2014 deep blue-violet",
        FurRamp("#2B3168", "#4E57A0", "#C6CAE8"),
    ),
    "rust": (
        "Rust \u2014 deep red-brown",
        FurRamp("#7A3320", "#A85A3A", "#E6C4AE"),
    ),
    # B. Wide internal spread -- dark points, bright belly. Real cat genetics,
    #    and the lever with the most effect per unit of risk.
    "tuxedo": (
        "Tuxedo \u2014 near-black with a bright belly (widest spread)",
        FurRamp("#1E2024", "#33373D", "#F2EEE9"),
    ),
    "smoke": (
        "Smoke \u2014 grey, but with the gaps opened right up",
        FurRamp("#3A3F46", "#7A828C", "#EDEFF2"),
    ),
    "sealpoint": (
        "Seal point \u2014 Siamese, dark ears and tail",
        FurRamp("#3A2A22", "#8A7361", "#EFE4D6"),
    ),
    "bluepoint": (
        "Blue point \u2014 pale body, slate points",
        FurRamp("#33404D", "#8794A1", "#E8EDF2"),
    ),
    # C. Both levers at once: saturated AND wide.
    "tealpoint": (
        "Teal point \u2014 saturated and wide",
        FurRamp("#0E3F47", "#3E9AA3", "#E2F4F2"),
    ),
    "gingerpoint": (
        "Ginger point \u2014 the classic cat, done with contrast",
        FurRamp("#8A4418", "#D98A45", "#F9E7CC"),
    ),
    "orchid": (
        "Orchid \u2014 saturated mauve, wide spread",
        FurRamp("#3E2148", "#8E5C9E", "#EEDCF2"),
    ),
    # ===========================================================================
    # ROUND 3 -- THE CHOSEN DIRECTION.
    #
    # The reference sheet settled this. Duo is green in all fourteen tiles; Duolingo
    # never varies the mascot's colour. What makes him pop is HUE OPPOSITION against
    # a ladder that stays on the purple -> magenta -> red side of the wheel, plus a
    # radial glow behind him. So the ramp and the fur are one decision, and the
    # `stages` ramp was rebuilt to that arc -- blue and yellow dropped -- at which
    # point green becomes the right answer rather than a brand-loyalty argument.
    #
    # Measured against the new arc, these hold 90-99 degrees of hue separation at
    # worst and 140-173 at the pink and red end. The shipped grey holds 12 degrees at
    # worst -- it is the same hue as the crimson tile -- and has 0.06 chroma, so hue
    # separation cannot help it at all. That is the whole reason it looked dead.
    #
    # All three keep the wide spread round 2 proved matters: a dark green ear and
    # tail, the body, and a near-white belly.
    "brandpoint": (
        "Brand green, wide spread \u2014 the record's own #09BC8A",
        FurRamp("#046B4E", "#09BC8A", "#EAF9F2"),
    ),
    "forestpoint": (
        "Forest \u2014 calmer green, best luminance of the three",
        FurRamp("#17503C", "#2E8B6B", "#DCEFE6"),
    ),
    "jadepoint": (
        "Jade \u2014 between the two, slightly cooler",
        FurRamp("#0B5F55", "#1E9E86", "#E2F5F0"),
    ),
}


# Above this mean-RGB a pixel is either the belly or an eye white -- the two roles
# CHARACTER.md groups under one colour. They have to be separated here even so; see
# protected_regions().
LIGHT_FLOOR = 225.0
# A light region smaller than this fraction of the largest one is an eye white, not
# the belly. The belly is an order of magnitude bigger than an eye in every pose in
# the set, so the threshold is not delicate -- measured, the ratio is about 0.06.
EYE_AREA_RATIO = 0.25


def protected_regions(src: Image.Image) -> set[int]:
    """Pixel offsets of light regions that must NOT take the fur colour.

    The reason this exists: CHARACTER.md lists "Belly and eye whites" as a single
    palette entry, so a naive lightness remap tints both. That is faithful to the
    table and wrong on the screen -- a brand-green cat came back with pale mint eye
    whites, which reads as an illness rather than as a colourway, and it was
    degrading the green candidate in the comparison sheet for a reason that had
    nothing to do with the colour being judged.

    Belly and eye whites are never connected (one is on the torso, the others are
    inside the eyes), and the belly is far larger, so flood-filling the light mask
    and keeping everything except the biggest component isolates the eyes without
    needing a hand-painted mask or a per-pose rule.
    """
    src = src.convert("RGBA")
    width, height = src.size
    raw = src.tobytes()
    light = bytearray(width * height)
    for p in range(width * height):
        i = p * 4
        if raw[i + 3] == 0:
            continue
        if (raw[i] + raw[i + 1] + raw[i + 2]) / 3.0 >= LIGHT_FLOOR:
            light[p] = 1

    seen = bytearray(width * height)
    regions: list[list[int]] = []
    for start in range(width * height):
        if not light[start] or seen[start]:
            continue
        stack = [start]
        seen[start] = 1
        region: list[int] = []
        while stack:
            p = stack.pop()
            region.append(p)
            x, y = p % width, p // width
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < width and 0 <= ny < height:
                    q = ny * width + nx
                    if light[q] and not seen[q]:
                        seen[q] = 1
                        stack.append(q)
        regions.append(region)

    if not regions:
        return set()
    regions.sort(key=len, reverse=True)
    biggest = len(regions[0])
    protected: set[int] = set()
    for region in regions[1:]:
        if len(region) <= biggest * EYE_AREA_RATIO:
            protected.update(region)
    return protected


def recolour(src: Image.Image, ramp: FurRamp) -> Image.Image:
    """Remap fur pixels through `ramp`, leaving apricot, eyes and alpha alone.

    Works on the raw RGBA buffer rather than through per-pixel accessors: it is
    faster on a 631x806 render and, unlike `getdata`, is not deprecated.
    """
    src = src.convert("RGBA")
    keep = protected_regions(src)
    raw = bytearray(src.tobytes())
    lut = ramp.lut()
    for p in range(len(raw) // 4):
        i = p * 4
        if raw[i + 3] == 0 or p in keep:
            continue
        r, g, b = raw[i], raw[i + 1], raw[i + 2]
        if max(r, g, b) - min(r, g, b) > FUR_CHROMA_MAX:
            continue  # the apricot
        mean = (r + g + b) / 3.0
        if mean < FUR_FLOOR:
            continue  # eyes and mouth
        raw[i], raw[i + 1], raw[i + 2] = lut[round(mean)]
    return Image.frombytes("RGBA", src.size, bytes(raw))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("sources", nargs="+", type=Path, help="cut-out PNGs to recolour")
    ap.add_argument("--fur", required=True, choices=sorted(CANDIDATES), help="candidate")
    ap.add_argument("--out-dir", type=Path, required=True)
    args = ap.parse_args()

    label, ramp = CANDIDATES[args.fur]
    args.out_dir.mkdir(parents=True, exist_ok=True)
    for path in args.sources:
        dest = args.out_dir / f"{path.stem}-{args.fur}.png"
        recolour(Image.open(path), ramp).save(dest)
        print(f"{dest}  <- {label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
