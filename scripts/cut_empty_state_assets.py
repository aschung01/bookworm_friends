#!/usr/bin/env python3
"""Cut the empty-state stencils into shippable Flutter assets.

Source is `docs/mockups/empty-states/art/gen/cut/stencil/<piece>.png` at 1024px:
an alpha stencil of chalk coverage (see `alpha_from_luma.py`). This resizes each
one to its real call-site size and writes Flutter's resolution-aware variants:

    assets/icons/empty/<piece>.png        1x
    assets/icons/empty/2.0x/<piece>.png   2x
    assets/icons/empty/3.0x/<piece>.png   3x

Declaring only the 1x path in `pubspec.yaml` is enough -- Flutter discovers the
`N.0x/` siblings itself and picks by device pixel ratio. Shipping buckets rather
than one oversized file means a 40pt spot decodes ~120px, not 1024px.

Sizes come from the call sites, not from taste. `nomatch` is cut at 48 because
it appears at both 40pt (search miss) and 34pt (scan failure card).

The RGB stays the light-theme ink `#626A72` even though the app re-tints with
`BlendMode.srcIn`: if a tint is ever dropped the art still reads correctly on a
light background, whereas a white-RGB stencil would vanish.

    python3 scripts/cut_empty_state_assets.py
    python3 scripts/cut_empty_state_assets.py --check   # verify only
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SRC = REPO / "docs" / "mockups" / "empty-states" / "art" / "gen" / "cut" / "stencil"
OUT = REPO / "assets" / "icons" / "empty"

# piece -> logical size in pt, from the call site that uses it largest.
SIZES = {
    "rest": 100,  # library_view.dart      a friend's empty library
    "invite": 100,  # library_view.dart      your own empty library
    "search": 100,  # add_book_bottom_sheet  idle, nothing typed
    "note": 48,  # book_details_tab_view  Notes tab, no note
    "nomatch": 48,  # add_book_bottom_sheet 40pt + scan_book_page 34pt
    "duo": 40,  # friends_sheet.dart     no friends yet
}
SCALES = (1, 2, 3)


def dest(piece: str, scale: int) -> Path:
    return OUT / (f"{piece}.png" if scale == 1 else f"{scale}.0x/{piece}.png")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="report, write nothing")
    args = ap.parse_args()

    missing = [p for p in SIZES if not (SRC / f"{p}.png").exists()]
    if missing:
        sys.exit(
            f"missing stencil(s): {', '.join(missing)}\n"
            f"run: python3 scripts/alpha_from_luma.py"
        )

    if args.check:
        bad = []
        for piece, size in SIZES.items():
            for scale in SCALES:
                d = dest(piece, scale)
                if not d.exists():
                    bad.append(str(d.relative_to(REPO)))
        print(f"expected {len(SIZES) * len(SCALES)} files, missing {len(bad)}")
        for b in bad:
            print(f"  MISSING {b}")
        sys.exit(1 if bad else 0)

    total = 0
    for piece, size in SIZES.items():
        for scale in SCALES:
            d = dest(piece, scale)
            d.parent.mkdir(parents=True, exist_ok=True)
            px = size * scale
            subprocess.run(
                ["sips", "-Z", str(px), str(SRC / f"{piece}.png"), "--out", str(d)],
                check=True,
                capture_output=True,
            )
            total += d.stat().st_size
            print(f"  {d.relative_to(REPO)}  {px}px  {d.stat().st_size // 1024} KB")
    print(f"\n{len(SIZES) * len(SCALES)} files, {total // 1024} KB total")


if __name__ == "__main__":
    main()
