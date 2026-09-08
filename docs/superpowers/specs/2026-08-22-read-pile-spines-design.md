# Read-pile spines: hashed sizes, cover tones, and turning one out

Status: decided, not built.
Drawings: `docs/mockups/read-pile-turn/index.html` (root version `decided`).

## Context

The read view's collapsed state is `ReadPile` — a horizontal `ListView` of
`BookVertical` spines standing on a plank, 169pt tall, and the thing the Library
tab rests on. It is **the only place in the app where every book is drawn the
same size**. The shelves above it vary book heights on purpose (`BookWidget`
resolves a `BookJitter` per ISBN, and `bookRowExtent()` exists to reserve room
for it); the month grid deliberately switches that off, because its cells are a
uniform 2:3 and the same 6% reads as misalignment there. The pile has no such
excuse — it is a row of physical objects on a shelf, and a row of identical
objects is the one thing a shelf never looks like.

Two things follow, and they are the whole of this design:

1. **Size.** Give each spine its height and its thickness from the `BookJitter`
   the rest of the app already resolves. Nothing new is computed; the pile
   simply stops discarding what is already known about each book.
2. **Depth.** A spine is the one face of a book that says nothing about it.
   Tapping one turns it out to its cover in place, and from there it behaves
   exactly like a book on a shelf: hold to turn it, tap to fly to the details
   page.

Neither is reachable today. `BookVertical` takes a fixed 26×124 and a
`bookOpacityList` index, and `BookChassis` — the app's 3D book — has three faces
and no spine, so there is nothing on that side to rotate from.

### What the drawings settled

`docs/mockups/read-pile-turn/index.html` ports `bookHash`,
`bookThicknessPositionFromPages` and both jitter ranges into the page and checks
the port against the goldens `test/book_geometry_test.dart` pins, so every drawn
width is the number the widget would produce for that ISBN. Six findings came
out of it, four of which contradicted the prose that preceded them:

- **`BookChassis` has no spine face.** The addition is small — the machinery for
  a perpendicular strip already exists in `bookPageLocalMatrix` — but it has to
  be added before a spine can turn into anything.
- **`_face` pivots on the book's centre.** Invisible at 16°; at 90° it slides the
  book half a cover width sideways, through its neighbour. The turn needs the
  pivot at the spine's edge, which means the chassis needs it as a parameter.
- **The row's width is not monotonic in the turn.** It peaks at
  `atan(thickness / cover)` — 16.4° for a typical book — at
  `hypot(cover, thickness)`, about 3pt past the cover's final width, then
  narrows. Accepted, not fixed: it is what a real book does, and 3pt over the
  last ~90ms is under what reads as a wobble.
- **A cover-toned pile needs separation between spines.** The spines are flush
  (the `ListView` has no separator), which is invisible while the row is one
  green at three opacities and reads as a solid dark slab once every spine takes
  its own tone.
- **A turned-out book needs air either side.** Flush, the cover sits hard against
  its neighbours — a book wedged in place rather than one taken off the shelf —
  and its stacked shadows are clipped away by them.
- **`bookBoardColorFor` is not a spine tint.** It multiplies toward black, so a
  cover averaging `#DCD8D1` lands on `#878480`: a dead neutral grey at 3.72:1,
  which reads as a gap in the shelf and cannot carry the 12pt title a spine now
  has. A back board never had to clear anything, because nothing is written on
  it.

The last three were only visible in a rendered screenshot. No measurement on the
page said anything about them.

### Rejected

Kept browsable in the drawings, because each is the evidence for a decision.

- **`green-remap`** — brand-green spines, widths remapped from the thickness
  _position_ onto 21–31pt so the mean stays today's 26 and the pile's density is
  untouched. The original recommendation, on the grounds that it moved nothing.
  Killed by its own drawing: a ±5pt spread on a 26pt spine barely reads as
  variation, so it paid the full cost of per-book sizes and collected almost none
  of the benefit. It also has to make the spine's width and the turned book's
  thickness agree by fiat, where real thickness agrees by construction.
