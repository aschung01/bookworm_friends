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
./rive/streak_flame/build.sh                           # verify, inspect, build, install
../../.venv/bin/python rive/streak_flame/sheet.py      # the six keyed poses
../../.venv/bin/python rive/streak_flame/between.py    # and the blends between them
../../.venv/bin/python rive/streak_flame/motion.py     # and all of it on the real curve
```

Both outputs are committed: the `.riv` because `flutter build` cannot run the CLI and a missing
asset degrades silently, and the RML because it is the source. Edit the RML, run the script,
commit both.

## The three names that must match exactly

| Thing                              | Name                           |
| ---------------------------------- | ------------------------------ |
| Asset path                         | `assets/rive/streak_flame.riv` |
| State machine                      | `Ignite`                       |
| Bound view-model property (Number) | `progress`                     |

A typo in any of them is a **silent fallback** — the app keeps working and quietly never shows
the artboard, which is the hardest failure to notice. They are constants in
`streak_flame.dart`, asserted in `streak_flame_test.dart`, and — because constants agreeing
with each other proves nothing about the binary — that test also greps the built `.riv` for
`Ignite` and `progress`. It reads the bytes rather than the runtime, so unlike the rest of the
file it holds on every machine.

## The contract: Flutter keeps the clock

`progress` is a Number in **0–100**, written every frame from the celebration's own
`AnimationController`. **The artboard must not autoplay.** Its timeline is scrubbed, start to
finish, by that one property.

Which means **it does not animate on its own, anywhere** — not in the CLI previewer, not in the
Rive Editor, not in any runtime that just loads it. It animates because something writes
`progress`. In the app that is `_flame`. In the editor it is you, dragging the bound value.
That is the design, not a missing piece; the price is that a bare preview shows one frozen pose
and looks broken, which is worth knowing before you conclude it is.

Two consequences fall out of who owns the clock, and both are the reason Rive was acceptable:

- the beats of the celebration stay in Dart, where they are greppable and a test can drive
  them, instead of moving into an editor timeline nobody can read from the repo;
- `MediaQuery.disableAnimationsOf` keeps working with no special case — the controller jumps
  to `value = 1`, `progress` becomes 100, and the artboard poses at its final frame. A
  one-shot animation would need the artboard seeked by hand;
- **nothing moves once the last beat lands**, which this screen honours on purpose. An
  artboard with an idle loop would break it, on a screen a reader opens nightly.

Every animation in the scene is therefore a **single-frame pose**, and the blend between them
is the animation. There is no `loopValue`, no idle wobble, no autoplaying timeline.

The six poses the `BlendState1DViewModel` mixes between:

| `progress` | pose                                                                            |
| ---------- | ------------------------------------------------------------------------------- |
| 0          | shut — one board wide, flattened to a slab, covers out and pages hidden         |
| 20         | fallen open a few percent past its rest, seam showing, a dormant ember in it    |
| 35         | ignition, and the stretch: taller than rest while narrower than it              |
| 50         | the squash — wider and shorter than rest, licking the other way, gleam crossing |
| 70         | settling; the last of the lick, embers gone                                     |
| 100        | rest, and genuinely still                                                       |

Two rules the format enforces silently and the runtime does not check:

- weights run **0–100, not 0–1**;
- `BlendAnimation1D` children must be in **ascending `value`** order — the runtime binary
  searches them;
- **every blended property must be keyed in every pose.** One keyed in one pose and absent
  from another has nothing to mix toward, and jumps instead of blending. This is why the six
  pose blocks are the same eleven objects in the same order every time, and should be read as
  the columns of one table.

## Judging it: five tools, none a superset of another

|                            | catches                                                       |
| -------------------------- | ------------------------------------------------------------- |
| `rive . --verify`          | Luau and shader compilation; exits 1 on error                 |
| `rive inspect . --summary` | bind paths, state machines, and the only `problems` list      |
| `sheet.py`                 | **whether the drawing looks like anything**, at the six poses |
| `between.py`               | **whether the blends between them look like anything**        |
| `motion.py`                | **whether any of it happens where a reader can see it**       |

**Only the last three look at a picture**, and the first two will happily bless a scene that
draws nonsense. This one passed both with zero problems on its first attempt and still rendered
the pages _behind_ the covers (a dark mountain with a cream sliver on top), an egg instead of a
flame, and a black peg where the gutter poked out below the flame's base. None of those is a
structural error.

And `sheet.py` is not enough either, because **a blend state interpolates every property
independently and linearly, so two poses that are each correct can still pass through something
that is not.** The first version faded `page_*` in on opacity, which looks right at both ends and
spends the whole first fifth of the sequence as a grey slab in the middle — a half-transparent
page over a near-black cover. The opening happens in that same window, so most of it happened in
the mud. Only a sheet of the in-betweens shows it; `between.py` samples every 4%.

Nor are those two together, because **neither of them scrubs `progress` the way the app does.**
The artboard is posed by a curve over a window, and the first curve tried — `_ignite`'s
`easeOutBack`, shared with the hand-built glyph — crossed 0 → 100 in about 185ms and then
overshot to 108. A 1D blend clamps past its last pose, so 20 of the window's 32 frames were the
same held frame and the entire choreography played in three: a reader saw the flame _appear_
rather than a book falling open, with 62% of the window frozen. Every pose was correct and every
blend between them was correct. `motion.py` renders on the real curve and prints any value above
100; `_flame` in `streak_celebration.dart` is the fix, and a case in `streak_celebration_test.dart`
pins it, because both halves of that failure are silent — the runtime discards an overshoot
without complaint, and a front-loaded curve still animates, just somewhere nobody can see.

Two traps in the screenshot path:

- **`--advance=1` is mandatory.** Without it nothing has advanced and every frame is the
  authored rest pose — six identical renders that look convincingly like a working filmstrip.
- **The previewer composites onto its own opaque `#1D1D1D`**, and there is no flag to change
  it: a `kind="fragment"` document may not declare a `<Backboard>`, and `rive.yaml`'s
  `artboard.background` applies only to projects with no RML. So a chroma key cannot recover
  the alpha it was never given, and the first honest-looking contact sheet showed the glow as a
  solid black disc that does not exist. The scene therefore carries a cream `ground` rectangle
  bound to a second Number that **defaults to 0 and is switched on only by `sheet.py`**. The
  shipped artboard is transparent; the celebration paints `kCandleGlow` behind it.

