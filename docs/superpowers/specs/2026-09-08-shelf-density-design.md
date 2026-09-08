# Shelf density: three ways to draw a shelf, and reading first on all of them

Status: decided, not built.
Prior drawing: `docs/mockups/shelf-overflow/index.html` — same problem, three
different (wrapping) answers. See "What this supersedes".

## Context

A shelf is one horizontal `ListView` of face-out covers (`shelf_row.dart`), and
on a 390×844 phone **3.57 of them fit**: `bookHeight` is `screenHeight * 0.15`
(126.6), a cover at `kDefaultCoverAspect` is 84.4 wide, the row is
`screenWidth * 0.95` less 15pt of padding each side (340.5), and the separator is 15. So a twelve-book shelf shows three and a sliver, and the only thing on the
row that says otherwise is `_EdgeFades` softening the clip.

`docs/mockups/shelf-overflow/` framed this and drew three answers, all of which
spend **vertical** space: wrap onto a second plank, wrap until every book is
face-out, or cap the wrap and push the remainder onto a shelf page. This design
spends **horizontal** space instead, by drawing a non-reading book smaller than a
face-out cover.

Three states, cycled from one button in the library bar:

1. `covers` — today's row, unchanged but for the reading-first order. The
   default.
2. `leaning` — reading books face-out; everything else shingled at a fixed step,
   leaning right so the leftmost book is frontmost.
3. `spines` — reading books face-out; everything else spine-on, per
   `BookVertical`.

### What the arithmetic settles

The numbers decide more of this than argument does — and they depend on how many
books the shelf has _in progress_, because a face-out cover is expensive: at
84.4pt it costs about four shingle steps or three spines.

| state                   | books in 340.5pt, none reading | …with one reading |
| ----------------------- | ------------------------------ | ----------------- |
| `covers`                | **3.57**                       | **3.57**          |
| `leaning` (20.3pt step) | **~13.6**                      | **~9.7**          |
| `spines` (~37pt)        | **~9.2**                       | **~7.5**          |

The working, so it can be checked:

- `covers`: `84.4n + 15(n−1) ≤ 340.5` → 3.57.
- `leaning`, none reading: the group is `(m−1)·20.3 + 84.4`, because the last
  book is overlapped by nothing and draws its full cover → 13.6.
- `leaning`, one reading: `84.4 + 15 + (m−1)·20.3 + 84.4 ≤ 340.5` → 8.7
  shingled, 9.7 total.
- `spines`, none reading: `340.5 / 37` → 9.2.
- `spines`, one reading: `(340.5 − 84.4 − 15) / 37` → 6.5 spines, 7.5 total.

**A spine is 29–47pt wide, not 26.** `BookMetrics.from` resolves
`thickness = resolvedWidth * jitter.thicknessFactor` with factors 0.36–0.52, which
at `bookHeight = 126.6` and height jitter of 0.94–1.06 gives ~29 to ~47pt, mid
~37. Two earlier drafts of this document used 26 — `BookVertical`'s _default_
`width`, which the read pile overrides with `metrics.thickness` and which no real
spine ever uses. The correction matters twice over: it lowers the counts above,
and it is what makes a spine a viable drag target (see "Edit mode").

