#!/usr/bin/env python3
"""Pick a ground ramp that suits a NEUTRAL cat. Throwaway.

The fur is going to be one of the four greys, which changes what the ramp owes the
character. A chromatic cat separates by hue, so the old arc had to stay on one side of
the colour wheel to leave it a complement. A neutral cat has no hue to oppose with --
its only weapon is lightness -- so the wheel constraint is void and a LIGHTNESS floor
replaces it.

That also names what was wrong with the current arc: saturated magenta, pink and red at
mid-to-high lightness sit in the same value band as a grey cat, so the cat goes muddy on
exactly the hours that matter. Being colourful was never the problem; being colourful at
the cat's own lightness was.

So all three candidates below stay chromatic -- the hue ladder still carries the
escalation -- but move DEEP, so a mid or pale neutral reads as the light thing in a dark
room at every hour. Recorded stays kCandleGlow, which now buys a much stronger inversion
than it did against the mid-tone arc.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from _fur_sheets import contrast, hexr, lum
from recolor_mascot_fur import CANDIDATES

INK_LIGHT = "#FFF7EA"
INK_DARK = "#212529"
DONE = ("#FFFDF8", "#FFE8C4")  # kCandleGlow, unchanged and on-palette
GREYS = ["grey", "smoke", "bluepoint", "tuxedo"]
HOURS = list(range(7, 24))


def rgbs(c) -> str:
    return "#" + "".join("%02x" % max(0, min(255, round(v))) for v in c)


def mix(a: str, b: str, t: float) -> str:
    x, y = hexr(a), hexr(b)
    return rgbs([v + (y[i] - v) * t for i, v in enumerate(x)])


def sat(h: str) -> float:
    c = hexr(h)
    hi, lo = max(c), min(c)
    return 0.0 if hi == 0 else (hi - lo) / hi


def ramp_at(anchors, hour):
    if hour <= anchors[0][0]:
        return anchors[0][1], anchors[0][2]
    for i in range(len(anchors) - 1):
        h0, t0, b0 = anchors[i]
        h1, t1, b1 = anchors[i + 1]
        if h0 <= hour <= h1:
            t = 0 if h1 == h0 else (hour - h0) / (h1 - h0)
            return mix(t0, t1, t), mix(b0, b1, t)
    z = anchors[-1]
    return z[1], z[2]


def ground_vars(top: str, bottom: str):
    mid = mix(top, bottom, 0.5)
    ink = (
        INK_LIGHT
        if contrast(hexr(INK_LIGHT), hexr(mid)) >= contrast(hexr(INK_DARK), hexr(mid))
        else INK_DARK
    )
    dim = mix(ink, mid, 0.42)
    t = 0.42
    while t > 0 and contrast(hexr(dim), hexr(mid)) < 3.2:
        t -= 0.06
        dim = mix(ink, mid, max(0, t - 0.06))
    return mid, ink, dim


CANDIDATE_RAMPS = {
    # Dark jewel tones, cool to warm. Never leaves the dark end, so a neutral cat is
    # the light thing in the room at every hour. The hue ladder still escalates:
    # slate -> indigo -> violet -> plum -> deep rose -> burgundy.
    "dusk": [
        (7, "#3E4A5C", "#2A3340"),
        (11, "#3A4270", "#262C4E"),
        (14, "#4A3A70", "#31254E"),
        (18, "#5A3060", "#3D1C42"),
        (21, "#6B2640", "#47142A"),
        (23, "#6E1A20", "#3F0A10"),
    ],
    # The same ladder one stop lighter and more saturated -- more obviously "colourful",
    # which is closer to the original brief, at the cost of closing on the cat's value.
    "jewel": [
        (7, "#55688A", "#3A4760"),
        (11, "#525DA0", "#363E6E"),
        (14, "#6A4FA0", "#46356E"),
        (18, "#83438A", "#572C5C"),
        (21, "#9C3459", "#68203A"),
        (23, "#A02128", "#5E0F14"),
    ],
    # Cool dusk warming into the app's OWN candle darks at the deadline: the last
    # anchors sit beside kCandleWell #35230E and kCandleStock #26190A, so the
    # escalation ends somewhere the codebase already is, and the amber flame lands on
    # its own ground rather than on an invented one.
    #
    # v1 of this failed two assertions -- open saturation bottomed out at 0.197 and the
    # inversion gap fell to 0.068 -- because the cool-to-warm crossing went straight
    # through a neutral. Fixed by routing it through a saturated violet and maroon
    # instead, with an extra anchor so the transition never passes near grey.
    "ember": [
        (7, "#46566B", "#2F3B4A"),
        (11, "#414F6B", "#2A3348"),
        (14, "#574566", "#392C45"),
        (17, "#6E3A4E", "#482334"),
        (20, "#8A4420", "#5A2A12"),
        (23, "#6B2410", "#35230E"),
    ],
}


def report(name: str, anchors) -> None:
    print("=" * 74)
    print(f"{name}")
    print("=" * 74)
    band, dimfail, sats, lums = [], [], [], []
    for h in HOURS:
        top, bottom = ramp_at(anchors, h)
        mid, ink, dim = ground_vars(top, bottom)
        ci = contrast(hexr(ink), hexr(mid))
        cd = contrast(hexr(dim), hexr(mid))
        sats.append(sat(mid))
        lums.append(lum(hexr(mid)))
        if ci < 4.5:
            band.append(h)
        if cd < 3.2:
            dimfail.append(h)
    distinct = len({("".join(ramp_at(anchors, h))).lower() for h in HOURS})
    dmid = mix(*DONE, 0.5)
    print(f"  distinct hours   {distinct}/17")
    print(f"  band hours       {band or 'none'}  -> band flag {bool(band)}")
    print(f"  dim failures     {dimfail or 'none'}")
    print(f"  open saturation  min {min(sats):.3f}   (verify needs > 0.30)")
    print(f"  open luminance   max {max(lums):.4f}  (dark = a neutral cat reads)")
    print(f"  recorded sat     {sat(dmid):.3f}   inversion gap {min(sats) - sat(dmid):.3f}")
    print(f"  recorded paler   {lum(hexr(dmid)) > max(lums)}")
    print()
    print(f"    {'fur':<11}" + "".join(f"{h:>7}" for h in HOURS[::3]) + f"{'WORST':>8}")
    for key in GREYS:
        r = CANDIDATES[key][1]
        tones = [r.ears, r.body, r.belly]
        vals = []
        for h in HOURS:
            top, bottom = ramp_at(anchors, h)
            mid = mix(top, bottom, 0.5)
            vals.append(max(contrast(t, hexr(mid)) for t in tones))
        shown = vals[::3]
        print(f"    {key:<11}" + "".join(f"{v:7.2f}" for v in shown) + f"{min(vals):8.2f}")
    print()


def main() -> int:
    for name, anchors in CANDIDATE_RAMPS.items():
        report(name, anchors)

    print("For reference, the SAME four furs against the old mid-tone arc:")
    current = [
        (7, "#BFA8F2", "#9E7EE4"), (11, "#D8A3FF", "#A855F7"), (14, "#E58BE0", "#C755C2"),
        (18, "#FF8AC7", "#FF5EAE"), (21, "#FF6B6B", "#FF4B4B"), (23, "#E0242E", "#8E0B15"),
    ]
    for key in GREYS:
        r = CANDIDATES[key][1]
        tones = [r.ears, r.body, r.belly]
        worsts = []
        for h in HOURS:
            top, bottom = ramp_at(current, h)
            mid = hexr(mix(top, bottom, 0.5))
            worsts.append(max(contrast(t, mid) for t in tones))
        print(f"    {key:<11} worst {min(worsts):.2f}")
    return 0


# Guarded, because the sheet scripts import CANDIDATE_RAMPS from here and should not
# have to read a measurement report to do it.
if __name__ == "__main__":
    raise SystemExit(main())
