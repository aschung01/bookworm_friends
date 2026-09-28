# The sign-in hero's mascot

`m03-reading` — the cat holding an open book — seated on the bottom edge of
`AuthPage` and cropped by it. This file records the choices; the character itself is
owned by `docs/mockups/mascot/CHARACTER.md`.

## Why the cat is a sibling of the lockup, not a replacement for it

The obvious change is to swap `BrandMark` for the mascot, and it is wrong. Two
documented decisions collide here and the arrangement satisfies both:

- **`CHARACTER.md`, Deliberate non-goals:** "The launcher icon is not the mascot. It
  stays the chalk book." And separately, the mascot "lives in the six streak moments
  plus **the auth hero**" — so this screen was always an intended home.
- **`brand_mark.dart`:** the plate "is also what the reader just tapped on their home
  screen, so the sign-in screen and the launcher are the same object."

Duolingo gets to ignore this because *their launcher icon is their mascot*: Duo's face
is the app icon, so their welcome screen draws identity and character with one object.
Ours are deliberately split, so it takes two — and stacking them inside the centred
lockup is the failure `auth_page.dart` already warns about for the mark and the
wordmark ("under a solid plate the same gap reads as two unrelated objects"). Giving
the cat its own zone at the foot of the screen is what keeps them from competing.

## The contrast figure for this is a trap, and it cost a round

The fur is a neutral grey (`#D6D2D1` body, `#ECE8E5` belly). Against light
`pageBackground` `#F8F9FA` those measure **1.42:1** and **1.14:1**, and the first
conclusion drawn from them was that the cat would be a ghost on this screen and would
need a dark plate behind it. **That is false, and it was settled by rendering it.**

A drawing's legibility is not its largest fill's contrast. The silhouette is bounded
by the ears and tail at `#A4A4A6` (**2.36:1**), the eyes and mouth carry `#54575B`
(**~8.7:1**), the nose and inner ears are apricot, and the eye closes an edge the body
fill never draws. The belly is the genuinely weak region and reads as a soft pale mass
rather than a hole — and in this pose it is behind the book anyway.

This is the same error `CHARACTER.md` already records one level up, where ranking fur
candidates by WCAG contrast produced "the mud". The figure is not useless: it is what
still rules out `brand` `#09BC8A` as a ground at **1.63:1**, because a mid-lightness
saturated ground under a neutral cat is exactly the widget's original defect.

Two grounds were built and rejected on looking (`scripts/_auth_cat_proof.py` renders
both):

| variant | why not |
| --- | --- |
| `brandFill` `#067657` band across the foot | halves the screen, reads as a footer, and sets a second *darker* green against the mint plate above — two objects, one identity |
| radial glow, `kCandleFlame` or `brandFill` | imperceptible at this size |

## The asset

Cut from **`m03-reading-widget-v3`**, which is the master the widget shipped —
confirmed by cutting all three variants at `--width 720` and diffing against
`docs/mockups/streak-widget/cats/m03-reading.png`: v3 came back byte-identical, v1 and
v2 differ in size. So sign-in and the home screen draw one character rather than two
samples of one prompt.

```bash
# 1. Re-cut the master at a size with headroom (the shipped widget cut is 631x806,
#    which is only just enough for 3x at 265pt).
.venv/bin/python scripts/cut_mascot_bg.py --dest /tmp/m03master --width 1400 \
  m03-reading-widget-v3
# 2. Downscale to 1x/2x/3x at the design height. Aspect follows the cut (0.7825).
#    -> assets/mascot/{,2.0x/,3.0x/}m03-reading.png  at 207x265, 414x530, 621x795
```

**The widget's own cut-outs are not reusable here.** They top out at 260×333
(`m03-reading@3x` in `ios/StreakWidget/Assets.xcassets`), sized for a 158pt tile — a
third of what a 265pt hero needs.

**Not quantised, deliberately.** 64 colours takes the 3x from 167KB to 18KB, a 9×
win, and puts dark fringing on every antialiased edge plus mottling across the ears:
`Image.quantize` treats alpha as a fourth dimension, and the measured max alpha shift
is 54/255. `scripts/_quant_check.py` renders the comparison. At 300KB for three
variants this is 3% of what `assets/` already weighs, against 6.9MB of fonts.

## The size, and where the clamp actually binds

