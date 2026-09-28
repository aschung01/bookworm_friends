# Libstack mascot — character identity

The default context image is **`REFERENCE.png`** in this directory. It is the
single source of truth for how the cat looks. Judge new art against that file,
not against prose, and not against anything under `art/` with a round letter in
its name.

The canonical prompt that produces it is `CORE` in `scripts/gen_mascot_art.py`,
built from `CORE_INTRO + core_form() + CORE_PALETTE + CORE_STYLE`. To regenerate
the reference itself:

```bash
XAI_API_KEY=... .venv/bin/python scripts/gen_mascot_art.py \
  --style eyes3 --only k09-duoratio --variants 1 --resolution 2k --aspect 3:4
```

`--resolution 2k` is not optional — 1k was the single biggest quality defect in
early rounds, and it returns JPEG instead of PNG. `--aspect 4:5` is rejected by
the API; `3:4` is the nearest portrait it accepts.

## Always pass BOTH the prompt and the reference image

The prompt alone is not enough, and this is easy to get wrong because the script
quietly defaults to text-only. Without `--reference`, `route = "generations"`,
`body["images"]` is never set, and every pose is an independent sample with
nothing anchoring its geometry — which is how eye scale wanders across a set and
how a render silently loses the off-white in its eyes.

```bash
XAI_API_KEY=... .venv/bin/python scripts/gen_mascot_art.py \
  --style core --only r01-sit r03-wave --variants 1 \
  --resolution 2k --aspect 3:4 \
  --reference docs/mockups/mascot/REFERENCE.png
```

Confirm the log says `route=edits`. Two costs to know: the edits route is
**$0.09/image instead of $0.06** (it bills for the input image as well as the
output), and `data_url()` downscales the reference to **512px**, so it anchors
geometry and colour but not fine detail.

Passing the reference fixed two standing defects outright — the stray apricot pad
that kept getting stamped onto the belly of the curled/sleeping pose, and the ears
that refused to fold flat on the slumped pose. Both had survived several rounds of
prompt rewording; context fixed what words could not.

There is **no `seed` parameter** on this model, so runs vary by design and an
identical prompt drifts. Vendor guidance is to generate 2–3 and compare, which is
what `--variants` is for. Consistency has to come from the reference image, never
from a seed.

Also: **single-image edits follow the _input_ aspect ratio**, so `--aspect` is
likely ignored on the edits route. It has only ever matched by luck, because
`REFERENCE.png` is already 3:4.

Probably the best lever still unexplored: **multi-image editing takes up to 3
source images** (the Imagine overview says 5 — unverified, the editing pages say 3) using `<IMAGE_0>` / `<IMAGE_1>` syntax, and "character reference consistency"
is a named supported use case. Passing the character reference _and_ a pose
reference together should beat having to choose between locked identity and free
pose. The script already sends `body["images"]` as a list, so this is a small
change.

One unused knob: `quality` accepts `low` or `medium` (default `medium`) on
`grok-imagine-image-2.0`. We have never set it.

**Write edit prompts as an instruction, not a scene description.** Per xAI's docs
(Imagine → Image Editing) every official edit example is a short imperative, e.g.
_"Render this as a pencil sketch with detailed shading"_. Vendor guidance is that
re-describing the whole image "invites the model to regenerate it and lose the
source", and that you must **name what stays** — without a preservation clause the
model treats the whole frame as open to modification. Aurora also renders
sequentially, so the **first 20–30 words carry the most weight** and a key
instruction in the last sentence arrives late.

`CORE` violates all three as an edit prompt: it is 2165 characters that re-describe
a character the model can already see, with the pose in the final 25 words and no
preservation clause. Use `core_edit(change, keep_eyes=...)` and the `edit` style
instead, which front-loads the change, names what stays, and runs about a third
the length. Poses that deliberately change the eyes or ears pass
`keep_eyes=False`, so the preservation clause stops contradicting the change.

Negations are "often ignored" per the same guidance, which is worth remembering
before adding another `no ...` clause to `CORE`.

**Known edit-route defect: the mouth opens and a pink tongue appears.** One of
three `cheer` edits came back with an open mouth filled rose-pink — a sixth colour
outside the palette. The mouth is supposed to stay a fine darker curved line, so
name it in the preservation clause for any high-energy pose.

**Two claims to be careful about, both of which I got wrong from thumbnails:** the
edits route did _not_ drag a two-arms-up cheer back into the reference's one-arm
wave — it rendered the cheer correctly. Judge poses from the full-size PNG, never
from a contact sheet cell; at 330px a raised arm and a waving arm are
indistinguishable.

A mascot is recognisable because a few marks never change, not because the
drawing is always the same. So this file is split into marks that are
**load-bearing** and everything else, which is free.

## Load-bearing — never negotiable

1. **One rounded mass, no neck.** A large round head sitting directly on a soft
   egg-shaped body that is widest near the base. Head about as wide as the body.
2. **Connected, body-toned limbs.** Arms and feet are the _same grey as the body_
   and join smoothly onto it. Never detached, never floating. This is what makes
   the character poseable without redrawing it.
