# Shelf density: ways to draw a shelf, and reading first on all of them

Status: built. **`leaning` was withdrawn after it shipped** — see "Withdrawn:
`leaning`" below. What is built is `covers` and `spines`.
Prior drawing: `docs/mockups/shelf-overflow/index.html` — same problem, three
different (wrapping) answers. See "What this supersedes".

**Read this document knowing that one of its three states is gone.** The `leaning`
sections are kept rather than deleted, marked as withdrawn, because the analysis in
them is the reason not to bring it back and the hit-testing lesson in it applies to
any future overlapping drawing. Nothing below describes code that exists unless it
says `covers` or `spines`.

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

States, cycled from one button in the library bar:

1. `covers` — today's row, unchanged but for the reading-first order. The
   default.
2. ~~`leaning` — reading books face-out; everything else shingled at a fixed step,
   leaning right so the leftmost book is frontmost.~~ **Withdrawn.**
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
- `leaning`, none reading: the group is `(m−1)·20.3 + 84.4`, because the group
  ends where the last cover ends and that cover starts `(m−1)` steps along → 13.6.
  (The book drawn in full is the _first_, not the last — see "Left on top".)
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

## Withdrawn: `leaning`

It was built, it was fixed twice, and it was then removed. Both fixes are worth
reading before anyone proposes an overlapping shelf again, because neither was a
coding slip — each was a consequence of the overlap that the design had not
reasoned through:

1. **The hit slots were on the wrong edge.** A cascade that leans right paints book
   _i_ _under_ book _i−1_, so the visible part of each book is its **trailing**
   edge. The slots were placed at the leading edge, which is the part hidden under
   the neighbour — so every target sat under a book and taps landed on whoever
   happened to span the point. Tapping one book surfaced another.
2. **Bringing a book forward had to push both ways.** The book to the left of the
   revealed one is painted _on top_ of it, so pushing only the followers left the
   reveal half-covered and read as the tap having done nothing.

Both were fixed and the state worked. It was withdrawn anyway, and the reason is
not the bugs — it is what the bugs were symptoms of. **The overlap is the thing a
reader has to reason about in order to use the shelf.** At a quarter of a cover the
recognition is being done by colour rather than by type; a tap has to be aimed at a
20pt strip whose position is not where the drawing suggests; and the reveal needs
air opened on both sides just to make one book legible. A spine is a thing readers
already know how to look at, and it needs none of that.