`kAuthMascotHeight` is **132.5 — exactly half the 265 this first shipped at.** At 265
the cat filled all 230pt an iPhone 15 leaves under the buttons and read as a second
subject competing with the lockup; halved, it reads as a detail at the foot of the
screen, which is the register a greeting wants.

On-screen height is still *solved* from the room left under the lockup rather than
fixed, but **the clamp no longer binds on any phone the app supports**:

| surface | room under the buttons | mascot |
| --- | --- | --- |
| iPhone 15 (393×852) | ~230pt | 132.5 — the full size |
| iPhone SE (375×667) | ~173pt | 132.5 — the full size |
| 375×500 | 84pt | ~100, clamped |
| 375×380 | 24pt | withheld, past the floor |

So the clamp is now a guard for landscape, split view and any surface under ~555pt
tall, not for the SE. That is why `auth_hero_test.dart` exercises shrinking and hiding
at **explicit short sizes rather than on a phone** — sizing those cases by the SE would
make them pass because the branch never runs, which is the class of test this repo keeps
catching. On a surface with no view padding the room is `H / 2 - 166`, the lockup being
300 and centred.

At 265 the binding case was the SE, and the reason the height was computed at all was
that a constant tall enough for the large phone put the cat's ears through `Continue
with Google` on the small one. That is no longer live, and the arithmetic is kept
because it is what makes the size safe to change again.

`_kLockupHeight` sums the `Column`'s own children so the lockup's bottom edge can be
*computed*: measuring it with a `GlobalKey` would only be available on the next frame,
so the mascot would visibly pop between two sizes after the screen appeared.

**The 3x asset is now oversized by 2x** — it carries pixels to 521pt, so roughly 210KB
of the 300KB is headroom. Deliberate while the size is still being tuned; re-run the two
commands above with a 132.5 design height to reclaim it.

`kAuthMascotCrop` is 0.16, the widget's arrangement — "the mascot's feet are never
drawn". A cat fully inside the frame reads as a sticker laid on the page; one the edge
cuts reads as behind it. The overhang is what produces the crop: `Stack` clips to its
own bounds, so no `ClipRect` is involved, and the offset is a `Transform` because
`EdgeInsets` asserts it is non-negative.

## Which pose, and what it costs

All eight widget poses were rendered in place (`scripts/_auth_cat_proof.py` writes
`build/auth_cat/_poses.png`). The bottom four are the escalation ladder — `m07-drowsy`
and `m06-snooze` are the at-risk and dormant tiles, `m12-panic` is the 23:00 one,
`m05-puddle` the collapsed one — and a dozing or panicking cat is the wrong thing to
greet a stranger with. `m15-smug` has the right raised paw and a half-lidded look that
reads as smug, with sparkles claiming an achievement that has not happened.

That leaves `m01-flex`, `m13-blush` and this one. The two rejected are both *warmer*:
a raised paw at the moment of arrival reads as a wave, which is what a welcome wants,
and `m13-blush` is the warmest of the three by a distance. `m03-reading` was chosen
instead because it is the only one that says what the app is for, and because it is the
one pose whose book covers the belly.

**The cost: every pose is already spoken for as a streak state**, so this one also
means *reading* on the home screen. That is the mildest of the eight collisions and it
is still a collision. If it grates, a ninth pose is one `core_edit()` run — `r03-wave`
exists under `docs/mockups/mascot/art/` as a review render and was never promoted to a
cut-out.

## Checks

```bash
flutter test test/auth_hero_test.dart              # the assertions
flutter test test/auth_hero_render_preview.dart    # -> build/auth_preview/, and LOOK
.venv/bin/python scripts/_auth_cat_proof.py        # grounds and all eight poses
```

The preview is separate from `sign_in_button_render_preview.dart` for a structural
reason, not tidiness: that file cannot draw a raster. Its own note says so — an
`Image.asset` needs longer than its async window to resolve, which is why `BrandMark`
comes out there as a bare green plate. `precacheImage` inside `runAsync` is the missing
piece, and with it both the cat and the chalk book appear.

It also renders **one case per `testWidgets`**. Rendering four from a single case drew
the wordmark in the right weight on the first shot and a lighter one on the other
three, because repeated `pumpWidget` calls reuse a warm font cache — a preview that
misreports the screen is worse than no preview. `sign_in_button_render_preview.dart`
has the same latent issue and has not been changed here.