3. **Capsule eyes with a top-left twinkle.** Two tall off-white capsules, each
   holding a charcoal pupil that fills only the **upper half**, so a broad sweep
   of off-white shows below it. The twinkle is a rounded **notch bitten out of
   the pupil's top-left corner** — not a white dot laid on top. Always top-left,
   in every pose.
4. **The paw rule.** Underside facing the viewer or pointing up → the **jelly**:
   exactly four apricot circles, one larger centre pad with three smaller toe
   pads above. Planted on the ground or seen from above → **no jelly at all**,
   only two short darker slits. Both states may appear in one drawing, and
   `REFERENCE.png` deliberately shows both.
5. **Tri-point apricot.** Apricot appears in exactly three places: the nose, the
   inner ears, and the jelly pads. Nowhere else. Every round where it was left
   unconstrained it grew into ginger fur patches.
6. **Single-tone spiral tail.** One smooth tapering sweep in a flat darker grey,
   curling into a spiral. No differently coloured tip.

## Explicitly forbidden

- **No whiskers.** Tried and dropped.
- **No crown stripes, forehead marks, or body markings** of any kind.
- **No eye mask.** An early round used a goggle-like off-white patch joining both
  eyes; it was rejected as an _owl_ solution — owls have a facial disc, cats do
  not — and because it echoed Duo too directly.
- **No chest mark.** The three stacked book-page lines from the same early round
  are gone.
- **No outlines, gradients, shading or texture.** Flat solid fills only.
- **No props, clothing or text.** The word "library" in a prompt summons books,
  mortarboards and glasses even when props are forbidden — don't use it.

## Free by design

Pose, expression and state. That is the whole point of items 1 and 2 above.

## Palette — five flat colours

| Role                         | Hex       |
| ---------------------------- | --------- |
| Body and limbs               | `#D6D2D1` |
| Belly and eye whites         | `#ECE8E5` |
| Ears and tail                | `#A4A4A6` |
| Nose, inner ears, jelly pads | `#F9AF87` |
| Eyes and mouth               | `#54575B` |

Sampled off the render, not eyeballed. Note that generated output drifts a few
percent off these between renders, so treat the table as authoritative and the
PNG as indicative.

### The fur is a neutral grey, it is decided, and it shipped

**This section read "The fur colour is STILL UNDECIDED" until 2026-09-27, and that was
wrong in both halves — the decision and the reasoning behind it.** The grey in the table
above is not provisional: it ships in the eight widget cut-outs under
`ios/StreakWidget/Assets.xcassets`, and `2026-09-22-streak-widget-design.md` records the
cat art as final (Open question 7).

What settled it was not grey winning a comparison. It is that **the ground was rebuilt
around the grey rather than the reverse** — see _"The fur is a neutral grey"_ in that
spec. Against the first ramp the four grey candidates scored 2.0–3.9:1; every hour of
the ladder was darkened, the same four then scored 5.9–8.3:1, and the cat became the
light thing in a lit room at every hour. A chromatic fur was the premise the ramp had
been drawn for, and it was the ramp that gave way.

`#09BC8A` is still not the decision, and the note explaining why is kept: an earlier
pass of this file recorded brand green as chosen on the strength of a one-word answer to
a question about the widget's ramp. That reading was wrong then and the reversal stands.
Green lost to grey, not to nothing.

**Points 2 and 3 of the old analysis are reversed, and they are kept because a later
reader was misled by them.** They argued that hue opposition is what makes a mascot pop,
that luminance is "the wrong instrument here", and that WCAG contrast "misled once
already" by recommending a muted taupe. That is right for a _chromatic_ cat and wrong
for this one. `verify.py` in `docs/mockups/streak-widget/` voided the wheel constraint
explicitly rather than deleting it, and states the replacement in one line: **a neutral
cat has no hue to oppose with, so its only weapon is lightness.** The widget spec puts
the same finding the other way round — _"being colourful was never the problem; being
colourful at the cat's own lightness was"_. So luminance separation from the ground is
now the primary instrument, not the discredited one, and the ≥60°-complement assertion
that used to be cited here no longer exists.

The losing argument is worth keeping because its observation about Duo is still true —
Duo is green in all fourteen tiles and the _ground_ is what varies. It just does not
generalise to a neutral character, which separates on value or not at all.

**Point 1 survives and is still unbanked.** Spread beats hue: widening the ears-to-belly
step is point colouring, and the structure is already there in the darker ears and tail.
The recommendation was roughly a **4:1 internal step**; the shipped palette measures
**2.07:1** (`#A4A4A6` against `#ECE8E5`), so it was never taken. The dark ground solved
figure-against-ground, which is what made the grey viable, but it says nothing about
internal modelling — so "the cat reads flat up close" is still a live complaint with a
known fix, and `scripts/recolor_mascot_fur.py` is still the tool for it.