Judging a warm palette on white, or on the previewer's near-black, is how you ship a glow
nobody can see.

## Viewing it in the Rive Editor

`rive push` sends the document straight to a Rive file in the workspace, so it opens from the
editor's file browser with a revision history — no `.rev` on disk and no drag and drop.
`rive.yaml` records the target, so later pushes update that file rather than making a new one:

```bash
rive login                       # once; the session persists
rive push rive/streak_flame      # updates the recorded file
```

Then open **aschung's workspace → Personal Files → `streak_flame`**.

`rive rive/streak_flame --once --rev=<path>` is the other route. It **writes a file and opens
nothing** — it is the handoff artifact, which the editor then opens — and it lands relative to
the directory the command was run from, not the project. Both it and `push` need a login;
`--verify`, `--once`, the previewer and every screenshot do not.

To look at it without a login at all, the previewer works offline:

```bash
rive rive/streak_flame --data=progress=100 --data=ground=1
```

Both flags matter. The artboard does not autoplay, so with no `progress` it sits at pose 0 — a
shut book, which reads as a broken render — and `ground=1` puts it on the cream the celebration
actually paints instead of the previewer's near-black.

### Do not round-trip through the editor

**`rive pull` would overwrite the project from the Rive file**, replacing `scene.rml` with a
machine-generated equivalent and discarding every comment in it. `rive create --from-rev` does
the same thing from a `.rev`. Since the comments are the record of which geometry was tried and
why — which is the entire argument for authoring this as text — **the editor is a viewer here,
not an authoring surface.** Edits belong in the RML.