- **`green-true`** — true widths, brand green. Not wrong, and it is the cheapest
  thing that answers "should thick and thin books be distinguishable": no column,
  no sampled colour, no contrast floor, and the opacity cycle separates
  neighbouring spines by itself so it needs no hairline. Set aside because the
  tone is what makes the pile read as a shelf rather than as a chart, and because
  a spine that looks like the book it turns into is the point of turning it.
- **`taller-pile`** — heights on base 124 rather than 117, centring the spread on
  today's height instead of capping it there. Arguably the truer reading of "vary
  the heights", and it costs 7.4pt of shelf plus four test expectations. Set
  aside for the cheaper invariant; see below.

## Decision

### Heights: base 117, so `ReadPile.extent` does not move

`bookRowExtent()` already states the rule: a row must reserve
`baseHeight × BookJitter.maxHeightFactor`, or a book that hashes tall is clipped.
The pile's row reserves `124 + 13` (the 13 being what a praised spine grows by,
so praise cannot change the pile's height). Taking 124 as the _reserved_ height
rather than the base gives `124 / 1.06 = 117`, and therefore:

- books span **110.0 – 124.0pt**, the tallest exactly today's spine;
- `_rowExtent` stays **137**, `ReadPile.extent` stays **169**;
- the collapsed detent, `sheetMidExtent`, `_swapPoint`, the clearance tests and
  the "169pt `ReadPile`" in `docs/mockups/scan-to-add` all stay as they are.

The pile is unchanged in aggregate and varied in detail, which is the outcome
worth having: nothing in the shell has to be re-derived to get it.

### Widths: `BookMetrics.thickness`, unremapped

A spine's width is the book's thickness, so it is the thickness the chassis
already computes: `coverWidth × thicknessFactor`, i.e. `height × 2/3 × [0.36,
0.52]`, which lands at **28 – 39pt** against today's flat 26. Two consequences,
one cost:

- the spine you tap is exactly as thick as the book that turns out of it, with
  nothing to reconcile between the two states;
- where the catalogue supplied a credible page count, the spine's width is real
  data — `bookThicknessPositionFromPages` already prefers it over the hash;
- the row holds about **nine and a half** spines across its 324pt rather than
  twelve and a half. Accepted: the pile is a browsable object, not an index.

### Tone: each spine takes its own cover's, from a stored colour

A spine is filled with a darkened form of its own cover rather than with `brand`.
The colour must come **from the row, never from a live decode**.

`_sampleCoverColor` only has an answer after the image resolves, so a pile that
sampled would paint grey on a cold start and colour itself in. `books.page_count`
settled this exact question one property over, in as many words: stored, because
a value arriving mid-session would make the book visibly change on screen. So:

- **`books.cover_color text`, nullable, no index, no CHECK** — the same shape and
  the same reasoning as `page_count`. Nullable is load-bearing: a value gives the
  spine its cover's tone, NULL routes it to `generatedCoverColor(isbn)`, and the
  two states drive different code. A malformed value is ignored at the point of
  use rather than costing the row its book.
- **Written at insert**, from the decode the Add Book flow already performs.
- **Backfilled opportunistically**: `BookWidget` already samples every cover it
  decodes, to pick its back board. When the column is null for a book the
  signed-in user owns, write it back. No script, no new decodes, and — because it
  is the app's own sampler — a stored colour and a live one cannot disagree. A
  server-side backfill is rejected for exactly that reason: a server-side average
  would not equal Flutter's 1×1 GPU downsample, so books would visibly change
  tone the day it ran.
- **NULL falls back to `generatedCoverColor(isbn)`**, which needs no network. So
  every spine has a colour on the first frame whatever state the backfill is in,
  and the mixed state is colour-against-colour rather than colour-against-grey.
  A friend's library works unchanged: their rows are not yours to write, so their
  pile shows whatever their client has filled in, plus fallbacks.

Two things this buys outside the pile, and they are most of its value:
`_boardColor` returns null until the sample lands, so **every real-cover book in
the app currently shows a neutral grey back board and then pops to its tinted
one** — shelves, month grid, details hero, `CollapsingBookTitle`. A stored colour
removes that everywhere. And a friend's books get their tone without your client
decoding their whole library.

