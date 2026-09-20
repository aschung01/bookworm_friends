# The streak flame, as a Rive artboard

How `assets/rive/streak_flame.riv` is authored, built and judged.

**This file used to be a build sheet addressed to a human with the Rive Editor**, on the stated
premise that "a `.riv` cannot be authored from a terminal — it is a binary produced by the Rive
Editor, with no CLI and no public serializer". That was false. There is a first-party CLI,
`rive`, and it compiles a directory of plain text into a `.riv`. The premise is recorded rather
than deleted because it shaped the design of the Flutter side, which still assumes the artboard
may be missing — and that assumption turned out to be worth keeping for an unrelated reason
(see [Which flame you get](#which-flame-you-get-depends-on-the-machine)).

So: **`rive/streak_flame/scene.rml` is the source and the `.riv` is a build artifact.** That is
what voids the original objection to Rive — that a binary blob is un-greppable and
un-reviewable. A geometry change is a diff.

```bash
./rive/streak_flame/build.sh                        # verify, inspect, build, install
../../.venv/bin/python rive/streak_flame/smooth.py  # cubic handles and striations, to paste
../../.venv/bin/python rive/streak_flame/sheet.py   # Ignite, sampled across its 900ms
../../.venv/bin/python rive/streak_flame/motion.py  # the Idle loop, and a GIF of all of it
```

Both outputs are committed: the `.riv` because `flutter build` cannot run the CLI and a missing
asset degrades silently, and the RML because it is the source. Edit the RML, run the script,
commit both.

## The three names that must match exactly

| Thing            | Name                           |
| ---------------- | ------------------------------ |
| Asset path       | `assets/rive/streak_flame.riv` |
| One-shot         | `Ignite`                       |
| Looping timeline | `Idle`                         |

A typo in any of them is a **silent fallback** — `animationNamed` returns null, the painter poses
nothing, and the artboard sits on its authored rest frame, which is a book lying open with a
flame already on it and looks entirely deliberate. They are constants in `streak_flame.dart`,
asserted in `streak_flame_test.dart`, and — because constants agreeing with each other proves
nothing about the binary — that test also greps the built `.riv` for both names. It reads the
bytes rather than the runtime, so unlike the rest of the file it holds on every machine.

**These replaced a state machine called `Ignite` and a bound Number called `progress`.** See
[Who owns the motion](#who-owns-the-motion-and-why-that-changed).

## The contract: Flutter keeps the clock, the timeline keeps the shape

`StreakFlame` takes two drives and pushes them into a `BasicArtboardPainter`:

| drive      | what it does                                                                |
| ---------- | --------------------------------------------------------------------------- |
| `progress` | **seeks** `Ignite` — `animation.time = progress * duration`, then `apply()` |
| `liveness` | **mixes** `Idle` — `advance(dt)`, then `apply(mix: liveness)`               |

`progress` is **linear** and spans exactly the timeline's own 900ms. That is the whole point of
the arrangement: the host decides _how far through_ the sequence is, and the artboard decides
what the sequence _looks like_.

Two consequences fall out of who owns the clock, and both are the reason Rive was acceptable:

- the beats of the celebration stay in Dart, where they are greppable and a test can drive them,
  instead of moving into an editor timeline nobody can read from the repo;
- `MediaQuery.disableAnimationsOf` keeps working with almost no special case — the controller
  jumps to `value = 1`, `progress` becomes 1, and the artboard poses at its final frame.

The exception is `liveness`, and it is the one place the gate cannot live in
`streak_celebration.dart`. Every other beat there is built so that its t=1 state is the resting
one; this beat's t=1 state is _motion_. So `StreakFlame` forces the mix to zero under reduced
motion, and `streak_flame_test.dart` pins that.

### Who owns the motion, and why that changed

The first version had **no timeline at all**. `Ignite` was a state machine holding a
`BlendState1DViewModel` over six single-frame poses, scrubbed by a bound Number in 0–100. The
argument for it was exactly the one above — Flutter keeps the clock — and it did deliver that.
What it also delivered:

- **nothing to play.** Not in the editor, not in `rive .`, not in any runtime. The file animated
  only when something wrote `progress`, so every review had to go through a contact sheet, and
  the user could not iterate on the animation at all before it shipped;
- **a timing defect that hid for days.** The drive was `easeOutBack`, shared with the hand-built
  glyph. It crossed 0 → 100 in about 185ms and then overshot to 108; a 1D blend clamps past its
  last pose, so 20 of the window's 32 frames were the same held frame and the entire
  choreography played in three. A reader saw the flame _appear_ rather than a book falling open.
  Every pose was correct and every blend between them was correct;
- **three failure modes stacked on the Flutter side** — a `StateMachineNamed` selector, a
  `DataBind.auto()`, and a view model that had to be null-checked, because a loaded artboard with
  no view model is an artboard that cannot be posed;
- **a runtime defect with no fix except a workaround.** See
  [the blend state that never stopped](#three-runtime-defects-the-artboard-exposed).

The rework keeps the clock in Dart and moves the _easing_ into the timelines, where the editor
and the previewer can both play it. The state machine, the blend state, the view model and the
data bind are all gone, and the file got smaller.

### And `Idle` reverses an explicit rule

This document, `streak_celebration.dart` and `AGENTS.md` all used to state that **nothing moves
after the last beat lands and there is no idle loop**, and treated an idle loop as a cost the
scrubbed-timeline contract existed to avoid. That was overruled deliberately: a flame that
freezes the instant it arrives reads as a decal of a flame, and the brief was Duolingo-grade.

The cost is real and is stated rather than waved away. A loop repaints for as long as the screen
is up, and **`pumpAndSettle` never returns anywhere the Rive path is live** — which is not
hypothetical, it took out four cases in `reading_streak_page_test.dart` that have nothing to do
with the flame. Four things bound it:

- the celebration is a transient sheet with one way out, not a screen left open;
- the mix is forced to zero under reduced motion;
- `_FlamePainter.advance` returns `false` when `liveness` is 0, which stops the render box's
  ticker. `false` means "no more frames needed", not "do not draw" — the drawing still paints,
  and a later change to either drive calls `scheduleRepaint`, which restarts the ticker;
- `useStillStreakFlame()` in `test/still_streak_flame.dart` pins the fallback for any test that
  pumps the celebration and settles.

`advance` deliberately does **not** also return true while the ignition is mid-flight. That was
the first version and it looks like an optimisation — it saves a ticker stop/start per frame —
but it means an artboard parked at any value strictly between 0 and 1 asks for frames forever,
and `streak_flame_golden_test.dart` renders six of those side by side.

## Judging it: four tools, none a superset of another

|                            | catches                                                        |
| -------------------------- | -------------------------------------------------------------- |
| `rive . --verify`          | Luau and shader compilation; exits 1 on error                  |
| `rive inspect . --summary` | bind paths, animations, and the only `problems` list           |
| `sheet.py`                 | **whether `Ignite` looks like anything**, sampled across 900ms |
| `motion.py`                | **whether `Idle` looks like anything**, and whether it seams   |

**Only the last two look at a picture**, and the first two will happily bless a scene that draws
nonsense. This one passed both with zero problems on its first attempt and still rendered the
pages _behind_ the covers (a dark mountain with a cream sliver on top), an egg instead of a
flame, a black peg where the gutter poked out below the flame's base, and — after the rework — an
idle loop in which **every ember was hidden behind the flame it came off**. None of those is a
structural error.

`sheet.py` is not enough on its own, and the reason changed with the architecture. It used to be
that a blend state interpolates every property independently, so two correct poses could pass
through something wrong in between; a timeline has no such split, because sampling it by time
_is_ sampling the in-betweens, which is why `between.py` was deleted. What `sheet.py` still
cannot see is `Idle` — **the previewer plays only the artboard's first animation, and there is no
`--animation` flag.** So until `motion.py` existed the loop had never been rendered once, and it
shipped with no visible spray at all.

`motion.py` is also the only thing that shows the **seam**. A looping timeline whose properties
do not return to their frame-0 values jumps once a second, forever. Its strip puts frame 0 and
frame 72 side by side; they must be the same picture.

Three traps in the screenshot path:

- **`--advance=1` is mandatory.** `--advance=0` applies no animation at all and renders the
  _authored_ pose — which here is a finished flame over an open book, and is a very convincing
  way to conclude the file is broken. `_preview.py` clamps to one frame.
- **The previewer composites onto its own opaque `#1D1D1D`**, and there is no flag to change it:
  a `kind="fragment"` document may not declare a `<Backboard>`, and `rive.yaml`'s
  `artboard.background` applies only to projects with no RML. So a chroma key cannot recover the
  alpha it was never given, and the first honest-looking contact sheet showed the glow as a solid
  black disc that does not exist. `_preview.py` builds a **patched copy** of the project with a
  cream rectangle behind everything; the shipped artboard is transparent and the celebration
  paints `kCandleGlow` behind it. (The scene used to carry a preview-only rectangle switched on
  by a second bound Number. That stopped being possible when the view model went away, and it is
  better this way — no preview scaffolding in the asset.)
- **An `Idle`-only render lies unless the authored pose is the resting pose.** `Idle` keys the
  flame, the core, the glow's scale and the embers, and nothing else — so every property the
  _opening_ moves falls back to its authored value. Authored shut, the loop breathed over a closed
  book. `_preview.py` used to patch those attributes in a copy of the project before rendering,
  which made the preview right and left the file wrong; `scene.rml` authors the open pose now and
  that mechanism is deleted. See [Motion](#motion).

Judging a warm palette on white, or on the previewer's near-black, is how you ship a glow nobody
can see.

### And do not hand-tune cubic handles

`smooth.py` fits them, using the Catmull-Rom construction, and prints RML to paste. Three
attempts by eye all came out faceted, because a `CubicMirroredVertex` spends one `rotation` and
one `distance` on **both** of its segments: a tangent chosen to suit one neighbour kinks the
other, and a handle long enough for a long segment bulges a short one. `CubicDetachedVertex`
gives each side its own angle and length, which makes the handles a calculation.

The same script fits the page-edge striations, for the same reason: each hairline needs a height
and a centre derived from the band's taper at its x, which is fourteen pairs of arithmetic that
cannot be checked by reading them — and which had to be redone from scratch the first time the
page block got thicker.

## Viewing it in the Rive Editor

`rive push` sends the document straight to a Rive file in the workspace, so it opens from the
editor's file browser with a revision history — no `.rev` on disk and no drag and drop.
`rive.yaml` records the target, so later pushes update that file rather than making a new one:

```bash
rive login                       # once; the session persists
rive push rive/streak_flame      # updates the recorded file
```

Then open **aschung's workspace → Personal Files → `streak_flame`**.

**It now actually plays there**, which it did not before the rework: a scrubbed blend state has
no timeline to scrub in the editor either. `Ignite` and `Idle` appear as ordinary animations.

`rive push` **writes ids into `scene.rml`** — 413 of them the first time. That is how it matches
objects up to update the same file rather than create a new one. It is harmless, and unlike
`rive pull` it does not regenerate anything: comments, structure and formatting all survive. Two
consequences worth expecting rather than investigating:

- a push shows up as a large diff;
- **any script written against the pre-push text stops matching**, because every tag has grown an
  `id=` attribute. Patch by line, not by regex on a tag.

**Do not push while the file is open in the editor.** Three pushes in one session, with the tab
open throughout, left the editor showing an **empty stage and an empty Animations panel** — no
artwork, no timelines — while the source on disk was intact (441 objects, 2 `LinearAnimation`s,
`rive inspect` clean) and the last push had reported `0 created, 56 updated, 0 deleted,
387 unchanged`, which accounts for every object. The document was fine; the editor was holding a
copy that had been rewritten underneath it. Close the tab, push, reopen.

Or skip the live file for review altogether:

```bash
rive rive/streak_flame --once --rev=/tmp/streak_flame.rev
```

writes a standalone document that opens directly and cannot be out of sync with anything.

`rive rive/streak_flame --once --rev=<path>` **writes a file and opens nothing** — it is the
handoff artifact, which the editor then opens — and it lands relative to the directory the command
was run from, not the project. Both it and `push` need a login; `--verify`, `--once`, the
previewer and every screenshot do not.

To look at it without a login at all, the previewer works offline and now genuinely animates:

```bash
rive rive/streak_flame
```

It plays `Ignite` on the previewer's near-black canvas. For `Idle`, or for the cream ground, use
`motion.py`.

### Do not round-trip through the editor

**`rive pull` would overwrite the project from the Rive file**, replacing `scene.rml` with a
machine-generated equivalent and discarding every comment in it. `rive create --from-rev` does
the same thing from a `.rev`. Since the comments are the record of which geometry was tried and
why — which is the entire argument for authoring this as text — **the editor is a viewer here,
not an authoring surface.** Edits belong in the RML.

## What the drawing taught

In the order the defects were found, because each fix caused the next.

### The orientation, which took two attempts

The brief is a book **lying flat on the floor with its spine running away along Z**, camera at
the book's own level looking down the spine. What that shows is the **tail edge and nothing
else**: the stacked edges of the pages, the edge of the cover boards under them, and a dark notch
at the centre where the halves part.

The first version drew the page _surfaces_ splaying open in a V, which is the view from **above**
— a camera looking down into the book. From the intended camera the interior is edge-on and
invisible. The drawing is a low horizontal slab, and several early defects (the bow tie, the pale
needle down the crease) only existed because there was interior geometry to get wrong.

### The book

- **The spine is the hinge, and the first mechanism had no spine in it at all.** Opening was
  `scaleX` 0.52 -> 1 plus `scaleY` 1.9 -> 1 on one node, on the reasoning that a shut book seen
  down its spine is one board wide and its full thickness while an open one is nearly two boards
  wide and half as thick. That arithmetic is right and the mechanism is still wrong, because
  nothing in it is a spine: the shut pose came out as two parallel dark bars with a cream filling
  and read as **an equals sign**, and the covers slid apart rather than hinging. A reader named it
  on sight.

  From this camera the spine runs away along Z, so it is a _point_ in our view, and opening a book
  is the front cover plus half the page block **rotating 180 degrees about that point** -- an
  ordinary in-plane rotation. `leaf` is that half, `base` is the half that stays.

  Three things then fall out instead of needing to be built: the 2:1 thickness relationship is
  geometry rather than a faked `scaleY`; the layering sorts itself out, because going up from the
  hinge the leaf is pages-then-board (the front cover is on top of a shut book) and after the flip
  the board is underneath, where a cover laid open belongs; and **every use of opacity in the book
  disappears**, which killed four separate bugs at once -- see [Motion](#motion).

- **The rotation must be negative.** At +90 degrees the leaf sweeps _down_ through the table
  before coming up the other side. Signed the other way, the book opens by passing its cover
  through the floor.

- **The page block is a constant thickness, and that is a concession.** Half a text block in an
  open book does thin toward the gutter, and it was drawn that way -- but a taper reflected
  through the hinge leaves a wedge-shaped _gap_ between the two halves when they are stacked, and
  a shut book has no gap in the middle of its pages. The shallow V an open book rests in is
  carried instead by tilting each half 3 degrees, which is cheaper and has no such side effect.

- **The page block is the bulk of a book.** At 15 units the open book was a 5px cream sliver on a
  3px dark line and read as a ruler with graduations -- the hairlines filled the whole band
  because there was no band to speak of. It is 22 now, and the boards are 8, because a board is
  two millimetres of card and the paper is the bulk.

- **No fore-edge chamfer.** Bevelling both halves' outer top corners opened a wedge between them
  as they stacked, which drew a dark notch in the shut book's fore edge and made the whole thing
  read as a **battery icon**. A rounded corner does the same job with nothing to misalign.

- **Page-edge hairlines run _across_ the block, parallel to the cover -- not up it.** They were
  drawn the other way round for several passes and this is the most basic thing the drawing got
  wrong. The pages are sheets lying flat, stacked through the block's thickness, so looking at
  the block's edge each sheet is one thin _horizontal_ band and the shadows between them are
  horizontal too. Vertical hairlines correspond to nothing physical at all. Note that they were
  described as "a comb" and as "a ruler's graduations" across three review passes -- including in
  this document -- without anyone naming the cause.

- **They are a shadow between sheets, not a highlight.** Five wide _pale_ bars per side, over a
  band that itself runs pale-to-tan, meant that near the fore edge the striation was _lighter_
  than what it sat on: the book read as a row of piano keys. Dark, at a fifth or less, with the
  alpha varied so the stack does not read as ruled notepaper.

- **`smooth.py` generates them.** The leaf's have to be authored in mirrored local space, because
  its flip runs its local `y` the other way, so that both halves' layers line up across the
  gutter when the book is open and stack into an evenly ruled slab when it is shut. That is not
  arithmetic worth doing twice by hand.

- **The crease is the darkest part of an open book, not the brightest.** Lighting the pages
  outward from the gutter -- on the reasoning that the flame is the light source and the gutter is
  nearest it -- put each half's brightest pixel against `x=0` and drew a pale needle straight down
  the middle. Two pages meeting in a valley shade each other. (This predates the reorientation and
  no longer applies to the same geometry, but the reasoning error is worth keeping.)

Four entries have been deleted from this list along with the geometry they described. Each was a
real fix to a real defect, and the hinge needs none of them:

- the book node's origin being the floor line (it was inside the slab, with the boards' underside
  bowed, so the book's lowest point sat _below_ the contact shadow and it read as a hammock);
- the shut pose needing a separate front board (without one, "shut" was the open slab at
  0.52 x 1.9: a tall cream loaf with a dark foot);
- the shut pose needing a cream filler to cover the page taper (scaled 1.9x, that taper drew a
  bright V valley down the middle of a closed book, with daylight between the two points);
- the gutter being a wedge pointing _down_ rather than a rectangle, because a gutter is a valley
  and the dark belongs below the page tops. Twice a gutter drawn standing proud of the paper read
  as a black peg with a flame balanced on it. One shape is now both the spine and the gutter, at
  two heights.

### The flame

- **A flame is widest about a quarter of the way up, and leans.** Four mirrored vertices gave an
  egg. Correcting it overshot into a tulip: the widest point too low and the base as wide as the
  shoulders, so the silhouette flared, pinched to a waist, and flared again. Six evenly spaced
  ones with the widest point at mid-height gave a **gothic leaf** with near-parallel sides. Eight,
  with a _shoulder_ between the apex and the belly, is what finally read as fire. The apex is a
  `StraightVertex` so the two curves meet in a corner rather than rounding over.
- **The base has to sit _in_ the gutter, not on it.** Tapered almost to a point it met the book in
  a maroon pinch.
- **Hold the body's gradient flat for the top half.** Run linearly from `kCandleFlame` to `flame`
  over the whole height, the midtone is a brown-orange nothing, the silhouette has no value
  contrast against the core, and the result is a soft airbrushed blob — which is precisely what
  the reader called "plain and low quality". A flat saturated body with a burnt foot is bolder
  and more like what fire does.
- **Embers may not wear the flame's own colour** — and which colour that rules out _flipped_ when
  they moved in front of the flame. Behind it, sparks painted `flame` #B54708 over a body that
  runs to #B54708 at its base were invisible. In front of it, they spend almost their whole life
  over the `#FFE8C4` cream ground, where the two pale tokens are a four-point difference and
  simply are not there. `kCandleFlame` #F2A93F is the one token that reads against both.
- **The artboard renders at half scale.** `stageSize` is 152pt against a 304×304 artboard. The
  empty upper half is not waste — it is where the burst and the embers fly.

### Motion

- **Nothing translucent may cross-fade over something dark, in either direction** -- and the
  final answer to this was to stop needing to. Five instances, and the last three were all the
  same handoff: page bands fading over the covers (a grey slab); the `fire` group at opacity 0.5,
  which made core and body _both_ translucent so their outlines showed through each other like
  overlapping decals; the front board **fading** over the cream ground (a grey plank); the front
  board **collapsing at full opacity**, which had no mud but left a hard dark line lying across
  the paper for its whole descent, so the open book read as a ruler; and the cream filler mid-fade
  over that same board, which is the first mud again with the layers swapped.

  The fix at the time was the oldest trick there is -- **change on the action**: the cover lifted
  at one corner, and then it, the filler and the gutter all switched on a single `hold` keyframe
  at the frame where `backOut` had the covers moving fastest. That worked. It was also three
  shapes and a hard cut in service of a mechanism that had no spine, and **the hinge deleted all
  of it**: there is no front board to fade, no filler to hide a taper, and no separate gutter to
  bring in. The book now animates on four continuous transforms and not one opacity. Recorded
  because the rule still binds everywhere else in the scene, and because "remove the thing that
  needs the cross-fade" is a better move than any cross-fade.

- **`backOut` needs a hold in front of it.** It front-loads so hard that at frame 4 -- 66ms -- the
  covers were already 70% open, and the reader never saw a closed book at all. Softening the curve
  costs the landing its knock; six held frames cost nothing.

- **Light may not arrive before its source.** The glow was keyed from frame 0, which lit a warm
  halo behind a book that was still shut and nothing was burning. It was visible in every contact
  sheet and noticed in none of them for three passes.

- **The authored pose must be the _resting_ pose, not the starting one.** `Idle` keys the flame,
  the core, the glow and the embers and deliberately nothing else -- it has no business re-stating
  a pose the ignition already reached. So every property the _opening_ moves falls back to its
  authored value, and with the scene authored shut, playing `Idle` on its own gave a living flame
  standing on a **closed book**. In the app this was invisible, because the painter applies
  `Ignite` first; it showed up the moment a human scrubbed `Idle` in the Rive Editor.

  Worse, `motion.py` had been **hiding it**: it built a patched copy of the project with those
  authored attributes rewritten to the post-ignition values before rendering, so the preview was
  right and the file was wrong. That is the wrong place to fix anything. Authoring the resting
  pose costs nothing, deletes that whole mechanism (`REST_POSE`, a `rest=` flag, about thirty
  lines), and makes a still render -- or a runtime that fails to find `Ignite` at all -- show a
  book lying open with a flame on it, which is the only sensible thing for either to show.

- **An idle breath of three percent over 1.2s is below the threshold of being seen.** The first
  render of `Idle` was indistinguishable from a still. It is two uneven breaths now, at seven
  percent, because fire moves faster and less regularly than a breathing chest and an even
  two-cycle sine is a pulsing logo.

- **A hard ease-out is wrong for a drifting ember.** On `0:200`, a (0.16,1,0.3,1) snap, an ember
  was four fifths of the way up a quarter of the way through its flight: the spray appeared as
  specks pinned near the top of the frame with a gap between them and the flame they came off. A
  spark slows as it cools; it does not stop.

- **`Idle` may only key properties `Ignite` leaves at their authored values.** The painter applies
  the ignition and then mixes the loop on top, so anything keyed in the loop _replaces_ what the
  ignition left. The flame's and core's scales and the glow's _scale_ all end at 1 and are safe.
  The glow's **opacity** is not -- `Ignite` settles it at 0.58 -- so the loop does not touch it.

- **Shapes that belong to one moment are authored invisible.** The burst and the gleam were not,
  and although the app never sees the authored value (a keyed property is held at its first
  keyframe's value, which is 0 for both), a still render does -- and the first render of `Idle`
  looked like the loop threw a permanent starburst.

- **Loop seams are free if a property is invisible at both ends of its own window.** Rive holds a
  keyed property at its first keyframe's value for every frame before it, so an ember whose window
  is 14..40 sits at its birthplace from 0 to 14 and at its death place from 40 to 72, and jumps
  back at the seam at zero opacity. The snap-back keyframes an earlier version carried were noise.

## The palette is shipped tokens, and only shipped tokens

`library_card/card_lighting.dart` and `app_theme.dart` own these. The scene picked none of its
own, because inventing brand colours is a mistake this repo has already made once.

|                         |                                                                 |
| ----------------------- | --------------------------------------------------------------- |
| `FFFFF3DD`              | the flame's hot tip — `kShareChromeLitInk`                      |
| `FFFFD479`              | flame core — the record's lit-today highlight                   |
| `FFF2A93F`              | flame body, and every ember — `kCandleFlame`                    |
| `FFB54708`              | the flame's burnt foot — `AppColors.light.flame`                |
| `FF26190A`              | the page-edge hairlines, at a fifth or less — `kCandleStockTop` |
| `FF130D05`              | _(retired with the gutter wedge)_ — `kCandleStockBottom`        |
| `FF35230E` / `FF1B1106` | cover board edge — `kCandleWellTop` / `kCandleWellBottom`       |
| `FFFDFAF1`              | page edges, lit — the record's paper                            |
| `FFFFE8C4`              | page edges, falling off — `kCandleGlow`                         |
| `FFD9A96B`              | page edges at the fore edge — `kCandleCoverLight`               |

The ground is `kCandleGlow` `#FFE8C4`. **A lighter halo is invisible on it**, so the glow is
warmer rather than brighter.

## Three runtime defects the artboard exposed

None is about the drawing, and all were found only by putting the file in place. Each is worse
than the bug it replaced, which is the argument for wiring an asset up early.

**`Factory.rive` aborts the process.** The Rive Renderer wants a GPU context and a headless
`flutter test` shell has none, so `File.asset` trips a native assertion — `Assertion failed:
(factory)`, `file.cpp:206` — and the shell dies with SIGABRT. That is not catchable: the `catch`
in `_resolve` never runs, the whole test file reports `did not complete`, and every case in
`streak_celebration_test.dart` goes with it. `kStreakFlameFactory` is `Factory.flutter`, which
draws through Flutter's own canvas. For a few dozen paths with no meshes, images or scripts the
Rive Renderer was buying nothing that would pay for a crash on a screen presented over the streak
page.

**A 1D blend state never stops advancing.** `RiveWidgetController.advance` returns
`didAdvance && active`, and a blend state reports itself as always advancing, so with `active`
left at its default the ticker ran forever. It surfaced as `pumpAndSettle timed out`. The
workaround was `controller.active = false`, which does not stop the drawing being drawn — it
gates the ticker, the hit test and the pointer handlers, not `paint`. **This is now moot**: there
is no state machine, and `_FlamePainter.advance` returns a value it computes itself. Recorded
because it is a property of blend states rather than of this file, and because the failure it
produced is the same one the idle loop produces deliberately.

**`RiveWidgetBuilder` documents a `RiveFailed` state and a missing asset does not reach it.**
`FileLoader.file` throws `RiveFileLoaderException` out of `initState`, which takes the subtree
down and broke fifteen cases the moment Rive was wired in. `StreakFlame` therefore calls
`File.asset` itself and treats every failure — thrown _or_ a null return, it does both — as an
ordinary absence. Don't simplify it back to `FileLoader.fromAsset`.

## Which flame you get depends on the machine

`rive_native`'s dynamic library is downloaded by `dart run rive_native:setup --platform macos`
into `build/`, and **`build/` is gitignored, so it does not travel between worktrees** any more
than `env.json` does. A fresh checkout has the `.riv` and no library to read it with:
`File.asset` fails, the fallback draws, and that is correct behaviour rather than a broken test.
Usefully, without the library the failure is _printed_ rather than thrown, so the graceful path
really is graceful.

But it means the hand-built flame is not dead code, and it means a test that inspects one flame or
the other is asserting a property of the machine. It also means, since `Idle` exists, that any
test which pumps the celebration and then settles hangs on a configured machine and passes on an
unconfigured one. `useStillStreakFlame()` in `test/still_streak_flame.dart` settles both, by
pointing the widget at a name that cannot resolve; `streak_celebration_test.dart` and
`reading_streak_page_test.dart` both call it. In the other direction,
`streak_flame_test.dart` asserts only what is true on both paths, and its one case that needs the
library skips itself with a reason.

## The drawing itself

A book **lying flat on the floor**, spine running away along Z, camera at the book's own level
looking down the spine. So what is drawn is the tail edge: a low horizontal slab. **The spine is
therefore a point in our view, and it is the hinge** -- `leaf` (the front cover and the half of
the page block above the midline) rotates -177 degrees about it, `base` (the rest) tilts 3 degrees
the other way, and one shape is the spine's rounded cap when shut and the gutter when open.

The cross-section when shut, in artboard units with the floor at 0:

```
  0 ..  -8    the back board, edge-on
 -8 .. -30    its half of the page block
-30 .. -52    the leaf's half of the block, resting on it
-52 .. -60    the front board
```

and the spine capping all four down the left, from -60 to 0. Open, the two halves are side by
side instead of stacked, each 30 units deep, and the spine is squashed to half its height into the
gutter between them. The flame rises along +Y out of that gutter.

**The authored values in `scene.rml` are the OPEN pose**, not the shut one -- see
[Motion](#motion) for why that matters outside the app.

Draw order is declaration order, **front first**: the embers, then the fire (burst, gleam, core,
body), then the book (leaf, base, spine, contact shadow), then the light behind all of it.