## What the drawing taught

In the order the defects were found, because each fix caused the next:

- **Opening is `scaleX`, not rotation.** A 2D rotation pivots about a point, and a half's inner
  edge is not a point but the gutter _line_, which recedes. Rotating the halves swung their
  far-inner corners across the centre line and the book crossed into a bow tie. Anchored at the
  gutter, `scaleX` 0.54 → 1.0 is also the physical truth: a shut book seen down its spine is
  one board wide and an open one nearly two. `scaleY` flattens the open book's shallow V back
  into a slab, and `page_*` opacity fades the pages in over a cover that was always there —
  the material swap that sells the open, for one property rather than a second set of geometry.
- **The crease is the darkest part of an open book, not the brightest.** Lighting the pages
  outward from the gutter — on the reasoning that the flame is the light source and the gutter
  is nearest it — put each half's brightest pixel against `x=0` and drew a pale needle straight
  down the middle of the book. Two pages meeting in a valley shade each other. (The page
  outline was the first suspect and was innocent; `PointsPath` strokes every edge or none, so
  it had to go anyway.)
- **A flame is widest about a third of the way up.** Correcting the egg overshot into a tulip:
  the widest point sat too low and the base was as wide as the shoulders, so the silhouette
  flared, pinched to a waist, and flared again. The apex is a `StraightVertex` so the two
  curves meet in a corner rather than rounding over, and it sits right of centre so the
  silhouette leans.
- **The gutter may not outlive the flame's base.** Twice a gutter drawn past that point read as
  a domino stood on the page — once as a blunt rectangle, once as a converging wedge. Below the
  flame the crease is carried by the page gradient's own shadow, which is where a crease comes
  from anyway; what is left of the gutter is the seam that appears after the covers fall open
  and before there is a flame big enough to hide it.
- **Embers may not wear the flame's own colour.** Half the fan sits in front of the flame body,
  and sparks painted `flame` #B54708 over a body that runs to #B54708 at its base were
  invisible. The burst looked left-weighted and the distribution was symmetrical all along.
- **The artboard renders at half scale.** `stageSize` is 152pt against a 304×304 artboard, so a
  drawing occupying a third of the artboard's height wastes both resolution and layout. The
  flame is the hero and is sized like it.
- **Nothing translucent may cross-fade over something dark.** Two instances, found together in
  the in-between sheet: `page_*` on opacity over the covers gave the grey slab above, and the
  `fire` group at opacity 0.5 made the bright core and the body _both_ translucent, so their two
  outlines showed through each other like overlapping decals instead of reading as fire. The
  pages now unfold on `scaleY`, and the dormant ember at pose 20 is fully opaque and simply
  small — a tiny crisp flame reads as a flame, where a half-transparent one read as a smudge.

## The palette is shipped tokens, and only shipped tokens

`library_card/card_lighting.dart` and `app_theme.dart` own these. The scene picked none of its
own, because inventing brand colours is a mistake this repo has already made once.

|                         |                                                                 |
| ----------------------- | --------------------------------------------------------------- |
| `FFFFD479`              | flame core — the record's lit-today highlight                   |
| `FFF2A93F`              | flame body — `kCandleFlame`                                     |
| `FFB54708`              | flame edge — `AppColors.light.flame`                            |
| `FF26190A`              | gutter seam — `kCandleStockTop`                                 |
| `FF35230E` / `FF1B1106` | cover, far and near — `kCandleWellTop` / `kCandleWellBottom`    |
| `FFFDFAF1`              | page, lit — the record's paper                                  |
| `FFFFE8C4`              | page, falling off — `kCandleGlow`                               |
| `FFD9A96B`              | page at the crease, and the outer falloff — `kCandleCoverLight` |
| `FFE2D9C4`              | the stacked page edges — the record's hairline                  |

