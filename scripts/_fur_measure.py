#!/usr/bin/env python3
"""Measure the fur candidates. Throwaway alongside _fur_sheets.py.

Two questions, and they are separate:

1. INTERNAL legibility -- does the character still read as a face and an animal?
   The belly, the apricot nose/inner-ears/jelly and the eyes are all fixed colours
   that sit *on* the body, so if the body drifts toward any of them that feature
   stops existing. This has nothing to do with the widget and cannot be fixed by
   choosing a different ground.

2. EXTERNAL legibility -- does the silhouette survive the ground it is drawn on?
   Reported separately for the three grounds the app actually owns (the candle
   cream, the recorded glow, the dark lamp) and for the four saturated ones the
   `stages` ramp introduces, because those two sets give opposite answers and
   averaging them would hide that.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _fur_sheets import GROUNDS, contrast, hexr
from recolor_mascot_fur import CANDIDATES, _hex

APRICOT = _hex("#F9AF87")  # nose, inner ears, jelly pads
EYES = _hex("#54575B")
FLAME = _hex("#F2A93F")  # kCandleFlame -- the one brand mark on the tile

NATIVE = {"cream", "mint", "lamp"}


def main() -> int:
    native = [(n.splitlines()[0], h) for n, h in GROUNDS if n.splitlines()[0] in NATIVE]
    loud = [(n.splitlines()[0], h) for n, h in GROUNDS if n.splitlines()[0] not in NATIVE]

    print("1. INTERNAL -- features sitting on the body. Independent of any ground.")
    print("   (a feature below ~1.5:1 has stopped being a feature)\n")
    print(f"   {'':<11}{'belly':>8}{'nose':>8}{'eyes':>8}{'vs flame':>10}")
    for key, (_, ramp) in sorted(CANDIDATES.items()):
        print(
            f"   {key:<11}"
            f"{contrast(ramp.body, ramp.belly):8.2f}"
            f"{contrast(ramp.body, APRICOT):8.2f}"
            f"{contrast(ramp.body, EYES):8.2f}"
            f"{contrast(ramp.body, FLAME):10.2f}"
        )

    print("\n2. EXTERNAL -- the silhouette against the ground.\n")
    head = "   " + f"{'':<11}" + "".join(f"{n:>8}" for n, _ in native) + f"{'worst':>8}"
    head += "   |" + "".join(f"{n:>8}" for n, _ in loud) + f"{'worst':>8}"
    print(head)
    ranked = []
    for key, (_, ramp) in sorted(CANDIDATES.items()):
        nv = [contrast(ramp.body, hexr(h)) for _, h in native]
        lv = [contrast(ramp.body, hexr(h)) for _, h in loud]
        ranked.append((min(nv), min(lv), key))
        print(
            f"   {key:<11}"
            + "".join(f"{v:8.2f}" for v in nv)
            + f"{min(nv):8.2f}"
            + "   |"
            + "".join(f"{v:8.2f}" for v in lv)
            + f"{min(lv):8.2f}"
        )

    print("\n3. RANKED by worst case on the grounds the app actually owns:\n")
    for nv, lv, key in sorted(ranked, reverse=True):
        note = "" if nv >= 3.0 else "   <-- below 3:1 somewhere"
        print(f"   {key:<11} native {nv:5.2f}   saturated {lv:5.2f}{note}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