What it cost to remove: about two books of density per row (`leaning` fit ~9.7 with
one book in progress against `spines`' ~7.5), and the `Stack` that came with it —
`spines` is a lazy `ListView`, so a sixty-book shelf builds about four tiles where
`leaning` built sixty. The density was the thing `leaning` was better at, and it was
the only thing.

## The model

```dart
enum ShelfDensity { covers, spines } // `leaning` was here; see "Withdrawn"
```

A new enum, **not** a widening of `LibraryMode`. `LibraryMode { library,
editLibrary }` is about what the reader is doing; this is about how books are
drawn. They are orthogonal — edit mode draws each density as itself — so fusing
them would produce four states of which two are aliases.

`leaning` rather than `stacked` or `shingled`, because it named the physical thing
being drawn (books leaning right onto each other) and this codebase names drawings
after what they depict: `BookVertical`, `ReadingBookmark`, `kReadSpinePose`. (Kept
for the naming principle, which outlived the state.)

### Where the state lives

New file `lib/providers/shelf_density_provider.dart`, shaped exactly like
`ThemeModeNotifier`: a `Notifier` whose `build()` reads
`sharedPreferencesProvider` and whose `set()` writes a string key and then
assigns `state`. An unparsable stored value falls back to `covers` — except a stored
`'leaning'`, which migrates to `spines`. That is deliberate rather than lazy: the
withdrawn state was the _other_ compressed one, so a reader who had chosen it asked
for a shelf that fits, and dropping them to `covers` would answer a question they did
not ask.

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

**In every state, and in edit mode.** Reading books come first on every
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
- **All books reading.** Nothing is compressed, so both states render
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

## `leaning` (withdrawn — see "Withdrawn: `leaning`")

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
horizontal `SingleChildScrollView`, children emitted **highest index first**, so
book 0 paints last and lands on top. `clipBehavior: Clip.none`.

**Each `Positioned` is `step` wide and anchored to its cover's _right_ edge, with
the cover overflowing it to the left.** This is the part that is easy to get
wrong, and the first implementation got it wrong in both halves.

A `RenderBox` hit-tests its whole rect regardless of what is painted there, so a
slot sized to the full cover would let book 0 — hit-tested first, being frontmost
— claim taps landing on the visible strip of book 3, which sits well inside book
0's rect. Sizing the slot to the exposed strip fixes that.

But _which_ strip matters just as much. The cascade leans **right**, so book _i_
is painted **under** book _i−1_: the part of book _i_ a reader can see is its
trailing edge, and the part hidden under the neighbour is its leading one. A slot
at `i * step` — the cover's left edge — therefore sits entirely under book _i−1_
and collects no tap anyone ever aimed at it, while the tap they did make falls
through to whichever box happens to span that point. The symptom is tapping one
book and surfacing another. So each slot's left edge is
`i * step + cover − slotWidth`, and the cover is aligned `bottomRight` inside it.

**The first book of the group draws in full, not the last.** Nothing is painted on
top of book 0, so all of it is visible and it gets a full-cover slot. The last
book is covered from the left like every other book but that one. (An earlier
version of this section had this backwards.)

So paint order and hit order end up saying the same thing: emitted in reverse, book
0 paints last and is hit-tested first, and every other book's hit rect is only the
trailing strip it actually shows.

**A `Stack` can hold draggables**, which is what lets `leaning` keep the
one-gesture lift the rest of the app has — each `Positioned` child is the same
`LongPressDraggable` a cover gets in `covers`. The slot it reports is the step, so
this is the one density needing the `slotExtent` override described under "Edit
mode".

The `OverflowBox` inside each slot must set `minWidth: 0`. It inherits its
parent's `minWidth`, and a `Positioned` with a `width` makes that tight — so the
child would be forced to fill the slot and `ShelfBookTile` would bottom-_centre_
the cover inside it, undoing the right-anchoring on exactly the full-cover slots
where it matters.

The `Stack` needs an explicit width, and a cover's true width is not knowable
before decode, so it is computed from `kDefaultCoverAspect`. This is the same
approximation `readSpineMetrics` already makes and documents — "resolved at
`kDefaultCoverAspect` rather than at the cover's true ratio, which the pile could
not know without decoding every cover" — so it is a precedent being followed
rather than a new liberty being taken.

**Right-anchoring turns the height jitter from a defect into nothing.** Book
heights jitter ±6% (`BookJitter`), so a cover's real width is not
`base · kDefaultCoverAspect`. Because a strip is the distance between two right
edges, anchoring on the right makes every visible strip exactly `step` whatever
the heights are; anchoring on the left would have made the strips ragged by the
jitter, which is the version a reader would notice. What is left is a leading
overhang of at most 4% of the base height on the group's first book, which lands
in the margin the row already keeps in front of the cascade.

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

The tapped book's slot animates from `step` to its full cover width and it moves
to the top of the z-order. 220ms `easeOutCubic`, in the family of
`_kPartDuration` (280) and `_hiddenWhileEditing` (260). One surfaced book in the
whole library — see "One book forward in the library" under Interaction — so
tapping another, on this shelf or any other, surfaces that one instead.

**It has to open air on _both_ sides, not just the trailing one.** The book to the
left of the surfaced one is painted _on top_ of it, so pushing only the books
after it leaves the revealed book still half-covered by its left neighbour —
which reads as the tap having done nothing. So the revealed book moves right by
one clearance to step out from under the book in front of it, and everything
after it moves by two.

A clearance is `cover − step + kTurnMargin`: enough to undo the overlap, plus the
same 8pt the read pile puts either side of a book it turns out, for the same
reason — flush reads as a book wedged in place rather than one taken off the
shelf. That 8pt also absorbs the height jitter, whose worst case is about 5pt, so
the revealed book keeps air on both sides whichever books it lands between.

A reveal splits one cascade into three, and every cascade has a leading book that
nothing covers — so the book _after_ the revealed one shows its whole cover too,
by the same rule rather than by a special case. That is what makes the row read as
a gap with books standing either side of it.

### Retained, and one addition

- `_EdgeFades` stays. A thirty-book shelf still overflows.
- `shelvedBookCount` and `ShelfLabel` are untouched, so the shelf-tab hero keeps
  the same width at both ends of its flight.
- **Added:** trailing room in each compressed state equal to `ShelfLabel`'s
  measured width. Today 3.4 books means the tail is always off-screen and the
  label floats over bare plank; once a row fits, the last book lands under the
  label — a new problem created by success. (This one **survived** the withdrawal:
  `spines` still reserves it.)

  Reserved **unconditionally** rather than only when the row fits, because "does
  it fit" is a post-layout fact and a reserve that appears and disappears across a
  decode would shift the row. On an overflowing row the reserve simply sits at the
  far end where nobody sees it. `covers` is untouched, since its tail is never on
  screen.

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

### One book forward in the library, not one per shelf

The surfaced book is **one id for the whole library**, held in
`surfacedBookProvider`. Bringing a book forward on any shelf puts back whatever was
forward on any other.

It began as a `_surfacedBookId` field on `_ShelfRowState`, which made "at most one"
true of each row independently — so a five-shelf library could stand five covers
among its spines at once. That is not a stricter version of this rule, it is a
different rule: a cover among spines reads as _the_ book being looked at, and five
of them read as a library that has half-changed density. It was reported as the
feature functioning oddly, which is the right reading of it.

It also carries the delete-badge argument below, which was only ever coherent
because **one** book is face-out. One badge per _shelf_ was already several 44pt
discs per screen.

The reset belongs to the state rather than to any view of it: the provider watches
`shelfDensityProvider` and clears itself when the density changes, because a book
brought forward stops being forward when the density changes what "forward" means.
A row clearing it from `didUpdateWidget` would instead be mutating a provider from
inside a widget lifecycle callback, once per shelf, in the frame that is already
handling the change.

Nothing clears it when a book leaves its shelf, which the per-row version did.
With one id there is nothing to go stale: a book dragged to another shelf is still
the book being looked at and the receiving row draws it forward, and a deleted book
matches no row at all. Ids are unique, so a dangling one can never name a different
book.

**Reduced motion still turns the book out.** `TurningBook` draws a spine at
progress 0 and a cover at 1, so "skip the animation" cannot mean leaving the
controller alone — that left a reader with Reduce Motion on tapping a spine, getting
a spine, and then a details page on the second tap. The controller jumps to 1
instead.

### Hero tags only on face-out books

Reading books and the currently surfaced or turned one. This is the read pile's
own rule ("only that book carries the tag"), and it guarantees a flight always
starts from a cover that is fully on screen rather than from one three-quarters
hidden behind a neighbour.

### Edit mode: every density is edited as itself

| density       | edit mode draws       |
| ------------- | --------------------- |
| `covers`      | covers (unchanged)    |
| `spines`      | **spines, draggable** |
| ~~`leaning`~~ | ~~covers~~            |

An earlier draft of this design said "edit mode always draws face-out, regardless
of the active density", and gave three reasons. **Two of them were wrong about
`spines` and one was arithmetic on a number that did not exist.** The rule became
per-density, because that is where its reasons actually hold — and with `leaning`
withdrawn, both remaining densities are edited as themselves, so there is nothing
left to decide. `_effectiveDensity`, the getter that held the fallback, is gone with
it, as is the `slotExtent` override below.

That is worth knowing before adding a third density: one whose drawing _changes_ on
entering edit mode brings the whole problem back.

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
face-out at a time in the whole library, so one badge exists at a time and nothing
can collide. The two-step tap does double duty and no new affordance is invented.

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

### Transitions are a per-book turn, not a cross-fade

**Revised, and the earlier version of this section argued the opposite.** It is
kept below, because the reason it was wrong is worth having on the record.

Switching density is **every compressed book rotating on its binding**, hinged at
its left edge, from cover-on to spine-on — in a wave from the left, with the row
narrowing as they turn. One book's turn takes `kBookTurnDuration` (260ms), which
is what a book turning takes everywhere else in this app; the wave adds 0.35 of
the total, so the row takes **400ms**. A book in progress does not turn, in
either direction, because it is face-out at both densities. See
`shelf_density_turn.dart`.

The narrowing is the point. A book seen edge-on takes about a fifth of the width,
and watching the row close up _is_ the answer to "why is this state denser" — the
reader is shown the trade rather than told about it.

#### What the fade got wrong

The first implementation faded the row out over 90ms, swapped the drawing while
nothing was visible, and faded back. It was honest about being a cop-out: nothing
moved, so nothing was explained. A reader saw one shelf replaced by a different
shelf and had to work out what had happened to their books. "The same books,
drawn differently" is exactly the claim a cross-fade **cannot** make, because a
cross-fade is the transition you use for two unrelated things.

The cost argument was also wrong, in a way that is only visible with the code in
front of you. It said a per-book turn "would need a `BookChassis` per book, which
is the exact cost rejected when a chassis-based `leaning` variant was turned
down". But `leaning` would have paid that cost **at rest, forever, on every shelf
in the library**. The turn pays it for 400ms, on the one row a reader is looking
at, and hands back to `ShelfSpineTile` — whose width comes from the page count, so
`spines` still needs no cover decode and the row stays a lazy `ListView`. Those
are not the same cost, and conflating them cost the transition its meaning.

Nothing new had to be built. `BookWidget` already takes a `turnRadians` pose and a
`spine` face, `BookChassis` already renders a book at any angle, and the read pile
has turned single books out of a row of spines since it was written. This is that
turn applied to every book at once instead of to one.

#### Two things the turn does need

**Ratios, not points.** A cover's width follows its _decoded_ aspect ratio, so
nothing above `BookWidget` knows it, and every previous attempt at compressed
shelf geometry had to approximate it at `kDefaultCoverAspect` and then document
the approximation. Dividing the projection through by the cover width cancels the
unknown and leaves only `BookJitter.thicknessFactor`, which is hashed from the
ISBN and page count and so is known before anything loads —
`turningBookWidthFactor` and `turningBookHingeFraction` in `turning_book.dart`.
Fed to `Align.widthFactor` and `FractionalTranslation`, the box is the _exact_
projection of whatever width the cover turned out to be.

**A flag, not a controller reading.** The row's `build` chooses which tile each
book gets, and it runs on the frame the density changed — which is the frame the
controller was started on, when it still stands at the endpoint it is leaving. Ask
the controller _where it is_ and every book is chosen as a resting cover, nothing
ever re-chooses, and the row animates its margins closed around books that never
turn. Hence `_densityTurning`, raised before the controller starts. The bug was
found in a rendered frame, not by reasoning about it, which is the second time
this row has been saved that way.

One seam is accepted: `BookVertical.arch` is false on a chassis face, because a
notch cut into the head of one face of a solid object cannot exist beside a
full-height cover. So the arched heads appear at the instant the turn lands. This
is the tradeoff `BookVertical.arch` already documents and `TurningBook` already
lives with, at the other end of the same turn.

The withdrawn per-book turn on **entering edit mode** stays withdrawn, for the
reason that always applied: `spines` no longer redraws on entry at all, so there
is nothing there to transition.

## The control

In `_LibraryBar`, inboard of `GlassAvatarButton`, with an `AdaptiveIconButtonGap`
between them — the same slot relationship the gear has to Poke in the visit
state. `AdaptiveIconButton.svg` at `diameter: 44`.

**One cycling button**, `covers → spines → covers` (it was
`covers → leaning → spines` while there were three). The feedback is unmissable
because the entire library redraws — so the effect _is_ the affordance in a way it
would not be for eight states. A segmented pill was rejected: it costs 110–130pt of a
56pt bar whose own doc calls it "the most valuable row on screen" and records that
Edit and `+` were deleted from it for being duplicate entry points.

It stays a _cycle_ rather than becoming a boolean now that there are two states,
because that is where a third goes if one is ever added — `ShelfDensityCycle.next` is
a modulo over `values`, so the control never learns how many there are.

It shows **the state you are in**, not the state you would get. This is a mode
indicator, and with a two-tap-maximum cycle "what am I looking at" matters more
than "what will this do". The semantic label names the current state, so the
cycle is announced rather than silent.

Present in both the self and visit states of the bar, since the preference
applies to both libraries. Absent while editing, where density does not apply.

### Strings and glyphs

One semantic label per state in `app_en.arb` and `app_ko.arb`.

**Built with SF Symbols plus Material fallbacks, not with bundled SVGs** — the plan below
was written before checking the catalogs, and both have marks for both states, so there
was no reason to take the raster/mask trap on at all.

| state    | SF Symbol        | Material          |
| -------- | ---------------- | ----------------- |
| `covers` | `book.closed`    | `Icons.book`      |
| `spines` | `books.vertical` | `Icons.view_week` |

`book.closed` and not `book`: the latter's SF Symbol is an _open_ book, which says
"reading" rather than "cover". It needs iOS 14 and the floor is 15. The first version
used `rectangle.portrait`/`Icons.crop_portrait`, which was accurate about the geometry
and said nothing about books — and shared `Icons.crop_portrait` with the share card's
Fill toggle.

**Known collision:** `books.vertical` is also the Library tab's mark in
`shell_tab_bar.dart`, so in the `spines` state this button and that tab carry the same
glyph two rows apart meaning different things. Unresolved; replacing it is a design call.

---

The original plan, kept because the rasterisation trap in it is real and the next
bundled glyph will hit it. Three icon pairs in `svg_icons.dart` following the
`kStretchHorizontalIcon*` pattern exactly: a stroked SVG for Flutter (with an explicit
stroke, so renderers need not resolve Lucide's upstream `currentColor`), plus a raster
PNG for UIKit.

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
lib/providers/library_shell_provider.dart     + surfacedBookProvider: the one
                                              book forward in the library
lib/ui/widgets/shelf/shelf_book_tile.dart     today's _buildBookContent: cover,
                                              bookmark, delete badge
lib/ui/widgets/shelf/shelf_spine_tile.dart    a BookVertical spine, and the slot
                                              width that goes with it
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
  states, absent while editing, and cycles through every state.
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