The ground is `kCandleGlow` `#FFE8C4`. **A lighter halo is invisible on it**, so the glow is
warmer rather than brighter.

## Two runtime defects the artboard exposed

Neither is about the drawing, and both were found only by putting the file in place. Both are
worse than the bug they replaced, which is the argument for wiring an asset up early.

**`Factory.rive` aborts the process.** The Rive Renderer wants a GPU context and a headless
`flutter test` shell has none, so `File.asset` trips a native assertion — `Assertion failed:
(factory)`, `file.cpp:206` — and the shell dies with SIGABRT. That is not catchable: the
`catch` in `_resolve` never runs, the whole test file reports `did not complete`, and every case
in `streak_celebration_test.dart` goes with it. `kStreakFlameFactory` is `Factory.flutter`,
which draws through Flutter's own canvas. For a dozen paths with no meshes, images or scripts
the Rive Renderer was buying nothing that would pay for a crash on a screen presented over the
streak page.

**A 1D blend state never stops advancing.** `RiveWidgetController.advance` returns
`didAdvance && active`, and a blend state reports itself as always advancing, so with `active`
left at its default the ticker runs forever — a 60fps repaint on a screen a reader opens
nightly and then leaves sitting there, which is exactly the idle-loop cost the scrubbed-timeline
contract exists to avoid. It surfaced as `pumpAndSettle timed out`. Clearing `active` does not
stop the drawing being drawn: it gates the ticker, the hit test and the pointer handlers, not
`paint`. And the state machine registers `scheduleRepaint` as an advance-request listener, so
writing `progress` asks for a frame by itself — one frame per change, stillness in between.

And the older one, still true: **`RiveWidgetBuilder` documents a `RiveFailed` state and a
missing asset does not reach it.** `FileLoader.file` throws `RiveFileLoaderException` out of
`initState`, which takes the subtree down and broke fifteen cases the moment Rive was wired in.
`StreakFlame` therefore calls `File.asset` itself and treats every failure — thrown _or_ a null
return, it does both — as an ordinary absence. Don't simplify it back to `FileLoader.fromAsset`.

## Which flame you get depends on the machine

`rive_native`'s dynamic library is downloaded by `dart run rive_native:setup --platform macos`
into `build/`, and **`build/` is gitignored, so it does not travel between worktrees** any more
than `env.json` does. A fresh checkout has the `.riv` and no library to read it with:
`File.asset` fails, the fallback draws, and that is correct behaviour rather than a broken
test. Usefully, without the library the failure is _printed_ rather than thrown, so the
graceful path really is graceful.

But it means the hand-built flame is not dead code, and it means a test that inspects one flame
or the other is asserting a property of the machine. Three cases in
`streak_celebration_test.dart` do inspect it — the glyph's colour as it catches, the spark
painter, the gleam's `ShaderMask` — and they pass on a machine that has not run the setup and
fail on one that has. `debugStreakFlameAssetOverride` settles it by pointing the widget at a
name that cannot resolve. In the other direction, `streak_flame_test.dart` asserts only what is
true on both paths, and its one case that needs the library skips itself with a reason.

## The drawing itself

A book laid with its spine along Z, so the camera sits at the **tail edge looking along the
spine**. We see the two halves splaying left and right, the page block between them, the
stacked page edges along the near edge, and the gutter as a dark seam up the middle. The flame
rises along +Y out of that seam. Rive is 2D, so the depth is drawn rather than transformed: the
far edge of every quad is narrower and higher than its near edge, converging up-screen.

Draw order is declaration order, **front first**: the fire (embers, gleam, core, body), then
the seam it comes out of, then the two halves of the book, then the light behind all of it, then
the preview-only ground.
