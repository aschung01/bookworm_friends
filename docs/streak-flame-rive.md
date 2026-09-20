# The streak flame, as a Rive artboard

The build sheet for `assets/rive/streak_flame.riv`. Written because **a `.riv` cannot be
authored from a terminal** — it is a binary produced by the Rive Editor, with no CLI and no
public serializer — so the file has to be built by hand, and everything a builder needs to
match is here rather than in someone's memory.

The Flutter side already exists and is wired in: `lib/ui/widgets/streak/streak_flame.dart`.
Drop the file at `assets/rive/streak_flame.riv` and it takes over; until then the celebration
draws the hand-built ignition in `streak_celebration.dart` and nothing is broken.
`test/streak_flame_test.dart` pins that.

## The three names that must match exactly

| Thing | Name |
| --- | --- |
| Asset path | `assets/rive/streak_flame.riv` |
| State machine | `Ignite` |
| Bound view-model property (Number) | `progress` |

A typo in any of them is a **silent fallback** — the app keeps working and quietly never shows
the artboard, which is the hardest failure to notice. The three are constants in
`streak_flame.dart` and asserted in `streak_flame_test.dart`.

## The contract: Flutter keeps the clock

`progress` is a Number in **0–100**, written every frame from the celebration's own
`AnimationController`. **The artboard must not autoplay.** Its timeline is scrubbed, start to
finish, by that one property.

This is the whole reason Rive is acceptable here, and it is worth understanding rather than
just implementing:

- the nine beats of the celebration stay in Dart, where they are greppable and a golden test
  can drive them, instead of moving into an editor timeline nobody can read from the repo;
- `MediaQuery.disableAnimationsOf` keeps working with no special case — the controller jumps
  to `value = 1`, `progress` becomes 100, and the artboard poses at its final frame. A
  one-shot animation would need the artboard seeked by hand;
- **nothing moves once the last beat lands**, which this screen honours on purpose. An
  artboard with an idle loop would break it, on a screen a reader opens nightly.

So: **no idle state, no looping layer, no `advance`-driven wobble.** Frame 100 is a resting
frame.

## The drawing

**A book lying with its spine running away from the viewer, and a flame rising out of it.**

Orientation, because this is the part that is easy to get backwards: the spine is along **Z**
— it runs into the screen — so the camera is at the book's **tail edge**, looking along the
spine. We see the two covers splayed left and right, the page block between them, and the
gutter as a dark seam down the middle. The flame rises along **+Y**, straight up out of that
seam.

Rive is 2D, so the depth is drawn rather than transformed: the far edge of each cover is
**narrower and higher** than the near edge, converging toward a vanishing point above centre.

### Artboard

- **304 × 304**, origin centred. The Flutter side hands it a 152pt square (`_Ignition.stageSize`)
  and asks for `Fit.contain`, so 2× gives clean scaling on a 3× screen without the artboard
  being the thing that decides the on-screen size.
- Background **transparent**. The celebration paints its own cream ground (`kCandleGlow`,
  `#FFE8C4`) and a filled artboard would sit on it as a visible panel.

### Palette — take these, do not pick new ones

Every value below is already a token in `lib/ui/widgets/library_card/card_lighting.dart` or
`lib/constants/app_theme.dart`. The app has been burned by invented brand colours before
(`docs/mockups/streaks/index.html` says so in its first comment block), so the artboard uses
the shipped ones.

| Role | Hex | Token |
| --- | --- | --- |
| Flame core | `#FFD479` | the record's lit-today highlight |
| Flame body | `#F2A93F` | `kCandleFlame` |
| Flame edge / deep | `#B54708` | `AppColors.light.flame` |
| Cover | `#26190A` | `kCandleStockTop` |
| Page block | `#FDFAF1` | the record's paper |
| Page edge lines | `#E2D9C4` | the record's `cstats` hairline |
| Glow | `#F2A93F` at 0–30% | `kCandleFlame`, alpha animated |

The flame is a **gradient**, core → body → edge, not a flat fill. That single fact is most of
what separated the hand-built version from Duolingo's.

