#!/usr/bin/env python3
"""Render a review sheet of the keyed-out empty-state art, at real sizes.

The art has to be judged two ways at once: large, where the chalk grain either
reads as hand-drawn or as a smudge, and at the size it actually ships at (34pt
to 100pt), where composition either survives or collapses into a blob. So each
piece gets one big cell plus a row of chips at its call-site size.

It also has to be judged on the backgrounds it will really sit on, which is the
whole point of keying the plate out: `pageBackground` #F8F9FA, the mint sheet
#EFF5EF, and the dark page #121212. A cutout that looks clean on white can show
a grey halo on mint.

Light (`paper`) and dark (`night`) sets render side by side, so a piece whose
two surfaces disagree in weight is obvious.

    python3 scripts/contact_sheet.py                  # both surfaces
    python3 scripts/contact_sheet.py --surface paper  # one

Writes cut/sheet.svg and, if rsvg-convert is present, cut/sheet.png. Note
rsvg-convert cannot render JPEG inside <image href>, which is why this only
ever points at the keyed PNGs in cut/.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CUT = REPO / "docs" / "mockups" / "empty-states" / "art" / "gen" / "cut"

# Ship size in pt per piece, from the call sites. `rest`/`invite`/`search` are
# the full-page states; the rest are inline and much smaller.
SIZES = {"rest": 100, "invite": 100, "search": 100, "nomatch": 40, "note": 48, "duo": 40}
PAGE, MINT, DARK = "#F8F9FA", "#EFF5EF", "#121212"

CELL, PAD, GUT = 210, 16, 22
COLS = 3

# `secondaryText` per theme, from lib/constants/app_theme.dart. The stencils are
# tinted to these at render time rather than baked, which is the whole claim the
# stencil mode is here to test.
INK = {"light": "#626A72", "dark": "#949599"}


def find(piece: str, surface: str) -> Path | None:
    """The keyed PNG for a piece, whichever variant was accepted."""
    hits = sorted(CUT.glob(f"{piece}-grok-{surface}-v*.png"))
    return hits[0] if hits else None


def esc(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;")


def tint_filters() -> str:
    """feFlood+feComposite tints an alpha stencil, the SVG equivalent of srcIn."""
    return "<defs>" + "".join(
        f'<filter id="ink-{k}" x="0" y="0" width="100%" height="100%">'
        f'<feFlood flood-color="{v}" result="f"/>'
        f'<feComposite in="f" in2="SourceAlpha" operator="in"/></filter>'
        for k, v in INK.items()
    ) + "</defs>"


def stencil_cell(x: int, y: int, piece: str, src: str) -> tuple[list[str], int]:
    """One stencil shown big on both themes, then at ship size on all three bgs.

    Same file every time -- only the tint and the background change. If a piece
    reads on one row and not the other, the single-asset approach is wrong.
    """
    half = (CELL - 8) // 2
    o = [
        f'<text x="{x}" y="{y + 11}" font-family="Menlo" font-size="10" '
        f'fill="#626A72">{esc(piece)} · {SIZES[piece]}pt · one stencil, tinted</text>',
        f'<rect x="{x}" y="{y + 18}" width="{half}" height="{half}" rx="8" fill="{PAGE}"/>',
        f'<image x="{x + 10}" y="{y + 28}" width="{half - 20}" height="{half - 20}" '
        f'href="{src}" filter="url(#ink-light)"/>',
        f'<rect x="{x + half + 8}" y="{y + 18}" width="{half}" height="{half}" rx="8" fill="{DARK}"/>',
        f'<image x="{x + half + 18}" y="{y + 28}" width="{half - 20}" height="{half - 20}" '
        f'href="{src}" filter="url(#ink-dark)"/>',
    ]
    cx, cy = x, y + 18 + half + 8
    size = SIZES[piece]
    box = size + 12
    # At 100pt three chips are wider than the cell, so wrap instead of letting
    # the last one run under the neighbouring column and get clipped.
    rows = 1
    for bg, ink in ((PAGE, "light"), (MINT, "light"), (DARK, "dark")):
        if cx > x and cx + box > x + CELL:
            cx = x
            cy += box + 8
            rows += 1
        o += [
            f'<rect x="{cx}" y="{cy}" width="{box}" height="{box}" rx="5" fill="{bg}"/>',
            f'<image x="{cx + 6}" y="{cy + 6}" width="{size}" height="{size}" '
            f'href="{src}" filter="url(#ink-{ink})"/>',
        ]
        cx += box + 10
    return o, 18 + half + 8 + rows * (box + 8)


def cell(x: int, y: int, piece: str, surface: str, src: str) -> tuple[list[str], int]:
    """One piece: label, big preview, then chips at ship size on each surface."""
    dark = surface == "night"
    big_bg = DARK if dark else PAGE
    # On the dark set the mint sheet is irrelevant, so show the dark page twice
    # at different sizes instead of inventing a background the app never uses.
    chips = [(DARK, SIZES[piece]), (DARK, 34)] if dark else [(PAGE, SIZES[piece]), (MINT, SIZES[piece])]
    o = [
        f'<text x="{x}" y="{y + 11}" font-family="Menlo" font-size="10" '
        f'fill="#626A72">{esc(piece)} · {SIZES[piece]}pt · {surface}</text>',
        f'<rect x="{x}" y="{y + 18}" width="{CELL}" height="{CELL}" rx="8" fill="{big_bg}"/>',
        f'<image x="{x + PAD}" y="{y + 18 + PAD}" width="{CELL - 2 * PAD}" '
        f'height="{CELL - 2 * PAD}" href="{src}"/>',
    ]
    cx, cy = x, y + 18 + CELL + 8
    for bg, size in chips:
        box = size + 12
        o += [
            f'<rect x="{cx}" y="{cy}" width="{box}" height="{box}" rx="5" fill="{bg}"/>',
            f'<image x="{cx + 6}" y="{cy + 6}" width="{size}" height="{size}" href="{src}"/>',
        ]
        cx += box + 10
    return o, 18 + CELL + 8 + max(s for _, s in chips) + 12


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--surface",
        choices=["paper", "night", "both", "stencil"],
        default="both",
        help="stencil: the alpha stencils from alpha_from_luma.py, one file per "
        "piece, tinted per theme",
    )
    ap.add_argument("--out", default="sheet")
    args = ap.parse_args()

    if args.surface == "stencil":
        stencil_sheet(args.out)
        return

    surfaces = ["paper", "night"] if args.surface == "both" else [args.surface]
    body: list[str] = []
    y = 12
    missing: list[str] = []

    for surface in surfaces:
        body.append(
            f'<text x="12" y="{y + 12}" font-family="Menlo" font-size="13" '
            f'fill="#121212">surface: {surface}</text>'
        )
        y += 26
        row_h = 0
        for i, piece in enumerate(SIZES):
            src = find(piece, surface)
            if src is None:
                missing.append(f"{piece}/{surface}")
                continue
            col = i % COLS
            x = 12 + col * (CELL + GUT)
            o, h = cell(x, y, piece, surface, src.name)
            body += o
            row_h = max(row_h, h)
            if col == COLS - 1:
                y += row_h + GUT
                row_h = 0
        if row_h:
            y += row_h + GUT

    w = 12 + COLS * (CELL + GUT)
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{y}">'
        f'<rect width="{w}" height="{y}" fill="#ffffff"/>' + "".join(body) + "</svg>"
    )
    svg_path = CUT / f"{args.out}.svg"
    svg_path.write_text(svg)
    print(f"wrote {svg_path.relative_to(REPO)}")

    if missing:
        print("missing: " + ", ".join(missing))
    if shutil.which("rsvg-convert"):
        png = CUT / f"{args.out}.png"
        subprocess.run(
            ["rsvg-convert", "-o", str(png), str(svg_path)], check=True, cwd=CUT
        )
        print(f"wrote {png.relative_to(REPO)}")
    else:
        print("rsvg-convert not found; SVG only")


def stencil_sheet(out: str) -> None:
    body: list[str] = [tint_filters()]
    y, row_h, missing = 12, 0, []
    for i, piece in enumerate(SIZES):
        src = CUT / "stencil" / f"{piece}.png"
        if not src.exists():
            missing.append(piece)
            continue
        col = i % COLS
        o, h = stencil_cell(12 + col * (CELL + GUT), y, piece, f"stencil/{piece}.png")
        body += o
        row_h = max(row_h, h)
        if col == COLS - 1:
            y += row_h + GUT
            row_h = 0
    if row_h:
        y += row_h + GUT

    w = 12 + COLS * (CELL + GUT)
    svg_path = CUT / f"{out}.svg"
    svg_path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{y}">'
        f'<rect width="{w}" height="{y}" fill="#ffffff"/>' + "".join(body) + "</svg>"
    )
    print(f"wrote {svg_path.relative_to(REPO)}")
    if missing:
        print("missing stencils: " + ", ".join(missing))
    if shutil.which("rsvg-convert"):
        png = CUT / f"{out}.png"
        subprocess.run(["rsvg-convert", "-o", str(png), str(svg_path)], check=True, cwd=CUT)
        print(f"wrote {png.relative_to(REPO)}")


if __name__ == "__main__":
    main()
