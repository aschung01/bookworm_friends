#!/usr/bin/env python3
"""Generate the burst spray and splice it into `scene.rml`.

    ../../.venv/bin/python rive/streak_flame/burst.py            # dry run, reports the diff
    ../../.venv/bin/python rive/streak_flame/burst.py --write    # apply

**Why this is generated rather than authored.** A reader's note on the first spray was that "the
shapes morph, and initial position and travel paths of each are more random", against a Duolingo
still. Both halves are hostile to hand-authoring: a person placing twelve things places them
evenly -- an even fan is precisely the tell being removed -- and twelve particles times five
keyed properties each is 120 keyframes nobody will keep consistent by hand. So the recipe lives
here, the scatter comes from a seeded RNG, and `scene.rml` holds the output.

**What the shipped spray did wrong.** All six were children of one node carrying `scaleX`/`scaleY`
0.85 -> 1.35 plus a single shared opacity envelope, so they left on the same radial line, at the
same speed, brightened at the same instant and died at the same instant; they were circles within
2 units of one size; and they sat in near-mirrored pairs (+-76, +-84, +-58). The `embers` group in
the same file already does the opposite -- per-particle `x`/`y` with staggered windows and its own
opacity -- so the burst was the odd one out rather than the file lacking a pattern.

**Morph is the parametric path, not the node's scale.** `rive schema Rectangle` marks `width`
(key 20), `height` (21) and `cornerRadiusTL` (31) animatable. Scaling the node is a *zoom*: the
corner radius scales with everything else, so a rounded square stays the same rounded square and
merely gets bigger. Keying the path turns a bar into a stub and a pill into a rounded square,
which is what the reference does.

**Three traps, all of which cost a round.**

*The group is authored `opacity="0"` and its own keys were what lifted it.* Rive multiplies a
parent's opacity into its children, so moving the reveal onto the individual bits renders an empty
frame unless the group is opened too -- and an empty frame looks exactly like a broken keyframe
table. The group is emitted without an opacity attribute here, like `embers`.

*The radii are the whole ballgame, and the first attempt took them from the old flame.* The spray
is drawn behind the silhouette on purpose -- an ember is seen only once it is clear of the flame --
and the widened body's half-width is 135 at the burst and 93 settled, where the shipped placement
sat at 76..84 against a then-101. Every bit spent its whole flight occluded.

*The bright token is too pale for bits that sit on paper.* `#FFD479` on white nearly disappears,
and unlike the old spray these are outside the flame for most of their life, so an even split left
half the spray invisible. The mix is weighted toward `#F2A93F`. A third colour is not available:
only the two bright tokens, never `flame` #B54708 -- see the note in `scene.rml`.
"""

from __future__ import annotations

import math
import random
import re
import sys
from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCENE = HERE / "scene.rml"

# **The scatter is one number, and changing it is how you get a different spray.** Recorded
# rather than left to chance so that a review can be repeated: an unseeded spray cannot be
# looked at twice, and a hand-nudged one drifts back toward regular.
SEED = 3
COUNT = 12

WARM = "FFF2A93F"
BRIGHT = "FFFFD479"

# Ids for the generated objects. Well clear of the scene's own maximum (1272) so a regenerate
# cannot collide with hand-authored geometry; `rive push` matches by id, so a change here shows
# up as deletes plus creates rather than as updates.
ID_BASE = 2000

# The artboard is 360 wide, so its edge is 180 from the flame's centre line, and the settled
# silhouette's half-width is 93. That band -- 93 to 180 -- is the entire visible field, and the
# ceiling below leaves room for a bit's own size.
RADIUS = (100.0, 165.0)

# `0:204`, the scene's ease-out. A bit is thrown clear and then slowed by drag; constant-speed
# travel is one of the things that reads as mechanical.
EASE = "0:204"


# `Ignite`'s duration, in frames. Every bit has to be dead by here.
#
# **This is the trap that shipped once: three bits were left frozen in midair in the idle state.**
# Rive holds a keyed property at its *last* keyframe's value for every frame after it -- the same
# fact the `embers` note in `scene.rml` relies on deliberately -- so a bit whose death frame lands
# past the end of the timeline never reaches opacity 0. Frame 78 leaves it mid-flight and
# mid-fade, and `Idle` does not key the spray at all, so it sits there for as long as the screen
# is up. Authoring the shapes at `opacity="0"` does not save it either: the authored value only
# applies where nothing has keyed the property, and `Ignite` has.
#
# The first recipe drew `birth` from 56..68 and `life` from 10..20 independently, so a death at 88
# was reachable and three of twelve bits exceeded 78. Drawing `life` first and then bounding
# `birth` by it makes that unrepresentable rather than unlikely.
LAST_FRAME = 78


@dataclass
class Bit:
    x: float
    y: float
    dx: float
    dy: float
    w0: float
    h0: float
    w1: float
    h1: float
    r0: float
    r1: float
    rot0: float
    rot1: float
    birth: int
    life: int
    colour: str
    peak: float