### Layer order, back to front

1. `glow` — radial gradient, `kCandleFlame` centre to transparent. Sits behind everything.
2. `cover_far` — the underside cover, a trapezoid: wide at the bottom (near edge), narrow at
   the top (far edge).
3. `pages` — the page block, a fanned stack. 5–7 hairlines in `#E2D9C4` over `#FDFAF1`,
   splaying from the gutter.
4. `gutter` — a narrow dark wedge at centre, `#26190A`, where the flame emerges.
5. `cover_left`, `cover_right` — the two splayed covers, same trapezoid mirrored.
6. `flame_outer` — the main flame body, gradient-filled.
7. `flame_inner` — ~60% scale, core colour, **its own centre of rotation slightly below the
   outer flame's**, so it can lean independently. This is the part a font glyph could not do
   and the reason we are in Rive at all.
8. `sparks` — 12–16 small shapes, each on its own path or a bone.

## The timeline, in `progress` 0–100

One timeline, keyed against the scrub. Times are percentages of `progress`, not seconds.

| `progress` | What happens |
| --- | --- |
| 0 | Book **closed and flat**, seen end-on: covers together, no flame, no glow, no sparks. The page block is a thin closed stack. |
| 0 → 22 | **The open.** Covers rotate apart to their splayed rest. Page block fans. Ease out with a small overshoot — the covers pass their rest angle by a few degrees and settle. Nothing else yet. |
| 18 → 45 | **The ignition.** `flame_outer` scales from 0 at the gutter, `scaleY` leading `scaleX` so it *stretches up* then settles wide — the squash-and-stretch the hand-built version never had. Gradient shifts from deep edge toward the lit core over the same window. |
| 22 → 60 | `glow` rises to 30% alpha and settles back to ~16%: a flare, then a steady burn. |
| 24 → 55 | **Sparks** leave the gutter in a ~250° fan biased upward, gravity-pulled, faded to nothing by 55. They must be **gone**, not merely transparent, by the end. |
| 30 → 100 | `flame_inner` leans — two or three slow, decaying cycles of ±4° with a small vertical scale breathe, **damped to zero by 100**. This is the "settles rather than freezes" beat. Keep it decaying: a constant wobble at frame 100 is an idle loop by another name. |
| 55 → 90 | Optional **gleam**: a narrow bright diagonal band travelling across the flame. The hand-built version does this with a `ShaderMask` and it reads well at 0.15 band width / 55% white — anything wider turned the flame into paper. |
| 100 | **Resting frame.** Book open, flame lit and still, glow steady, no sparks, no gleam. |

## What to check before accepting it

The rule this repo learned on the empty-state art: *a contact sheet is not a look.* Render it
and look at these specifically.

1. **Frame 100 is genuinely still.** Scrub to 100, leave it, and confirm nothing moves. This
   is the one that will be got wrong, because an animator's instinct is to leave the flame
   alive.
2. **The covers read as depth, not as a bow tie.** If the far edges do not converge, the book
   reads as two flat triangles rather than a book seen along its spine.
3. **The flame is legible at 152pt and at 44pt.** The chip draws a flame at 18pt and the page
   hero at 44pt; this artboard is only used at 152, but if it collapses to mush when scaled
   down it is over-detailed.
4. **It does not compete with the counter.** The figure below it is the fact; the flame is the
   event. If the eye lands on the flame and stays there, the glow or the sparks are too strong.
5. **On cream, not on white.** The ground is `#FFE8C4`. A flame tuned against white will look
   washed out on it — the hand-built version's first glow was invisible for exactly this
   reason.

## Scope, deliberately

This artboard is the **increment** only. Duolingo's milestone takeovers — the fracturing egg,
the mascot in sunglasses — are character animation, and this app has no character;
`docs/mockups/empty-states/PROMPTS.md` records what producing art here costs. If a milestone
takeover is ever scoped it gets its **own** artboard and its own file, so the nightly path
stays as cheap as it is now.