**The backfill turned out to be reachable, and it found a third thing.** The
sampler was a 1×1 `drawImageRect` that let the rasteriser average; Impeller does
not average at that size, it returns roughly a single texel. Measured against 56
rows a real device had written: 0 correct, median drift 42/255. `averageCoverColor`
is now an alpha-weighted mean in Dart — correct, cheap at thumbnail sizes, and
**deterministic**, which is what lets a command-line tool reproduce a phone's
answer. `test/cover_color_backfill_tool.dart` then sampled all 471 covers with that
very function and wrote them, so the stored colours and live ones agree by
construction rather than by hope.

### `spineTintFor`: a floor with chroma in it

`bookBoardColorFor` is kept for the back board and is **not** used raw for a
spine. A new function applies two steps before it, each a no-op for a cover that
does not need one:

1. **Chroma lift.** Below `kSpineTintMinSaturation = 0.18` (HSV saturation),
   blend the cover toward `brand` by up to `kSpineTintChromaLift = 0.45`, scaled
   by how far below the floor it sits **and by the cover's own luminance**.
   Borrowed from the brand rather than invented, so a washed-out cover's tint is
   a desaturated version of the app's own green rather than an arbitrary hue.

   The luminance factor is not decoration, and implementing this without it is
   how the need for it was found: black has saturation 0 exactly as white does,
   so a lift gated on chroma alone fires on a **black jacket as hard as on a pale
   one** and turns it into a dark green spine. That is a book with no problem,
   recoloured. A pale neutral goes dead against paper; a dark neutral already
   reads as a book.

2. **Contrast floor.** Darken in 6% steps toward black until white clears
   `kSpineTintMinContrast = 4.6:1`, bounded at 24 iterations. Stepwise rather
   than closed-form because the target is a contrast ratio, which is not linear
   in the mix. This step is not confined to washed-out covers: the amber in
   `kGeneratedCoverPalette` boards at 4.02:1, so it fires on a fully saturated
   swatch too — and adds no hue when it does, which is the property the
   palette test pins.

On the drawn corpus this leaves **12 of 13 tints exactly `bookBoardColorFor`**
and lifts one: `#DCD8D1 → #878480` (3.72:1, saturation 0.05) becomes `#62776E`
(4.79:1, saturation 0.18) — a muted sage that reads as a pale book instead of as
a hole in the shelf. Because the floor guarantees it, **a tinted spine's title is
unconditionally white**; choosing per spine was the earlier answer and it left
exactly one dark-on-pale label in a row of white ones, which looked like a
mistake.

> **Open, and measured on real data.** 1 of 13 was the drawing's corpus. Of **471
> real averaged covers, 228 fall below the floor** — averaging a colourful jacket
> with white paper and black type desaturates it, so about half a real library is
> near-neutral. Because the lift blends toward one fixed hue they converge:
> `#CDCEDA` → `#617575`, `#A2B4A3` → `#617669`, `#A9B9B0` → `#62786F`. Three
> distinguishable covers, one spine colour. The likely answer is to raise the
> cover's **own** saturation and keep its hue, falling back to the brand only when
> there is no hue left to preserve — pale lavender becomes grey-blue, khaki stays
> khaki. Undecided.

`BookVertical`'s existing rule is untouched for untinted spines: white above
opacity 0.7, `primaryText` at or below.

### A 1pt line between spines

Each tinted spine carries `inset -1px 0 0` of black at 28% down its right edge.
Not decoration: the `ListView` has no separator, and once every spine has its own
tone a near-black book beside a navy one has no edge between them at all. Only
needed where the tone varies, which is why the shipped pile never needed it.

### The turn

Tapping a spine turns it out to its cover in place. One book at a time; tapping
another turns that one out and this one back, and the year filter, the grid's
swap point and edit mode all close it.

- **Angle.** The existing `turn` extends from `[0, +kBookTurnAngle]` to
  `[-π/2, +kBookTurnAngle]`. Positive turn exposes the fore-edge, so the spine is
  revealed at **negative** turn. `-π/2` is spine-on, `0` is cover-on, `+16°` is
  the held book.