def spray(seed: int = SEED, count: int = COUNT) -> list[Bit]:
    rng = random.Random(seed)
    bits: list[Bit] = []
    for i in range(count):
        # **Two families, because the visible room is two shapes.** The flame fills the middle of
        # the frame, so a bit reads either beside it or above its tip. The reference has both:
        # most of its particles flank the flame and a couple clear the top.
        #
        # The side alternates rather than being drawn -- otherwise a twelve-bit spray comes out
        # seven-to-five by luck and the asymmetry reads as a mistake instead of as scatter.
        # Everything else is drawn.
        above = rng.random() < 0.25
        side = 1 if i % 2 else -1
        if above:
            x = side * rng.uniform(8, 66)
            y = -rng.uniform(188, 214)
        else:
            radius = rng.uniform(*RADIUS)
            elev = rng.uniform(-0.10, 0.85)
            x = side * math.cos(elev) * radius
            y = -math.sin(elev) * radius - rng.uniform(0, 18)

        long_side = rng.uniform(5.5, 10.5)
        short_side = long_side * rng.uniform(0.34, 0.85)
        bar = rng.random() < 0.45
        w0, h0 = (long_side, short_side) if bar else (short_side, long_side)
        # The morph: the sides swap most of the way and shrink, so a bit cools rather than
        # simply fading -- a shape that only loses alpha reads as a ghost.
        w1, h1 = h0 * rng.uniform(0.7, 1.15), w0 * rng.uniform(0.4, 0.8)
        life = rng.randrange(10, 21)
        bit = Bit(
            x=x,
            y=y,
            # Small outward travel, bigger rise. There are only about 15 units between the
            # outer radius and the artboard edge, so a bit that flies outward leaves the frame;
            # up is where the room is, and up is also what buoyant embers do.
            dx=(1 if x > 0 else -1) * rng.uniform(2, 12),
            dy=-rng.uniform(22, 54),
            w0=w0,
            h0=h0,
            w1=w1,
            h1=h1,
            r0=min(w0, h0) * rng.uniform(0.3, 0.5),
            r1=min(w1, h1) * rng.uniform(0.2, 0.5),
            rot0=rng.uniform(0, math.tau),
            rot1=0.0,
            # **Lifetime first, then birth bounded by it**, so a death cannot land past
            # [LAST_FRAME]. See the note there: the other order strands bits in the idle state.
            birth=0,
            life=life,
            colour=WARM if rng.random() < 0.62 else BRIGHT,
            peak=rng.uniform(0.82, 1.0),
        )
        bit.birth = rng.randrange(56, LAST_FRAME - life + 1)
        # A spin, and a modest one: a bit tumbling a full turn in a fifth of a second reads as a
        # propeller rather than as debris.
        bit.rot1 = bit.rot0 + rng.uniform(-1.4, 1.4)
        bits.append(bit)
    # Not a comment but a guard: the failure it prevents is invisible in `Ignite` and only shows
    # up once the sequence has landed, which is the hardest place to notice it.
    late = [b for b in bits if b.birth + b.life > LAST_FRAME]
    assert not late, f"{len(late)} bits outlive Ignite and would freeze in the idle state"
    return bits


class Ids:
    def __init__(self, base: int) -> None:
        self.n = base

    def __call__(self) -> str:
        self.n += 1
        return f"0:{self.n}"


def shapes_xml(bits: list[Bit], ids: Ids) -> tuple[str, list[tuple[str, str]]]:
    out: list[str] = []
    pairs: list[tuple[str, str]] = []
    for b in bits:
        sid, pid = ids(), ids()
        pairs.append((sid, pid))
        out.append(
            f'                <Shape x="{b.x:.2f}" y="{b.y:.2f}"'
            f' rotation="{b.rot0:.4f}" opacity="0" id="{sid}">'
            f'<Rectangle width="{b.w0:.2f}" height="{b.h0:.2f}"'
            f' cornerRadiusTL="{b.r0:.2f}" name="Path" id="{pid}"/>\n'
            f'                    <Fill name="Fill" id="{ids()}">'
            f'<SolidColor colorValue="{b.colour}" name="C" id="{ids()}"/></Fill></Shape>'
        )
    return "\n".join(out), pairs


def keyed(object_id: str, props: list[tuple[int, list[tuple[int, float]], str]], ids: Ids) -> str:
    out = [f'            <KeyedObject objectId="{object_id}" id="{ids()}">']
    for key, frames, interp in props:
        out.append(f'                <KeyedProperty propertyKey="{key}" id="{ids()}">')
        for i, (f, v) in enumerate(frames):
            last = i == len(frames) - 1
            if last:
                tail = ""
            elif interp == "linear":
                tail = ' interpolationType="linear"'
            else:
                tail = f' interpolationType="cubic" interpolatorId="{EASE}"'
            out.append(
                f'                    <KeyFrameDouble frame="{f}" value="{v:.4f}"'
                f'{tail} id="{ids()}"/>'
            )
        out.append("                </KeyedProperty>")
    out.append("            </KeyedObject>")
    return "\n".join(out)