These counts are **before** the trailing label reserve (see "Retained, and one
addition"), which costs roughly one spine's worth.

Three consequences:

- **Both new states are a large improvement, and an unequal one.** `leaning`
  roughly quadruples what a shelf shows and fits a twelve-book shelf whole when
  nothing on it is in progress; `spines` roughly doubles to triples it. Neither is
  the total victory an earlier draft claimed — see "An open question".
- **`leaning` is the denser of the two, by about two books.** So the choice
  between them is _not_ purely one of character: on the stated tiebreaker
  `leaning` wins. `spines` earns its place by being the more bookish drawing and
  the cheaper one, not by fitting more. Say this plainly rather than presenting
  them as equivalent.
- **`spines` is the cheaper of the two**, despite looking like the more
  elaborate drawing. A spine's width is `BookMetrics.thickness` from page count,
  so it needs no cover decode to lay out, and spines do not overlap, so paint
  order is irrelevant and the row can stay a lazy `ListView.builder`. `leaning`
  needs a `Stack` and therefore builds every tile. See "The one real risk".

### An open question: the step, and whether twelve should fit

`kShelfLeanStep` is set at 0.16 of `bookHeight` (20.3pt) below. To make a
twelve-book shelf fit whole _with_ one book in progress, the step would have to
come down to **15.7pt** (`k ≈ 0.124`), which shows 19% of each cover rather than
24%.

This is left at 0.16 and flagged rather than silently retuned, because 24% is
the figure the "colour, not type" argument was made about. If "twelve fits" is
worth more than that margin, 0.124 is the number. Decide before implementing;
the two differ by one constant.

### Goals, and the tiebreaker

Both expression and reachability, with **reachability as the tiebreaker** where
they conflict. This is why reading books are never compressed, why the emphasis
in `leaning` sits at the left end of the row, and why no cap is placed on the
face-out head block.

## The model

```dart
enum ShelfDensity { covers, leaning, spines }
```

A new enum, **not** a widening of `LibraryMode`. `LibraryMode { library,
editLibrary }` is about what the reader is doing; this is about how books are
drawn. They are orthogonal — edit mode always draws face-out, from any density —
so fusing them would produce six states of which three are aliases.

`leaning` rather than `stacked` or `shingled`, because it names the physical
thing being drawn (books leaning right onto each other) and this codebase names
drawings after what they depict: `BookVertical`, `ReadingBookmark`,
`kReadSpinePose`.

### Where the state lives

New file `lib/providers/shelf_density_provider.dart`, shaped exactly like
`ThemeModeNotifier`: a `Notifier` whose `build()` reads
`sharedPreferencesProvider` and whose `set()` writes a string key and then
assigns `state`. An unparsable stored value falls back to `covers`.

**Persisted per reader, and applied to every library including friends'.** This
is a statement about how _you_ like to see books — the same category as theme
mode and search source, the two things the app already persists — not a property
of a particular library. Deliberately _not_ in `library_shell_provider.dart`,
where everything is `StateProvider.autoDispose` and dies with the session.

A friend's shelves are the place the density helps most, not least: unfamiliar
shelves are exactly where seeing all twelve books beats seeing three and a
sliver.

### What was rejected: owner-authored presentation

A tempting fourth option is to store the state on `profiles`, so a reader
decides how their library is presented to visitors. The app already has authored
presentation as a concept (`shareable_library_card.dart`,
`card_shelf_plan.dart`), so it is not foreign. It is rejected because **it fuses
a private act to a public one**: the toggle's most frequent use is to flick to
spines for a second, check a shelf, and flick back — and under a single profile
field that flick is a publication. Every friend's next visit shows spines
because you wanted to see one shelf.

It also collides with the control. A bare cycling glyph cannot say "this is what
your friends will see"; that needs a label, a preview, and a place in Settings.
The honest version of owner-authored presentation is therefore a _second_
setting, not the same field — and nobody has asked for it. It can be built later
without disturbing anything here.

## Reading first

**In all three states, and in edit mode.** Reading books come first on every
shelf. This is a property of the library rather than of a density state.

New `withReadingFirst(List<Shelf>)` in `library_provider.dart`, directly beside
`withoutFinishedBooks`, stable: books at `bookStatusReading` in authored order,
then everything else in authored order. `LibraryPane.build` composes the two —
`withReadingFirst(withoutFinishedBooks(shelves))` — so both display-time
reshapings of the shelves happen in one place, symmetrically. The two are
independent (one filters status 2, the other promotes status 1), so the order of
composition is a readability choice only.

One pure helper beside it: `readingHeadCount(Shelf)`, the length of the leading
run of reading books. `ShelfBooksRow` reads it to place the compressed group and
`_ShelfRowState` reads it to clamp a drop index, so the two cannot disagree
about where the boundary is.

`Book.position` is never written by the view.

### The drag collision, and how it is resolved

Because promotion holds in edit mode, the row is two zones: the reading head and
the tail. A drag must not be able to preview an illegal landing.

`_dropIndexFor` already derives an index from measured slot centres, so it gains
a clamp: a tail book's drop index cannot fall below `readingHeadCount`, and a
head book's cannot rise above it. The gap therefore never opens where the book
cannot land, the preview is always the truth, and **nothing ever animates back**.
A cross-shelf drop lands in the arriving book's own zone on the receiving shelf.

### A consequence, named rather than discovered

`reorderBooksInShelf` writes positions from the list the row hands it, and that
list is the **promoted** one. So the first drag on a shelf persists the
promotion into `position`, and after that, clearing a book's reading status
leaves it where the promotion put it rather than where it originally sat.

That is a real departure from the property `withoutFinishedBooks` boasts about
("clearing the 'Read' status puts the cover straight back where it was"). It is
accepted deliberately: a drag is an authoring act, the reader was looking at the
promoted row when they performed it, and writing back any order other than the
one they saw would persist an arrangement nobody chose.

### Edge cases

- **No reading books.** No head block and no leading gap; the compressed group
  starts at the row's left padding. Promotion is a no-op.
- **All books reading.** Nothing is compressed, so all three states render
  identically. Correct rather than broken — though it does mean the toggle
  visibly does nothing on such a shelf.
- **Many reading books.** Five face-out covers overflow the row on their own and
  push the compressed group off-screen. **No cap is applied.** A cap would
  compress exactly the books the design promises to protect, and
  `FriendReading`'s own doc puts the realistic ceiling at two.

A free consequence worth recording: compressed books are non-reading by
definition, so `ReadingBookmark` only ever draws on a face-out cover. The ribbon
sits at `top: 0, right: kReadingBookmarkInset` — outside its cover's box — and
would be mangled by a neighbour leaning over it. It can never collide with
anything.

## `leaning`

Head block: reading books, face-out at full width, 15pt gaps, authored order
among themselves. Then one 15pt gap. Then the shingle group: every non-reading
book at a fixed step, left on top.

### The step

`kShelfLeanStep = 0.16`, a fraction of `bookHeight` — ~20.3pt on a 390×844, and
it scales with the device the way `bookHeight = screenHeight * 0.15` already
does.

Deliberately **not** a fraction of cover width. `shelf_row.dart` is emphatic
that "no shelf can work out the size of a book it does not hold": a cover's
width follows its decoded aspect ratio and its jittered height. A step in
absolute points needs no width at all, and it gives a uniform rhythm where a
proportional step would be ragged for reasons no reader could see.

At 20.3pt of an 84.4pt cover the reader sees about a quarter of each book. That
is enough, because at that width recognition is being done by **colour**, not by
type.

### Left on top

Each book leans right onto its neighbour, so the leftmost is frontmost and the
reading book sits fully visible in front of everything. The visible strip of each
subsequent cover is its right edge.

The alternative — right on top, revealing the left strip where left-aligned
cover type usually starts — was rejected because it puts the _rightmost_ book
frontmost and fully visible, which is the wrong end of a row whose whole premise
is that the leading book matters most. That is the tiebreaker firing.

### Why this needs a `Stack`, and how hit-testing survives it

`ListView` paints in child order, so a lazy list gives right-on-top — the
opposite of what is wanted. So the shingle group is a `Stack` inside a
horizontal `SingleChildScrollView`, children emitted **highest index first**
with `Positioned(left: i * step)`, so book 0 paints last and lands on top.
`clipBehavior: Clip.none`.

**Each `Positioned` is `step` wide, and the cover overflows it to the right.** This
is the part that is easy to get wrong. A `RenderBox` hit-tests its whole rect
regardless of what is painted there, so a `Positioned` sized to the full cover
would let book 0 — hit-tested first, being frontmost — claim taps landing on the
visible strip of book 3, which sits well inside book 0's rect. Sizing the slot to
the exposed strip makes the hit area exactly the part of the book a reader can see.
The last book in the group gets a full-cover-width slot, because all of it is
visible.

So paint order and hit order end up saying the same thing: emitted in reverse, book
0 paints last and is hit-tested first, and its hit rect is only the strip it
actually shows.

**A `Stack` can hold draggables**, which is what lets `leaning` keep the
one-gesture lift the rest of the app has — each `Positioned` child is the same
`LongPressDraggable` a cover gets in `covers`. The slot it reports is the step, so
this is the one density needing the `slotExtent` override described under "Edit
mode".

The `Stack` needs an explicit width, and the last book's true cover width is not
knowable before decode, so it is computed from `kDefaultCoverAspect` plus
trailing slack. This is the same approximation `readSpineMetrics` already makes
and documents — "resolved at `kDefaultCoverAspect` rather than at the cover's
true ratio, which the pile could not know without decoding every cover" — so it
is a precedent being followed rather than a new liberty being taken.

### The one real risk

A `Stack` builds every child. `leaning` therefore builds one `BookWidget` per
non-reading book on the shelf, where today's `ListView.builder` builds about
four. On a twelve-book shelf that is the point of the feature. On a sixty-book
shelf it is sixty cover decodes at once.

**Validate this with a measurement before building the rest of the state.** Do
not pre-emptively design a windowing scheme for a problem that may not exist;
`BookWidget` already caches decoded covers, and a reader who scrolls today's row
to its end pays the same total cost, just spread over time. But this is the one
place in the design where a state costs more than it saves, and it should be
measured rather than assumed.

### Surfacing

The tapped book's slot animates from `step` to its full cover width, pushing
later books right, and it moves to the top of the z-order. 220ms `easeOutCubic`,
in the family of `_kPartDuration` (280) and `_hiddenWhileEditing` (260). One
surfaced book per row; tapping another surfaces that one instead.

### Retained, and one addition

- `_EdgeFades` stays. A thirty-book shelf still overflows.
- `shelvedBookCount` and `ShelfLabel` are untouched, so the shelf-tab hero keeps
  the same width at both ends of its flight.
- **Added:** trailing room in `leaning` and `spines` equal to `ShelfLabel`'s
  measured width. Today 3.4 books means the tail is always off-screen and the
  label floats over bare plank; once a row fits, the last book lands under the
  label — a new problem created by success.

  Reserved **unconditionally** in the two compressed states rather than only
  when the row fits, because "does it fit" is a post-layout fact and a reserve
  that appears and disappears across a decode would shift the row. On an
  overflowing row the reserve simply sits at the far end where nobody sees it.
  `covers` is untouched, since its tail is never on screen.

## `spines`

Same head block, then one 15pt gap, then spines standing shoulder to shoulder
with no gaps, the way books on a plank actually sit.

Almost entirely reuse. Four pieces, each needing one change:

### 1. `readSpineMetrics` generalised

It hardcodes `baseHeight: ReadPile.spineBase`; a shelf needs `bookHeight`.
Extract `spineMetricsFor(Book book, {required double baseHeight})` into
`book_geometry.dart` and have `readSpineMetrics` delegate to it with the pile's
constant.

This keeps the guarantee that function's doc makes — "**One** function, used by
the flat spine, by the chassis that replaces it, and by the row that lays both
out. Two call sites computing this is how the spine and the cover come to
disagree about thickness" — and extends it to a third caller.

Because it uses the same `BookJitter.fromIsbn`, a spine and its turned-out cover
are the same height, and `bookRowExtent(bookHeight)` reserves the right headroom
with no change.

### 2. `_spineTone` lifted out of `_ReadPileState`

It is `spineToneFor(book.coverColor ?? generatedCoverColor(book.isbn))` and it is
private. Made a top-level function, so a shelf spine and a pile spine of the
same book cannot come out different colours.

### 3. `background: context.colors.surfaceVariant`

**This is a real bug that would otherwise be inherited.** `BookVertical`'s
`background` parameter exists to decide whether a pale spine needs an outline to
have a silhouette at all, and its doc says the `surface` default "is right on a
shelf". It is not: `library_view.dart` paints the library `surfaceVariant`
(`#E9ECEF`), not `surface` (`#FFFFFF`).

So a shelf spine would be measured against the wrong ground, and in the _unsafe_
direction — `#E9ECEF` is darker, so a fill can clear the 1.25 threshold against
white while genuinely having no edge against the surface it is on. This is
precisely the failure the same doc already describes for the read pile's
`sheetBackground`. **The comment should be corrected as part of this work.**

`separator: true` as well, for the reason the pile gives: two books with similar
covers otherwise stand side by side as one wide block.

### 4. The turn, shared

`_turnedBook` in `_ReadPileState` — `kReadSpinePose`, the `_slotWidth`
projection `width·|cos| + thickness·|sin|`, the `hinge` offset, `kTurnMargin`,
and `BookChassis` driven by a tween from `kReadSpinePose` to 0 — is exactly the
surfacing interaction needed here.

Extract it as `TurningBook` in `lib/ui/widgets/book/turning_book.dart` and have
both the pile and the shelf use it, including the `arch: false` rule for a spine
that has become a face of a solid object.

This is the piece that makes "a spine means one thing everywhere" true in code
rather than only in intent.

## Interaction

### Tapping a compressed book is two steps

The read pile already fixes what a spine tap means: `BookVertical`'s doc says it
"has to match what the chassis renders at a turn of `-π/2`, because tapping a
spine swaps one for the other in place." If a shelf spine behaved differently
from a pile spine, the same drawing would mean two different things in one app.

So: **first tap surfaces, second tap opens details.** A spine turns to its
cover; a shingled cover lifts clear of its neighbours. This also turns the
small-target problem into a recoverable one — the worst outcome of a mis-tap on
a 20pt strip is that the wrong book comes forward, which costs nothing.

`covers` is unaffected and remains one tap.

### Hero tags only on face-out books

Reading books and the currently surfaced or turned one. This is the read pile's
own rule ("only that book carries the tag"), and it guarantees a flight always
starts from a cover that is fully on screen rather than from one three-quarters
hidden behind a neighbour.

### Edit mode: spine-native in `spines`, face-out in `leaning`

| density   | edit mode draws       |
| --------- | --------------------- |
| `covers`  | covers (unchanged)    |
| `spines`  | **spines, draggable** |
| `leaning` | covers                |

An earlier draft of this design said "edit mode always draws face-out, regardless
of the active density", and gave three reasons. **Two of them were wrong about
`spines` and one was arithmetic on a number that did not exist.** The rule is now
per-density, because that is where its reasons actually hold.

**Why `spines` edits as spines.**

- **A spine is a real target.** 29–47pt wide on a ~119pt-tall strip — comparable
  to a list-row drag handle. The earlier objection said "a 26pt spine would be a
  26pt grab target", which was `BookVertical`'s unused default.
- **The slot arithmetic becomes self-consistent, and this is the important one.**
  `ShelfBookDrag.slotExtent` is measured from the rendered slot and is documented
  as "the width of the gap the receiving shelf has to open for it". If edit mode
  redrew a lifted spine as a cover, that measured 37pt would be the gap opened for
  a book needing 84, and the drop preview would lie. **That bug is created purely
  by changing the drawing on entry to edit mode** — editing spines as spines
  removes it, with no override and no fabricated width.
- **Hit-testing is exact**, because spines tile without overlapping.
- **It is better than editing in covers.** Rearranging a shelf today means seeing
  3.4 of its books; in `spines` it means seeing about nine. Reordering is the one
  task where seeing the whole shelf matters most, so the compressed drawing is
  _more_ useful in edit mode, not less.

**The delete badge, which is the one genuine problem.** `_DeleteBookButton` sits
at `top: -22, left: -22` — outside its cover — so a 44pt disc on a 37pt spine
blankets its neighbours, and in `spines` the neighbours are touching. The answer
is already in this design: **in spine edit mode, delete is reached by tapping a
spine to turn it out, and the turned-out cover carries the badge.** One book is
face-out at a time, so one badge exists at a time and nothing can collide. The
two-step tap does double duty and no new affordance is invented.

**A lifted spine stays a spine.** Its drag feedback is not turned out to a cover:
it is picked up where it stood, it lands in a spine-width gap, and `_liftScale`
alone is the cue that it came loose. This keeps `_liftScaled`'s stated promise —
"the cover's own height, not a larger one… starting at any other size would be the
jump this is here to avoid" — literally true, and needs no `turnDrive` on the lift
at all.

**Why `leaning` still falls back to face-out.** Shingled covers overlap, so a tap
is genuinely ambiguous about which book it hit, and the step is not the book's
width — so the measured `slotExtent` is wrong in exactly the way described above.
`leaning` is therefore the **one** place needing an override: on a lift from a
shingled row, `slotExtent` is computed from the face-out cover width rather than
measured. Confined to one density, for a reason that does not generalise.

### Transitions are a cross-fade, not a per-book turn

Switching density is a **180ms cross-fade of the row**. So is entering edit mode
from `leaning`, which is the one density whose drawing changes on entry;
`covers` and `spines` do not change drawing at all and so need no transition.

An earlier draft of this design had spines turning to covers per book on entering
edit mode. That is withdrawn twice over: `spines` no longer redraws on entry at
all, and a per-book turn would need a `BookChassis` per book, which is the exact
cost rejected when a chassis-based `leaning` variant was turned down. Spending it
on a transition after refusing to spend it on the drawing would be incoherent.

A fade needs no chassis and no decode, still reads as "the same books, drawn
differently", and keeps the toggle cheap enough to flick back and forth — which
is how it will actually be used. The expensive, convincing turn is kept for
surfacing, one book at a time, where a reader is looking directly at it.

## The control

In `_LibraryBar`, inboard of `GlassAvatarButton`, with an `AdaptiveIconButtonGap`
between them — the same slot relationship the gear has to Poke in the visit
state. `AdaptiveIconButton.svg` at `diameter: 44`.

**One cycling button**, `covers → leaning → spines → covers`. At three states
cycling costs at most two taps, and the feedback is unmissable because the
entire library redraws — so the effect _is_ the affordance in a way it would not
be for eight states. A three-glyph segmented pill was rejected: it costs
110–130pt of a 56pt bar whose own doc calls it "the most valuable row on screen"
and records that Edit and `+` were deleted from it for being duplicate entry
points.

It shows **the state you are in**, not the state you would get. This is a mode
indicator, and with a two-tap-maximum cycle "what am I looking at" matters more
than "what will this do". The semantic label names the current state, so the
cycle is announced rather than silent.

Present in both the self and visit states of the bar, since the preference
applies to both libraries. Absent while editing, where density does not apply.

### Strings and glyphs

Three semantic labels in `app_en.arb` and `app_ko.arb`, one per state.

Three icon pairs in `svg_icons.dart` following the `kStretchHorizontalIcon*`
pattern exactly: a stroked SVG for Flutter (with an explicit stroke, so
renderers need not resolve Lucide's upstream `currentColor`), plus a raster PNG
for UIKit.

**The PNG must be transparent outside the glyph**, and must be produced with a
real rasteriser:

```sh
rsvg-convert -w 72 -h 72 -o assets/icons/<name>.png <svg>
```

Not `qlmanage`, which bakes Quick Look's opaque backdrop in. iOS tints an
`imageAsset` by clipping a fill to the image as a _mask_, so an opaque backdrop
makes the mask the whole canvas and the button renders as a solid square. This
is documented at `kStretchHorizontalIconNativeAsset` and has already been hit
once.

Lucide `gallery-horizontal`, `gallery-horizontal-end` and `library` are the
closest candidates. They need eyeballing at 22pt before being committed to.

## Decomposition

`shelf_row.dart` is over 1,200 lines and most of it is the drag machine.

**The seam is not where an earlier draft of this document put it.** That draft
assumed view mode was a plain `ListView.separated` with no draggables, and proposed
extracting a separate "resting row". It is not: `_buildBookRow` serves both modes,
and every book at rest is a `LongPressDraggable`, because a hold at rest is the
gesture that both enters edit mode and lifts the book — and a `Draggable` that
appears after the finger is down can never adopt that pointer. There is no resting
row to extract.

So what moves out is the **drawing**, not the row. The draggable, the slot, the
shift animation and the drop machinery stay in `shelf_row.dart`, and each density
supplies the widget that goes inside the slot plus the slot's width.

```
lib/providers/shelf_density_provider.dart     enum + persisted Notifier
lib/ui/widgets/shelf/shelf_book_tile.dart     today's _buildBookContent: cover,
                                              bookmark, delete badge
lib/ui/widgets/shelf/shelf_spine_tile.dart    a BookVertical spine, and the slot
                                              width that goes with it
lib/ui/widgets/shelf/shelf_lean_metrics.dart  the step, and the Stack cascade's
                                              offsets and reversed paint order
lib/ui/widgets/book/turning_book.dart         _turnedBook, shared with the pile
```

`shelf_row.dart` keeps the frame, the label, the plank, the draggable and the drag
machine. It will grow a little rather than shrink, which the earlier draft had
wrong; the offset is that three drawings live in three small files instead of
inline.

`_EdgeFades` stays private where it is. Nothing outside `shelf_row.dart` needs it
any more, so moving it would be churn for its own sake.

## Testing

Following the repo's existing naming:

- `shelf_density_provider_test` — default is `covers`; persistence round-trips;
  an unparsable stored value degrades to `covers`.
- `shelf_reading_first_test` — `withReadingFirst` is stable; composes correctly
  with `withoutFinishedBooks`; all-reading and no-reading shelves;
  `readingHeadCount`.
- `shelf_leaning_layout_test` — step arithmetic against the table above; the
  `Stack`'s child order is **reversed**, pinning the paint-order decision so it
  cannot be silently undone; the trailing label reserve is present in both
  compressed states and absent in `covers`.
- `shelf_spine_metrics_test` — a shelf spine's height matches its own face-out
  cover's jittered height; `readSpineMetrics` returns what it did before the
  extraction (a regression guard on the refactor).
- `shelf_spine_background_test` — the pale-spine outline fires against
  `surfaceVariant`, extending `book_vertical_outline_test` and
  `color_contrast_test`.
- `shelf_drag_zone_clamp_test` — a tail book dragged over the head opens its gap
  at `readingHeadCount` and never before; a head book cannot leave the head; a
  cross-shelf drop lands in its own zone.
- `library_bar_test` extended — the button is present in the self and visit
  states, absent while editing, and cycles through three states.
- Edit mode renders face-out at every density.
- `shelf_density_render_preview.dart`, in the style of
  `library_sheet_render_preview.dart` — this is a visual feature and the repo
  already uses previews for the pile and the card.

A `docs/mockups/shelf-density/` drawing is recommended before implementation,
because `docs/mockups/shelf-overflow/` exists for the same problem and the two
should be comparable. It is not a blocker.

## What this supersedes

`docs/mockups/shelf-overflow/index.html` drew three answers to the same
arithmetic, all of which spend vertical space, and recommended `capped-wrap`.
None of them is built.

This design does not delete that work and does not formally kill those options —
wrapping and density are compatible, and a future `covers` state could still
wrap. But the recommendation in that mockup ("bounded vertical cost, legible
wrap, and a home for per-shelf actions") should be **annotated** to record that
a horizontal answer was chosen first, so a reader arriving at the mockup is not
misled into thinking `capped-wrap` is still the plan.

## Out of scope

- Owner-authored presentation (density stored on `profiles`). See "What was
  rejected"; if wanted, it is a second setting, not this field.
- A `BookChassis`-based `leaning` variant showing cover plus a sliver of spine.
  Most convincing, and it loads a cover per book, which is the cost
  `BookVertical` exists to avoid.
- Any change to the read pile's own behaviour. It gains a shared `TurningBook`
  and a shared spine tone; it loses nothing and changes nothing on screen.
- Wrapping onto multiple planks.