- **Pivot.** At the spine's edge, not the book's centre. `BookChassis` takes the
  pivot as a parameter; the shelves keep `Alignment.center`. The pile's books
  therefore turn about a different point from the shelves' — defensibly, since a
  book on a shelf is being looked at and a book in the pile is being pulled out.

  **The pivot moves the camera with it, not just the hinge.** `bookParentMatrix`
  composes `T(p) · projection · Ry · T(-p)`, wrapping the projection and not only
  the rotation. Wrap the rotation alone and the vanishing point stays on the
  book's centre line, which leaves a cover swung to `-π/2` about an edge that is
  off that line **not edge-on to the camera at all**: it projects as a sliver of
  squashed artwork beside the spine — measured at 6.96pt on a 78pt cover, 8.9% of
  its width, beside every spine in the pile. The correct composition collapses it
  to exactly zero, and throws in the property the row's layout wants: a spine-on
  face lands at `w = 1` and so projects at exactly `thickness`, making the pile's
  arithmetic exact rather than approximate.

  The drawing had this subtly wrong and could not have shown it: its
  `perspective-origin` sat at the cover's centre, which is only ~4.7pt off the
  hinge, so the sliver was sub-pixel. The Dart is what made the error legible; the
  mockup has been corrected to `var(--ox)`.

- **A fourth face.** A spine strip of the book's thickness, hinged on the cover's
  left edge, drawn with the `BookVertical` treatment the pile uses today: the
  tint, the 12pt rotated title — but **not the 5pt arch**. An arch is a notch in
  the head of one face, which a flat drawing can do and a solid cannot: the cover
  beside it is full height, so at the hinge the spine's head sits 5pt lower and the
  back board shows through the gap in a different tone, which reads as the spine
  and the cover being two different heights. The flat spine in the resting row
  keeps its arch; only the chassis face drops it.

  It is the mirror of the page block, and `bookPageLocalMatrix` is the model for
  its matrix — with two differences. The spine takes no depth clearance at either
  end, because a clearance would open a gap between it and a board that shows at
  every negative angle, which is the pile's resting state. And it turns the _other
  way_, `+π/2`, so that its **right edge is the hinge**: composed the other way
  round the strip lands in the same place and spans the same depth while being
  **reflected**, so every title reads backwards. The two conventions disagree about
  which sign that is, so the drawing's own note on the subject does not transfer.

  **It is painted under the cover, not over it**, and that is the opposite of
  where it first went. The spine's near long edge _is_ the cover's hinge edge, so
  the two never interleave — but which side of the hinge each falls on flips with
  the sign of the turn. Below `0` the spine is outside the hinge and the order is
  free; above it the spine crosses onto the cover's side and projects **inside the
  cover's silhouette**, 8.7pt in at `+16°`, where it must be occluded. Both signs
  happen to the same book, since the pile turns one out to `0` and a hold takes it
  on to `+16°`. CSS hid this completely: a `preserve-3d` context sorts its
  children by depth, so the drawing was correct in any DOM order.

- **Layout width.** `cover×|cos| + thickness×|sin|`, so neighbours slide rather
  than being painted over. Non-monotonic by ~3pt near the end; accepted.
- **Air either side.** `kTurnMargin = 8` at full turn, scaled by the same
  progress as the rotation, so the resting pile is untouched and the gap opens as
  the book comes out.
- **Timings are the shelves'.** `kBookTurnDuration` 260ms out,
  `kBookReleaseDuration` 180ms back, `kBookHoldDelay` 140ms before a hold turns
  it. Two motions at visibly different rates would read as two mechanisms.
- **Only the open book is a chassis.** The other twelve stay flat
  `BookVertical`s, so the collapsed Library tab loads **one** cover image where
  today it loads none. At `-π/2` the composite is the spine face alone, which is
  the same drawing `BookVertical` makes, so the swap on tap is seamless.
- **No stage two.** `onLongPress` enters edit mode on the shelves; the pile has
  no edit mode, so the hold is feedback and nothing else.

### The Hero, and why it is now safe