def keys_xml(bits: list[Bit], pairs: list[tuple[str, str]], ids: Ids) -> str:
    out = []
    for b, (sid, pid) in zip(bits, pairs):
        end = b.birth + b.life
        lit = b.birth + max(1, round(b.life * 0.22))
        out.append(
            keyed(
                sid,
                [
                    (13, [(b.birth, b.x), (end, b.x + b.dx)], "cubic"),
                    (14, [(b.birth, b.y), (end, b.y + b.dy)], "cubic"),
                    (15, [(b.birth, b.rot0), (end, b.rot1)], "cubic"),
                    (18, [(b.birth, 0.0), (lit, b.peak), (end, 0.0)], "linear"),
                ],
                ids,
            )
        )
        out.append(
            keyed(
                pid,
                [
                    (20, [(b.birth, b.w0), (end, b.w1)], "cubic"),
                    (21, [(b.birth, b.h0), (end, b.h1)], "cubic"),
                    (31, [(b.birth, b.r0), (end, b.r1)], "cubic"),
                ],
                ids,
            )
        )
    return "\n".join(out)


GROUP = re.compile(
    r'(            <Node y="-48"(?: opacity="0")? name="burst" id="0:21">\n)(.*?)(            </Node>\n)',
    re.S,
)
# The original hand-authored group envelope, present only before the first run.
GROUP_KEYS = re.compile(
    r'            <KeyedObject objectId="0:21" id="0:798">.*?</KeyedObject>\n', re.S
)
# One of this script's own `KeyedObject`s, from any previous run.
#
# **Four digits, not `0:2\d+`, and the loose version did real damage.** `0:2\d+` also matches
# `0:20` -- the `fire` node -- along with `0:21`, `0:23`, `0:24` and `0:25`, so the first
# idempotent run deleted the flame's own strain, tremor, gleam, core lick and squash keys along
# with the spray's. It reported "keyed objects 37 -> 24" and wrote a scene that still built and
# still verified clean; only a diff against a copy taken beforehand caught it. [ID_BASE] is 2000
# precisely so the generator's ids are four digits and cannot alias a hand-authored two-digit one.
OWN_KEYS = re.compile(
    r'            <KeyedObject objectId="0:2\d{3}"[^>]*>.*?</KeyedObject>\n', re.S
)


def replace_keys(text: str, keys: str) -> tuple[str, int]:
    """Swap whatever is currently keying the spray for `keys`.

    **Idempotence is the whole point of this function, and the first version did not have it.**
    It anchored on `objectId="0:21" id="0:798"`, the group envelope -- which this script deletes
    on its first run, so the second run asserted `burst keys not found` and could not regenerate.
    A generator that only works once is a one-off edit wearing a script's clothes.
    """
    m = GROUP_KEYS.search(text)
    if m:
        return text[: m.start()] + keys + "\n" + text[m.end() :], 1
    spans = [(m.start(), m.end()) for m in OWN_KEYS.finditer(text)]
    assert spans, "neither the original group envelope nor any previous output was found"
    # Emitted as one contiguous run, so removing from the last back to the first and inserting
    # at the first keeps every other block's offsets valid.
    out = text
    for a, b in reversed(spans):
        out = out[:a] + out[b:]
    return out[: spans[0][0]] + keys + "\n" + out[spans[0][0] :], len(spans)


def main(argv: list[str]) -> int:
    bits = spray()
    ids = Ids(ID_BASE)
    text = SCENE.read_text()

    shapes, pairs = shapes_xml(bits, ids)
    m = GROUP.search(text)
    assert m, "burst group not found"
    old_shapes = m.group(2)
    # No `opacity="0"` on the group: the reveal is per bit now.
    group = (
        '            <Node y="-48" name="burst" id="0:21">\n' + shapes + "\n" + m.group(3)
    )
    text = text[: m.start()] + group + text[m.end() :]

    keys = keys_xml(bits, pairs, ids)
    text, replaced = replace_keys(text, keys)

    print(f"seed {SEED}, {len(bits)} bits")
    above = sum(1 for b in bits if b.y < -180)
    print(f"  {above} above the tip, {len(bits) - above} flanking")
    print(f"  births frame {min(b.birth for b in bits)}..{max(b.birth for b in bits)}, "
          f"lives {min(b.life for b in bits)}..{max(b.life for b in bits)}")
    print(f"  |x| {min(abs(b.x) for b in bits):.0f}..{max(abs(b.x) for b in bits):.0f} "
          f"(silhouette half-width 93 settled, 135 at the burst; artboard edge 180)")
    print(f"  shapes {old_shapes.count('<Shape') } -> {shapes.count('<Shape')}, "
          f"keyed objects {replaced} -> {keys.count('<KeyedObject')}")

    if "--write" in argv:
        SCENE.write_text(text)
        print(f"\nwrote {SCENE}")
    else:
        print("\n(dry run — pass --write to apply)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