**The grey survives a light ground, and the arithmetic that says otherwise is measuring
the wrong thing.** Every shipped tile is dark, so the cut-outs had never been drawn on
`pageBackground` until the auth-hero round. Against light `#F8F9FA` the body `#D6D2D1`
is **1.42:1** and the belly `#ECE8E5` is **1.14:1**, and an earlier pass of this section
concluded from exactly those two figures that "the cat is a ghost" and that the auth hero
would need a dark plate. **Rendered, that is false** — see `scripts/_auth_cat_proof.py`
and `build/auth_cat/`, where the cat reads cleanly on the bare page at 265pt in all four
poses tried.

The error is instructive because it is the same one point 3 above records, one level
further in. A drawing's legibility is not its largest fill's contrast: the silhouette is
bounded by the ears and tail at `#A4A4A6` (**2.36:1**), the eyes and mouth carry
`#54575B` (**~8.7:1**), the nose and inner ears are apricot, and the eye completes an
edge the body's own fill never draws. The belly is the genuinely weak region and it reads
as a soft pale mass rather than as a hole. In `m03-reading` it is hidden behind the book
entirely.

So a filled plate is an aesthetic option here, not a requirement — and the two that were
tried both lost on looking: a `brandFill` band halves the screen and sets a second,
darker green against `BrandMark`'s mint plate, and a glow behind the character (in either
`kCandleFlame` or `brandFill`) is imperceptible at this size. **`brand` `#09BC8A` is
still ruled out as a ground** at 1.63:1 on the body, which is the one place the naive
figure does bite: a mid-lightness saturated ground is the widget's original defect.

**Two things the recolour pipeline exposed, both still open.** The eye whites share a
palette entry with the belly, so a naive lightness remap tints them — a coloured cat came
back with tinted eye whites, which reads as illness. `recolor_mascot_fur.py` flood-fills
the light mask and protects every region except the largest, isolating the eyes without a
hand-painted mask; but any future _native_ render needs the eye whites specified
separately from the belly, or the same bug returns at generation time. And the book in
`m03-reading` is drawn in the same neutral greys as the fur, so it recolours along with
the animal — the prop needs its own palette entry. Both still matter with the fur
settled, because point 1 above would go through the same pipeline.

## Expression states

The escalation axis is **awake → asleep**, per
`docs/superpowers/specs/2026-09-12-reading-streaks-design.md`: amber and never
red, no guilt copy, and a broken streak prints _the record, not a zero_. We are
not copying Duo's hellfire end of the matrix.

Useful finding: a **drowsy** face falls out of changing nothing but the eye —
flatten the capsule's top edge and drop the pupil low, and the same character
reads half-asleep. That is how `at-risk` and `freeze` should be drawn, rather
than as bespoke poses.

## Prompt-craft rules that are load-bearing

These were expensive to learn; ignoring them regresses the output.

- **Name shapes, don't grade them.** This model discriminates on geometry words,
  not degree. "Capsule", "rounded rectangle", "lozenge", "half-moon" all land.
  "Large" vs "very large" produces identical eyes, and **numeric ratios are
  ignored** — "twice as tall as wide" came back near-square.
- **Say "top-left of that _pupil_"**, not "top-left corner". The explicit version
  landed 6/6; the vague one drifted to top-right in 2 of 5.
- **Loose beats precise.** Over-specification collapses variation — 20
  over-constrained prompts returned one pose 20 times.
- **3–5 negations, no more.** Long negative lists fail ("NOT a spoon" returned
  three spoons), but dropping them is also bad — removing "no text" made a
  subject write **BEST BOOK**.
- **Long prompts silently drop late instructions.** Put anything critical early.
- **`front-facing` in the intro fights every off-axis pose.** It is the likely
  cause of the walk pose growing a leg out of the belly. Strip it for profile,
  from-behind and rolled-over poses.
- **Describe emotion mechanically.** "Slumped and deflated" produced plain
  sitting; "shoulders dropped, ears folded flat, eyes cast down" worked.
- **Never seed generation with Duo or any third-party mascot.** The edit route
  copies the seed's geometry, so an owl reference returns an owl — off-brief and
  a trademark exposure for a shipping App Store app. Describe the style in words.
  Seeding with our own output is the IP-clean equivalent.

## Generator notes

Grok (`grok-imagine-image-2.0`, via `scripts/gen_mascot_art.py`) is the chosen
generator at $0.06/image. Gemini was evaluated head-to-head on five poses and
**lost**: Gemini 3 Pro and Gemini 3.1 Flash both held limb attachment and the
palette better, but broke the _identity_ rules — inverted the paw rule, drew
interior contour lines, scrambled a face, sprayed stray slit marks. Grok breaks
anatomy instead, which is a per-image reroll rather than a spec violation. Also
worth knowing: Gemini 3 **Pro** beat the newer Gemini 3.1 **Flash** here, so tier
mattered more than generation.

## Deliberate non-goals

- **The launcher icon is not the mascot.** It stays the chalk book
  (`macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png`). The
  mascot lives in the six streak moments plus the auth hero.
- **No flame glyph.** The streak glyph is an ink stamp; a milestone earns a wax
  seal.
- **Chalk texture is not the mascot's style.** It was tried; it drifts
  dimensional (soft volume, drop shadows, a felted look) and true monochrome
  chalk destroys both the twinkle and the apricot. Flat vector wins.