Tapping the turned-out book pushes the details route and the cover flies, on the
same `book_<isbn>` tag, `MaterialRectCenterArcTween` and `FittedBox` shuttle the
shelves use.

**This reverses a written decision.** `book_details_tab_view.dart:151` says: "The
pile and the month grid fly no book either, for the same reason." That comment
must change with this. Two things make it safe now:

- A finished book is kept off the shelves by `withoutFinishedBooks`, so there is
  no second `book_<isbn>` hero on the library route to collide with.
- **Only the open book carries the tag.** `book_<isbn>` collides across the
  ~15 migrated books with no ISBN; tagging every spine would put several
  `book_` heroes in one subtree, which throws. One-at-a-time makes the tag unique
  by construction, which is a correctness argument for the interaction and not
  only a tidiness one.

`flyShelfFromLibrary` stays false for a finished book: the pile's plank is shared
by every book standing on it and is not a particular shelf's, so there is still
nothing for it to fly to.

## Dependencies

- `books.cover_color` migration and its backfill path. The pile renders correctly
  before it lands — every spine falls back to `generatedCoverColor(isbn)` — so
  this does not gate the rest.
- `BookChassis` gains a spine face and a pivot parameter; `BookWidget` gains a
  way to be handed a resolved `BookJitter` (it computes its own today, and the
  turned book must be as thick as the spine that was tapped), and a **pose** in
  radians. The pose _adds to_ the internal hold rather than replacing it, which is
  what makes "behaves like a book on a shelf" literally true rather than
  reimplemented: the pile says where the book is, the hold says how it answers
  your finger, and the `+16°` runs on the shelves' own code path. This is the one
  respect in which the pose differs from the existing `turnDrive`, which _is_ the
  hold relocated to another recogniser and therefore has to replace it.

## Testing

- `bookHash`/`BookJitter` goldens in `test/book_geometry_test.dart` are untouched
  and must stay untouched: nothing here changes the hash.
- `ReadPile.extent` stays 169. The clearance and sheet tests that assert the
  collapsed height are the guard on the base-117 decision, and they should pass
  unmodified — if any of them needs editing, the base is wrong.
- `spineTintFor`: every tint clears 4.5:1 against white; the floor is a no-op for
  a saturated cover (identity with `bookBoardColorFor`); a low-chroma cover comes
  out with more saturation than plain darkening would give it, not merely darker.
- The turn: projected width equals thickness at `-π/2` and cover width at `0`;
  the margin is 0 at rest and `kTurnMargin` from cover-on onward; the pivot is
  the spine's edge.
- One spine open at a time, and only the open one carries a hero tag. A pile of
  books with no ISBN must not throw.
- The last change's two tests — the empty message centred in the visible sheet,
  and the plank pinned to the card's bottom edge through a drag — must keep
  passing with variable heights, since a short book gains its headroom at the top
  like every other one.

## Risks

- **The write-back on decode is a mutation from a render path.** It needs to be
  idempotent, debounced, and silent on failure. A book scrolled past twice must
  not write twice, and an offline device must not surface an error for a cosmetic
  column.
- **`overflow` on the row.** The turned book's shadows must not be clipped by the
  row's cross-axis bound, and the spines must still clip horizontally.
- **Tap targets.** The horizontal list gives children tight cross-axis
  constraints, so a spine's target is already the full 137pt column. That is
  unchanged, but it means the target does not shrink for a short book — worth
  checking on device that a 110pt spine does not feel like it has dead space
  above it.
- **Two taps to the details page** where there is one today. The first tap buys
  seeing a cover without leaving the tab; if it reads as friction rather than as
  a peek, the fallback is to keep the turn and let a tap anywhere on the open
  book navigate immediately, which is what this design already does.

## Deliberately not done

- The month grid keeps `jitter: false` and gains no hero. Its cells are uniform
  by construction and the variation reads as misalignment there.
- No change to the empty state, the filter, the plank, or the sheet's detents.
- `ReadPile.extent` is not touched, and neither is the design record's 169.
- No stage-two long press, no reorder, no swipe-to-remove in the pile.
