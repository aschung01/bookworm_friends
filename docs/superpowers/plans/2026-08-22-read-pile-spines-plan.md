# Read-pile spines — Implementation Plan

> **For agentic workers:** Implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax
> for tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this
> project has established Given-When-Then and layer-isolation conventions.

**Design:** `docs/superpowers/specs/2026-08-22-read-pile-spines-design.md`
**Drawings:** `docs/mockups/read-pile-turn/index.html`, root version `decided`. Rebuild with
`python3 _build/build.py && sh _build/verify.sh`; the drawing's own assertions pin the geometry this
plan implements, so **run them before and after** any change to a shared number.
**Prior art to read first:**

- `docs/superpowers/plans/2026-08-11-book-3d-chassis-plan.md` — Tasks 1 and 2 built `BookMetrics`,
  `BookJitter` and the three faces. Task 3 here adds the fourth and moves the pivot.
- `docs/superpowers/plans/2026-08-16-phase-2-read-view-plan.md` — Task 2 extracted `ReadPile`. Task 5
  here makes it stateful for the first time.
- `supabase/migrations/20260816160000_book_page_count.sql` — Task 1 is the same column shape and the
  same argument. Read its rationale before writing the new one.

**Goal:** Give each spine in the collapsed read pile its own height, thickness and cover tone, and
make a tap turn a spine out to its cover, which then behaves like a book on a shelf.

**What is genuinely new:** one database column, one colour function, a fourth face on
`BookChassis`, and state in `ReadPile`. Everything else is existing values that the pile currently
discards.

---

## What this changes, stated carefully

`ReadPile.extent` **does not move.** That is the load-bearing invariant of the whole plan, and it is
what makes the shell arithmetic — the collapsed detent, `sheetMidExtent`, `_swapPoint`,
`library_clearance_test` — survive untouched. The base height is 117 and not 124 precisely so that
`_rowExtent` stays 137.

Express the base as **derived**, never as a literal:

```dart
/// Pre-jitter spine height, derived so it cannot drift from the row it must fit.
static final double _spineBase =
    (_rowExtent - _praiseGrowth) / BookJitter.maxHeightFactor; // 124 / 1.06
```

If a future change raises `_rowExtent`, the books grow with it. If someone types `117`, they do not.

**The pile renders correctly before the column lands.** Every spine falls back to
`generatedCoverColor(isbn)`, so Task 1 can ship, backfill quietly for days, and Tasks 2–7 land on top
of a column that is already partly populated. Do not sequence the UI behind the migration.

---

## Task 1: `books.cover_color`

> **Done.** 14 new tests in `test/book_cover_color_test.dart`, all green. Full suite 719 passing / 5
> failing, and the 5 are the pre-existing `library_read_books_test.dart` set — the sixth known
> failure, in `shell_tab_bar_test.dart`, is no longer failing. `flutter analyze lib test` unchanged at
> 8 issues, none in a touched file.
>
> One thing came up that the plan did not anticipate: `Book` had **no imports at all**, and a
> `Color?` field needs one. `dart:ui show Color` rather than `package:flutter/material.dart`, so the
> model gains a type and not a widget dependency. Same import needed in `library_provider.dart`,
> where nothing had been pulling `Color` in transitively.

- [x] `supabase/migrations/20260822120000_book_cover_color.sql`. Follow `page_count`'s migration in
      form and in candour: state why a stored colour rather than a sampled one (`_sampleCoverColor`
      only answers after the image resolves, so a sampling pile paints grey on a cold start and
      colours itself in — the same objection `page_count` records for thickness), and why nullable (a
      value gives the spine its cover's tone, NULL routes it to `generatedCoverColor`; the two states
      drive different code, exactly as they do for `page_count` and exactly as they do not for
      `authors`).
- [x] `text`, nullable. **No CHECK** — a malformed value is ignored at the point of use rather than
      costing the row its book, same trade as `page_count`. **No index** — the only reader is a
      per-book widget rendering rows the app has already fetched in full.
- [x] `COMMENT ON COLUMN`, stating that it is `_sampleCoverColor`'s average and never shown to the
      reader as a value.
- [x] `Book.coverColor` as `Color?`. Parse defensively: absent on rows written before the column,
      and **unparseable means null**, not black. A `#RRGGBB` string is the wire format.
- [x] Add it to `copyWith`. Note that `copyWith` today omits fields it cannot change; `coverColor`
      **can** change (the backfill writes it), so it belongs in the signature.
- [x] `LibraryActions.addBook` writes it alongside `page_count`. Takes an optional `Color?`; the
      caller that supplies it is Task 4's business, and null is the ordinary case until then.
- [x] Tests: `fromJson` with the key, without it, and with garbage in it; `copyWith` round-trip.
      Also the wire format both ways — the round-trip, the dropped alpha, and **zero-padding**, since
      `toRadixString` drops leading zeros and would emit a five-digit value the parser then rejects,
      i.e. a book losing its colour the moment it was stored.

**Do not** write a server-side backfill. A server-side average would not equal Flutter's 1×1 GPU
downsample, so every book would visibly change tone the day it ran. The backfill is Task 4.

---

## Task 2: `spineTintFor`

> **Done.** 12 new tests in `test/spine_tint_test.dart`, all green. `flutter analyze lib test`
> unchanged at 8 pre-existing infos. The JS port in the mockup was brought back into step and now
> agrees with the Dart **byte for byte** on every probe — `#000000`, `#FFFFFF`, `#DCD8D1`, `#2A1C14`
> — including the cases that walk the 24-step darkening loop, which was the thing worth checking:
> Dart lerps in floating point while the port rounds to 8-bit at each step, and the two could have
> drifted apart over 24 rounds. They do not.
>
> Two things the plan did not anticipate, both found by the tests rather than by reasoning:
>
> 1. **A black cover was being recoloured.** Gating the lift on saturation alone fires on black as
>    hard as on white — black has no chroma either — so a black jacket came out a dark green spine.
>    The fix is a second factor, the cover's own luminance, which is why the lift is
>    `shortfall × luminance × kSpineTintChromaLift` and not the two-term product the plan describes.
>    With the third factor in, `kSpineTintChromaLift` had to rise from 0.35 to **0.45** for a pale
>    cover to land in the same place. Spec updated to match.
> 2. **The contrast step is not confined to washed-out covers.** `kGeneratedCoverPalette`'s amber
>    boards at 4.02:1, so the darkening loop legitimately fires on a fully saturated swatch. The
>    palette test could therefore not assert plain identity with `bookBoardColorFor` as written; it
>    asserts the property that actually matters instead — exactly one swatch darkens, and **no swatch
>    gains hue**.
>
> Constants shipped under `kSpineTint*` names rather than `kTint*`, so they read unambiguously beside
> `bookBoardColorFor` in the same file. `_tintDarkenStep` and `_tintDarkenMaxSteps` are private.

- [x] In `lib/ui/widgets/book/book_chassis.dart`, beside `bookBoardColorFor`, which stays exactly as
      it is and keeps its one caller (the back board).
- [x] Three named constants with their reasoning: `kSpineTintMinSaturation = 0.18`,
      `kSpineTintChromaLift = 0.45`, `kSpineTintMinContrast = 4.6`. The last is a hair over AA's 4.5
      so rounding cannot leave a tint just short.
- [x] Step one: HSV saturation below the floor blends the cover toward `greenThemeColor` by up to
      `kSpineTintChromaLift`, scaled by how far below it sits **and by the cover's luminance**.
      **Borrowed from the brand, not invented** — a washed-out cover's tint should be a desaturated
      version of the app's own green rather than an arbitrary hue.
- [x] Step two: darken in 6% steps toward black until white clears `kSpineTintMinContrast`, bounded
      at 24 iterations. Stepwise rather than closed-form because the target is a contrast ratio,
      which is not linear in the mix. Document the bound.
- [x] Doc comment must say what this is **for**: a back board carries no text and is seen against the
      cover it came from; a spine carries a 12pt title and is seen against its neighbours. That is
      why one function is not enough for both.
- [x] Tests:
  - every `kGeneratedCoverPalette` swatch and a set of saturated darks gain **no hue** — **the floor
    must be a no-op for most books, or it is a recolouring**. Exactly one swatch (amber) darkens for
    contrast, which is the reason this is not stated as identity with `bookBoardColorFor`;
  - `#DCD8D1` lifts: plain darkening gives 3.72:1 and this gives ≥ 4.5:1;
  - the lifted result has **more saturation** than plain darkening, not merely less lightness. A
    darker grey passes the contrast test and still reads as a hole in the shelf, so assert the
    property that actually matters;
  - a **black** cover is left exactly `bookBoardColorFor` — the case above, pinned;
  - a sweep of a few hundred synthetic covers: every result clears 4.5:1 and the loop always
    terminates inside its bound.
- [x] Mockup kept in step: the port in `docs/mockups/read-pile-turn/_build/data.js`, a black-cover
      assertion mirroring the Dart's in `_build/assert.js`, and the spec's corpus figures corrected
      (`#62776E` at 4.79:1, saturation 0.18).

---

## Task 3: the fourth face, and the pivot

> **Done.** 10 new tests in `test/book_chassis_geometry_test.dart`, in two groups
> (`spine placement`, `a book standing spine-out`). **All 24 pre-existing tests in that file pass
> unmodified**, which was the point of them.
>
> Two things were wrong in the plan and in my first implementation, and both were caught by writing
> the test the plan asked for and finding it failed:
>
> 1. **The pivot has to move the camera, not just the hinge.** Composing `T(p) · Ry · T(-p)` inside
>    the projection — the obvious reading, and what I wrote first — leaves the vanishing point on the
>    book's centre line. A cover hinged off that line is then not edge-on at `-π/2` at all: measured
>    **6.96pt of squashed artwork beside every spine in the pile**, 8.9% of a 78pt cover. The fix is
>    to wrap the projection too, `T(p) · projection · Ry · T(-p)`. It also buys the property the
>    pile's layout wants: a spine-on face lands at `w = 1` and projects at exactly `thickness`.
> 2. **The spine belongs _under_ the cover, not over it.** The plan says "painted **in front of** the
>    cover" and that is wrong for half the range. Below `0` the spine and cover fall on opposite
>    sides of the hinge and the order is free; above `0` the spine crosses onto the cover's side and
>    projects **8.7pt inside its silhouette**, where it has to be occluded. Both signs happen to the
>    same book — the pile turns one out to `0`, then a hold takes it to `+kBookTurnAngle` — so this
>    is a real case. One fixed order still suffices: under the cover, above the board and pages.
>
> The plan's `z ∈ [-thickness, 0]` is also a slip: the back board is at **+z**, so a spine at
> negative z would stand out of the front of the cover. The test asserts `[0, thickness]`.
>
> Neither error was findable in the mockup, and the reasons are worth keeping: its `perspective-origin`
> sat only ~4.7pt off the hinge, making the sliver sub-pixel, and CSS sorts a `preserve-3d` context by
> depth, so the drawing was correct in any DOM order. **The Dart is what made both legible.** The
> mockup, the spec and the drawn DOM order have all been corrected to match, and `verify.sh` is green.

- [x] `bookSpineLocalMatrix(BookMetrics)` in `book_geometry.dart`, the mirror of
      `bookPageLocalMatrix`: the plane `x = -width/2` spanning the book's depth, outward normal `-x`.
      Write the sign reasoning out — the drawing got it backwards once and rendered a book turning
      inside out, and the note in `frame.css` explains why the two conventions differ.
- [x] `BookChassis.spine` — an optional face, `metrics.thickness` wide, painted **under** the cover
      and over the board and pages. Null on every existing caller, so the shelves are untouched.
- [x] `BookChassis.pivot` (`Alignment`, default `Alignment.center`), threaded into
      `bookParentMatrix` — _not_ into `Transform.alignment`, which has to stay on the centre because
      every local matrix in the library is written about it. Update the class doc: today it says the
      paint order is correct for any `|turn| < π/2`; with a spine face and a turn that reaches `-π/2`
      that sentence needs restating.
- [x] Extend the documented turn range to `[-π/2, +kBookTurnAngle]` and state that **negative turn
      exposes the spine** because positive exposes the fore-edge.
- [x] Tests in `book_chassis_geometry_test.dart`:
  - the spine plane sits at the cover's left edge and spans `z ∈ [0, thickness]`, with no clearance;
  - the spine's outward normal is `-x`, pinned separately — a face can span the right depth and
    still face inward;
  - at `-π/2` the cover's projected width is **exactly** zero and the spine's is `thickness`;
  - at `0` the reverse;
  - the spine widens monotonically from `0` to `-π/2`;
  - the hinge edge does not move at any angle, and a centre pivot would move it half a cover width;
  - at `+kBookTurnAngle` the spine projects inside the cover's silhouette — the paint-order guard;
  - **the existing depth-at-rest tests pass unmodified.**

---

## Task 4: `BookWidget` — external jitter, external turn, and the colour write-back

> **Done.** 18 new tests — 10 in `test/book_pose_test.dart`, 8 in
> `test/record_cover_color_test.dart` — all green. Full suite back to exactly the 5 pre-existing
> `library_read_books_test.dart` failures; `flutter analyze lib test` unchanged at 8 pre-existing
> issues.
>
> Three departures from the plan, all argued in the code:
>
> 1. **The pose composes with the hold; it does not replace it.** The plan says exactly one of the
>    three turn sources may be non-null. That is right for `turnDrive` and wrong for `turnRadians`,
>    and following it would have cost the design goal: the spec says a book turned out of the pile
>    _behaves like a book on a shelf_, `+16°` on a hold. If the pose replaced the hold, `ReadPile`
>    would have to reimplement `kBookHoldDelay`, the press controller and the release curve, and
>    "behaves like" would mean "has a copy of". They are not two drivers of one quantity: the pose is
>    where the book has been put, the hold is how it answers your finger — an offset from wherever
>    that is. `turnDrive` is different in kind, being the hold itself relocated to another
>    recogniser, so it still replaces. An `assert` forbids passing both.
> 2. **The guards live in `recordCoverColor`, not at the three call sites.** It takes the whole `Book`
>    and checks ownership and `coverColor` itself. Three call sites each re-deriving "is this mine"
>    is three chances to get it wrong, and one of them — the details page — renders a friend's book
>    as readily as your own, so the check has to be dynamic regardless. The UPDATE is split behind a
>    `@visibleForTesting writeCoverColor` seam, because the rules _are_ the method and the write is
>    one line; the tests assert all four rules against the real method rather than a copy of it.
> 3. **`ShelfRow` and `ReadMonthGrid` became `Consumer`s.** Neither had a `ref`. Threading the
>    callback down instead would have added a parameter to `FinishedBooksSheet`, `LibraryPane` and
>    whatever builds them, all of which are `StatelessWidget`s too — the dependency would have
>    surfaced four levels up from where it is used. Both are documented as Consumers _only_ for this;
>    neither watches anything. `test/finished_books_sheet_test.dart` needed a `ProviderScope` in its
>    pump helper as a result: a one-line test-infrastructure fix, and closer to how the sheet
>    actually runs than no scope at all.
>
> One test-writing note worth keeping: `onCoverSampled` cannot be tested without `tester.runAsync`.
> `_sampleCoverColor` awaits `Picture.toImage` and `Image.toByteData`, real engine round trips that
> never complete inside `testWidgets`' fake-async zone — so the callback silently never fires and a
> test that only checks "nothing threw" passes for the wrong reason. The cover is primed into the
> image cache under an identical `NetworkImage` key rather than through a fake `HttpClient`, which is
> four classes of boilerplate for the same bytes, and the test asserts the exact colour
> (`#C81E64`) survives the 1×1 downsample rather than merely that something was reported.

- [x] `BookJitter? jitterOverride`. The existing `bool jitter` stays (the month grid passes false and
      must keep working); the override wins over both. The pile needs it because **the turned book
      must be exactly as thick as the spine that was tapped**, and the pile resolves that thickness
      itself.
- [x] `Animation<double>? turnRadians`, distinct from the existing `turnDrive`. `turnDrive` maps
      `0..1` onto `kBookTurnAngle` and cannot reach `-π/2`; rather than overload its range, take
      radians directly. Document how it differs from `turnDrive` in **both** respects — range, and
      that it composes with the hold rather than replacing it — and assert that the two are never
      passed together.
- [x] `spine` passthrough to the chassis, and `pivot`.
- [x] `ValueChanged<Color>? onCoverSampled`. **This is the backfill.** `_sampleCoverColor` already
      runs on every successful decode to pick the back board; this exposes the result. `BookWidget`
      itself does no I/O and gains no Riverpod dependency — it stays a presentation widget.
- [x] Wire it in `shelf_row.dart`, `read_month_grid.dart` and `book_details_tab_view.dart` to a new
      `LibraryActions.recordCoverColor(book, color)`, **only for books the signed-in user owns and
      only when `book.coverColor` is null** — enforced inside the action, so a new call site cannot
      forget it. A friend's row is not yours to write.
- [x] `recordCoverColor` must be idempotent and silent: no `EasyLoading`, no rethrow, no provider
      invalidation. It is a cosmetic column being filled in from a render path, and an offline device
      must not surface an error for it. Debounce per book id for the session so a book scrolled past
      twice writes once — the id is claimed _before_ the await, since two decodes can land in one
      frame and an async gap between the check and the mark is long enough for both to pass it.
- [x] Tests: the override reaches `BookMetrics` and beats `jitter: false`; `turnRadians` poses the
      chassis at `-π/2` and the hold offsets that pose in both directions; passing both turn sources
      asserts; `onCoverSampled` fires once per decode with the right colour and never for a generated
      cover; `recordCoverColor` writes once for an owned colourless book and is a no-op for a book
      that already has a colour, a book owned by someone else, a signed-out reader, a repeat in the
      same session, a concurrent duplicate, and a write that failed.

---

## Task 5: `ReadPile` — sizes, tones, and one open book

`ReadPile` is a `StatelessWidget` today. It becomes stateful, and this is the first state it has ever
held.

> **Done.** 20 new tests in `test/read_pile_spines_test.dart` (16 for this task, 4 for Task 6), all
> green, plus a new renderer at `test/read_pile_render_preview.dart`. `ReadPile.extent` is still 169,
> asserted. The two tests the plan said must pass unmodified — the empty message centred in the
> visible sheet, and the plank pinned through a drag — do.
>
> **The renderer earned its place immediately.** Six frames written to `build/pile_preview/`, copied
> into `docs/mockups/read-pile-turn/_build/shots/flutter/` so the code sits beside the drawing. The
> resting row and the mid-turn frame confirmed by eye what no assertion states: the spine sits left of
> the hinge with the foreshortened cover to its right, the sign is right, and a book turning out does
> not turn inside out. The sixth frame exists because of a gap the other five could not close — in a
> row where every book has its own tone, a **missing separator looks exactly like a present one**. So
> it draws three books of one colour at 6×: either three books or one wide block, no third
> possibility. It is three books.
>
> Departures and findings:
>
> 1. **`BookVertical.onTap` became nullable, and that is load-bearing rather than tidy.** The same
>    widget is handed to `BookChassis.spine`, and the chassis hit-tests through one detector wrapping
>    all four faces — a detector _inside_ a face would claim taps meant for the cover, and would claim
>    them at the **untransformed** position, since the faces are laid out with
>    `transformHitTests: false`. A spine face has to be inert.
> 2. **The row clips with `Clip.none`, as the shelves already do.** A turned-out book carries the
>    stacked shadows that separate a cover from the plank and they fall outside the row's box.
> 3. **`isEditMode` had to be threaded from `FinishedBooksSheet`**, which already had it. One
>    parameter, no new plumbing.
> 4. **The open book's thickness moves once its jacket decodes**, by a few percent, because
>    `readSpineMetrics` resolves at `kDefaultCoverAspect` and the chassis picks up the real ratio. It
>    cannot be avoided without decoding every cover in the pile, which is the thing the pile exists
>    to avoid. It lands _after_ the turn, on a book whose spine is by then edge-on and whose cover is
>    what is being looked at — which is where a change of shape belongs. Documented on
>    `readSpineMetrics`.

- [x] `readSpineMetrics(Book)` — **one** function returning the jitter and the `BookMetrics` for a
      book in the pile, used by the flat spine, by the chassis that replaces it, and by the row that
      lays both out. Two call sites computing the same number is how the spine and the cover come to
      disagree about thickness.
- [x] Heights from `spineBase × BookJitter.fromIsbn(...).heightFactor`; thickness from
      `BookMetrics.thickness`. `spineBase` is **derived** — `(rowExtent − praiseGrowth) /
BookJitter.maxHeightFactor` — so the tallest book is exactly the 124pt every spine used to be
      and `extent` stays 169 by construction. A test sweeps 3,000 ISBNs against `rowExtent`.
- [x] `BookVertical` gains `fill` (a resolved `Color`, replacing the `opacity` computation at the call
      site) and `separator` (the 1pt inset line). Keep the `opacity` path for any other caller —
      there is none today, but the widget is public. The title colour rule stays: white above 0.7,
      `primaryText` at or below, and a tinted spine is **always** white because `spineTintFor`
      guarantees it.
- [x] Fill = `spineTintFor(book.coverColor ?? generatedCoverColor(book.isbn))`. No network, no decode,
      correct on the first frame whatever state the backfill is in. A test asserts the resting pile
      builds **no `BookWidget` at all**.
- [x] `_openId` (`String?`, the book id). Tap a spine to open; tap another to open that one and close
      this one; both animate on the same controller timings. Two controllers, not one: a single
      controller cannot run forward for the incoming book and back for the outgoing one, and the
      outgoing book snapping flat under the incoming one is what the plan was ruling out.
- [x] The open book is a `BookWidget` with `spine:`, `pivot:` at the spine edge, `jitterOverride:`,
      and `turnRadians:` driven from `-π/2` to `0` over `kBookTurnDuration`. Its layout width is
      `cover×|cos| + thickness×|sin|` — non-monotonic by ~3pt near the end, which is accepted and
      documented, because it is what a real book does. The chassis box is offset by
      `thickness × |sin|` so the drawing's left edge is the slot's, exactly as the drawing's `--ox`
      does; the `BookWidget` is built once outside the `AnimatedBuilder`, or the turn would
      re-resolve the cover on all sixteen frames.
- [x] `kTurnMargin = 8` of horizontal margin at full turn, scaled by the same progress as the
      rotation, so **the resting pile's density is unchanged until someone taps**.
- [x] The row does not clip the open book's shadows: `clipBehavior: Clip.none`, which is what
      `shelf_row.dart`'s own list already passes, so this is the house answer rather than a new one.
      **Still unverified on a device** — the renderer shows the shadow present and unclipped at the
      sizes it draws, but the plan's point stands that this is the kind of thing a widget test cannot
      settle.
- [x] Close on: a year filter change, `isEditMode`, and the sheet passing `LibrarySheet`'s swap point.
      The last one needs no new plumbing — the grid replaces the pile, and the pile is disposed. A
      fourth was added that the plan did not list: a book **leaving the list** while open, which would
      otherwise leave `_openId` pointing at nothing and a controller running.
- [x] The empty state and the plank are untouched. The two tests from the previous change — the empty
      message centred in the visible sheet, and the plank pinned to the card's bottom edge through a
      drag — pass unmodified with variable heights.

---

## Task 6: the Hero, and the comment it reverses

> **Done.** 4 tests, in the `the Hero, and why it is now safe` group of
> `test/read_pile_spines_test.dart`. The resting pile builds **no `Hero` at all**, which is the
> cleanest possible answer to the old objection: it was not that thirteen tags were unlikely to
> collide, it is that there are no tags until a book is turned out.

- [x] `heroTag: 'book_${book.isbn}'` on the **open book only**. Never on a spine.
- [x] Rewrite the comment at `book_details_tab_view.dart:151`. It currently says "The pile and the
      month grid fly no book either, for the same reason." The month grid still flies nothing; the
      pile now does. Record both halves of why it is safe: `withoutFinishedBooks` keeps a finished
      book off the shelves so there is no second `book_<isbn>` on the route, and only one book in the
      pile is open so the tag is unique **even though `book_<isbn>` collides across the fifteen
      migrated books with no ISBN**. The rewrite also keeps the sentence it replaces, and says why it
      was right at the time — a comment that quietly reverses itself teaches nothing.
- [x] `flyShelfFromLibrary` stays `book.status != bookStatusFinished`. The pile's plank is shared by
      every book standing on it and is not a particular shelf's, so there is still nothing for it to
      fly to.
- [x] Test: a pile of books that all have an empty ISBN opens one and navigates without throwing.
      That is the test that would have caught the collision if every spine had been tagged. Paired
      with one that walks the whole two-tap path: the first tap turns the book out and pushes nothing,
      the second pushes `AppRoutes.details`.

---

## Task 7: tests and verification

> **Done, except the device pass.** Everything checkable without a simulator is checked; the six
> by-eye items below are **not**, and are the only thing standing between this and shipped. `flutter
analyze lib test` is back at its **8-issue baseline** (not merely at or below — the same 8, all
> pre-existing, none in a touched file). The suite is **795 passing / 5 failing**, and the 5 are the
> same `library_read_books_test.dart` set that was failing before any of this started.
>
> 66 tests added across the seven tasks: 14 (`book_cover_color`), 12 (`spine_tint`), 10
> (`book_chassis_geometry`), 10 (`book_pose`), 8 (`record_cover_color`), 22 (`read_pile_spines`). Two
> renderers, one of which — `read_pile_render_preview.dart` — is new and paid for itself in the first
> run.

- [x] `flutter analyze lib test` at or below its current count. **At** it: 8, unchanged.
- [x] **`ReadPile.extent == 169`** as an explicit assertion. It is the invariant the base-117 decision
      exists to protect, and if a clearance or sheet test needs editing then the base is wrong — do
      not edit the test. Nothing needed editing.
- [x] `test/book_geometry_test.dart`'s hash and jitter goldens are **untouched**, and pass. Nothing
      here changes the hash.
- [x] New: one spine open at a time; tap turns out; hold turns +16° and, because the pile passes no
      `onLongPress` and so has no stage two to suppress the tap, a hold of _any_ length still ends in
      navigation — asserted, because "nothing happens on a long press" and "a long press swallows the
      tap" look identical until you hold a book for two seconds and it does nothing at all; the tint
      of a spine equals `spineTintFor` of the stored colour when present and of the generated colour
      when not.
- [x] Pre-existing failures: `test/library_read_books_test.dart` (5) and `test/shell_tab_bar_test.dart`
      (1) were already failing before this work, from in-progress shell changes. **Not fixed here.**
      Only 5 remain — the `shell_tab_bar_test.dart` one stopped failing on its own, which was noted at
      Task 1 and has held since.
- [ ] Device verification on an iPhone 17 Pro / iOS 26.4 simulator. **Outstanding.** What the widget
      renderer at `test/read_pile_render_preview.dart` _can_ settle is recorded beside each item; the
      rest genuinely needs a device.
  - the turn reads as a book coming off a shelf, not as a card flip — the renderer's mid-turn frame
    shows the three-quarter view, and the spine on the correct side of the hinge, which rules out the
    one failure that would look like a card flip. **The motion itself is unchecked.**
  - the 1pt separator is enough at 1× and not too much at 3× — _present and legible_, confirmed by a
    dedicated frame of three same-toned spines at 6×. Whether it is the right weight is a judgement
    that needs a screen.
  - the 8pt margin reads as air and not as a gap in the row — unchecked.
  - a pale cover's lifted tint reads as a pale book — the resting frame shows `#DCD8D1` as a muted
    sage among nine other tones and it does read as a book rather than a hole. Worth a second look at
    real brightness.
  - the pile at 2× accessibility text, where the spine title has to ellipsize much sooner —
    unchecked, and the renderer cannot help: no real font is loaded, so every title is a box.
  - dark mode, which nothing on this page has looked at yet — **unchecked, and still the least
    examined thing here.** See the risk table below.

---

## Post-implementation: three bugs, and the backfill

All found _after_ every task was checked off and green. Two were caught by rendering, and the third by
the backfill's own verification step — none of them by an assertion.

### 0. `_sampleCoverColor` was not averaging anything

**The worst of the three, and it predates this whole change.** The average cover colour was taken by
drawing the image into a 1×1 rect with `FilterQuality.medium` and reading the pixel, on the theory
that a huge downscale builds a mipmap chain whose last level is the mean. Skia's software backend does
roughly that. **Impeller, which is what iOS runs, does not** — at a 1×1 destination it effectively
returns a single texel.

Measured against 56 rows a real device had written: **0 correct, median drift 42/255, worst 118**, and
the device's answers were _more saturated than any average can be_. A mostly-white jacket with heavy
black type was stored as near-white `#EFEAEB` where its mean is `#A6A3A4`. Every back board in the app
has been tinted from an arbitrary pixel of its cover since the chassis shipped.

No test noticed because the only test of it used a **solid-colour** image — for which a single texel
and the mean are the same number. `test/cover_sample_test.dart` now leads with a half-black,
half-white image, which is the smallest input that tells an average from a sample.

`averageCoverColor` moved to `lib/ui/widgets/book/cover_sample.dart` and is now pure Dart: an
alpha-weighted mean over `rawRgba`'s premultiplied bytes, which makes the straight-alpha mean fall out
as `Σ(r·a/255) / Σ(a) · 255` with no per-pixel divide. Three properties follow, and the third is what
made the backfill possible at all: it is correct, it is cheap (21k pixels for a Kakao `R120x174`
thumbnail, not the "few hundred thousand" the old comment justified the GPU with), and it is
**deterministic** — no renderer, backend or platform in the answer, so a phone, a widget test and a
command-line tool produce the same value.

Averaged in sRGB rather than linear light, deliberately. Linear is the physically correct way to
average light and the wrong answer here: it weights bright pixels by true luminance, so any cover with
a light background comes out near-white — the same failure the single-texel sampling produced. This is
a surface tone, and a gamma-space mean is the one that reads as "the colour of that book".

### 1. The spine's arch cut a notch the cover did not have

`BookVertical` arches its head by 5pt at each edge — a stylisation that works on a flat drawing and
**cannot survive being one face of a solid object**. The cover beside it is full height, so at the
hinge the spine's head sat 5pt lower and the **back board showed through the gap in a different
tone**. It reads exactly as what it is: the spine and the cover being two different heights.

Fixed with `BookVertical.arch`, default true so the resting pile is untouched; the chassis's spine
face passes `false`. The cost is a one-frame change of head shape at the instant a flat spine is
swapped for a chassis — taken deliberately, because that frame is also the first frame of a 260ms
rotation in which the whole silhouette is already moving, whereas the notch was a grey wedge visible
for the entire turn.

### 2. The spine face was mirrored

`bookSpineLocalMatrix` composed the strip the wrong way round. It landed in exactly the same place,
spanned exactly the same depth, and passed **every one of the ten geometry tests** — while being
reflected about its vertical axis. Every spine title would have read backwards and the hairline would
have sat on the wrong edge.

This is the same trap `frame.css` records from the CSS side — "a back-facing plane in CSS renders
mirrored, so the +90 version drew every spine title in reverse" — and the two frameworks disagree
about which sign is the mirrored one, so the note did not transfer. The port got the position right
and the handedness wrong.

Found by rendering a red block at the face's top-left and a blue one at its bottom-right and watching
them come out top-right and bottom-left. The fix is `T(-half, 0, thickness - half) · Ry(+π/2)`, which
makes the face's **right** edge the hinge — the same end the drawing uses, and the end the separator
belongs on.

The guard is a new test, `is not mirrored`, which composes the whole chain and asserts the **order of
two points on screen**. Nothing about the matrix's entries can catch this; the `faces left, out of
the book` test it replaces was asserting a property of an axis no flat face has.

### The backfill, run

`test/cover_color_backfill_tool.dart` — a tool, not a test. It dumps rows with the Supabase CLI, samples
each cover with **`averageCoverColor` itself**, and emits a reviewable SQL file. It reads no
credentials and touches no database.

Run against the linked project: **471 of 472 books sampled, no failures, all applied.** The 472nd has
no thumbnail, so `generatedCoverColor(isbn)` is the right answer for it. The 56 rows that already had
a colour were **corrected rather than skipped** — they were single-texel values, and
`recordCoverColor` declines a book that already has a colour, so nothing else would ever have fixed
them.

Two traps worth keeping:

- `flutter_test` installs an `HttpOverrides` that answers every request with a 400, which is why
  `NetworkImage` fails in tests and why several tests here rely on that. A tool needs the real client
  — and the override has to be cleared **before** the `HttpClient` is constructed, because the factory
  resolves it once. Getting that order wrong reports "sampled 0 of 56" with a 400 for every URL, which
  looks exactly like a CDN refusing the requests.
- Doing this in SQL was never an option, and now there is a number for why: median drift 42/255
  between a plausible-looking average and what the app actually produces.

### Still open: the chroma lift homogenises a real library

> **Resolved.** The chroma lift is gone — see "Decided and shipped" below. Kept for the measurements.

`kSpineTintMinSaturation = 0.18` was tuned against the drawing's 13-book corpus, where **1 of 13**
covers fell below it. Against 471 real averaged covers, **228 do** — averaging a colourful jacket with
white paper and black type desaturates it, so about half a real library is near-neutral.

Because the lift blends toward one fixed hue, those books all converge on roughly the same muted
teal-green: `#CDCEDA` (pale lavender) → `#617575`, `#A2B4A3` → `#617669`, `#A9B9B0` → `#62786F`. Three
distinguishable covers, one spine colour. Rendering the real library shows four such spines in eleven.

The fix is probably to **raise the cover's own saturation rather than blend toward the brand**, keeping
its hue — pale lavender becomes grey-blue, khaki becomes khaki — and to fall back to the brand only
when there is no hue left to preserve. Not done: it changes a decided design value and wants a
decision.

### Still open: what "the colour of a book" means

> **Resolved.** See "Decided and shipped" below. Kept for the measurements, which are the argument.

Two questions from the same root, and they turn out to be one decision.

**We are literally mixing every pixel.** `averageCoverColor` is an alpha-weighted mean over the whole
jacket — background, type, artwork, margins. So a bright yellow cover with black type and a small
illustration averages to dark olive: `주식투자 안내서` is `#979015`. Nothing is wrong with the mean; it is
just answering "what is the average of this image" when the question people ask is "what colour is
this book".

**The background is recoverable.** Two approaches, measured on real covers:

1. **Histogram mode over the whole cover** — `dominantCoverColor`. Does not work, and the reason is
   worth keeping: 5-bit quantisation collapses every near-black pixel into a couple of bins while a
   real background spreads across many (gradients, JPEG ringing), so **black type reliably beats the
   background**. `역행자` returns `#020101` on 21% of pixels; `주식투자 안내서` returns `#010101` on 26%.
2. **Histogram mode over the border ring** — `coverBackgroundColor`. A cover's background is the thing
   that reaches its edges, so this counts only the outer 8% and ignores type and artwork by
   construction. It also yields a free confidence measure: what fraction of the ring agrees.

| book                 | mean      | whole-cover mode | border    | share    |
| -------------------- | --------- | ---------------- | --------- | -------- |
| `세이노의 가르침`    | `#FAFAFA` | `#FFFFFF` 94%    | `#FFFFFF` | **100%** |
| `Clean Code`         | `#F9F7F2` | `#FFFFFE` 63%    | `#FFFFFE` | **82%**  |
| `주식투자 안내서`    | `#979015` | `#010101` 26%    | `#FEEE02` | **48%**  |
| `5000일 후의 세계`   | `#585160` | `#040001` 14%    | `#040001` | 42%      |
| `역행자`             | `#855029` | `#020101` 21%    | `#010101` | 23%      |
| `어떤 화장실이 좋아` | `#8FA7CC` | `#83ABDC` 10%    | `#83ABDC` | 16%      |
| `곰돌이 팬티`        | `#DDA7A4` | `#F4F4F3` 13%    | `#C39D6D` | 15%      |

The share separates the two groups cleanly. Everything at 42% and above is the real background;
everything at 23% and below is a cover whose art bleeds to the edge, where the mean is the better
answer. `역행자` is the honest hard case — an orange jacket with black bands top and bottom, so _no_
method finds the orange and the mean's brown is the sensible fallback.

Across all 471 covers, at a 0.35 threshold **47% would use the background** and the rest the mean.

**The two open questions are one decision.** A yellow spine needs both halves: the background colour
_and_ a relaxed floor. `spineTintFor(#FEEE02)` darkens it straight back to olive, because the floor
exists to make room for white type. Likewise a white book needs the background (`#FFFFFF`) _and_ dark
type _and_ the outline. Together they also dissolve the homogenisation problem above, since a
background colour is saturated and the chroma lift mostly stops firing.

Shipped and inert, awaiting that decision:

- `dominantCoverColor` and `coverBackgroundColor` in `cover_sample.dart` — **not wired to anything**.
- `BookVertical` derives its title colour from the fill instead of assuming white, and outlines a fill
  that would vanish against `surface`. Both are no-ops for every tint the pile produces today.

If it goes ahead: `books.cover_color` keeps one column and stores the _resolved_ colour — background
when the border agrees, mean otherwise. That bakes the policy at write time, which is acceptable
because re-running the backfill over the whole library takes about three minutes.

### What this says about the test suite

Three bugs, all of them in code with tests over it. The geometry tests measured _where_ a face is and
every one is invariant to reflection; the sampler's test used the one input for which a broken sampler
looks correct. `test/read_pile_render_preview.dart` costs one `flutter test` run and has now found
four things: the separator's presence, the arch notch, the mirror, and the homogenisation above.

---

## Decided and shipped: the spine is the colour of the book

Both "still open" questions above were one decision, and it was taken. **A spine now shows its cover's
background colour, unadjusted except for a contrast floor that can lighten as well as darken.**

### What changed

|               | before                                                                                                          | after                                                                                   |
| ------------- | --------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| stored colour | `averageCoverColor` — the mean of every pixel                                                                   | `coverToneColor` — the border ring when ≥ 35% of it agrees, else the mean               |
| spine fill    | `spineTintFor` — chroma lift toward the brand, then `bookBoardColorFor`, then darken until white type clears AA | `spineToneFor` — the cover, pushed **away from whichever ink reads better** until 4.6:1 |
| spine title   | always white for a resolved fill                                                                                | the ink `spineToneFor` chose, passed through as `BookVertical.titleColor`               |

The two halves are inseparable, which is why they shipped together: `spineTintFor(#FEEE02)` darkened
the yellow straight back to olive, so the background colour alone would have changed nothing visible.

### `spineToneFor`, and the one thing that is easy to get wrong

The walk's direction is taken from **the chosen ink's own luminance**, not from which parameter it
arrived in. That is not defensive coding, it is dark mode: `AppColors.dark.primaryText` is `#F1F3F5`, so
threading `context.colors.primaryText` in as `darkInk` gives you two _light_ inks, no dark ink at all,
and a white jacket forced down to a mid grey to make room for off-white type.

So the inks are `kSpineInkLight` / `kSpineInkDark` — **constants, not theme colours.** A spine's fill is
opaque; it covers `surface` completely, so legibility on it cannot depend on the theme, and a white book
stays white when the lights go off. `kSpineInkDark` is a copy of `AppColors.light.primaryText` and
`test/spine_tone_test.dart` pins the two together so the copy cannot rot.

### The policy lives in `lib`, once

`coverToneColor` is in `cover_sample.dart` and **both** writers go through it: `BookWidget`'s render
path and `test/cover_color_backfill_tool.dart`. This is load-bearing rather than tidy. `recordCoverColor`
skips any book that already has a colour, so a row written under one policy would never be revisited
under the other — a book sampled on a device would keep a visibly different spine from an identical book
that was backfilled, forever.

`kCoverBackgroundMinShare = 0.35`. Across 471 covers: 0.30 → 56% take the ring, **0.35 → 47%**, 0.40 →
41%, 0.50 → 32%. Cheap to revisit; a full re-sample is about three minutes.

### Backfilled for one reader first

`@aschung` only, 74 rows (`--dart-define=user=<uuid>`), because **the rendering change cannot be scoped
per user — only the data can.** His numbers: 68% took the border ring (against 47% library-wide, so his
shelf is unusually flat-covered), 50 of 74 rows changed, 7 are now pure `#FFFFFF`, and `주식통자 안내서`
finally stores `#FEEE02` instead of `#979015`.

Rollback is `build/backfill/rollback.sql`, generated from the dump before the write.

**The other 397 books did not move, but they do render differently**, because `spineToneFor` replaced
`spineTintFor` for everyone. Their spines are now their stored _mean_, undarkened, rather than a
darkened green-shifted version of it. That is a strict improvement and it is unverified by eye.

### Verified by rendering, not by numbers

`test/read_pile_real_preview.dart` draws the actual library from the tool's TSV, before and after, at
equal spine sizes so the two frames can be flicked between.

The finding that mattered came from the magnified frame. At 2× across a 720pt overview, 30 near-white
spines look like holes in the shelf and the change looks like a mistake. At 6× — which is much closer to
a 26pt spine on a 3× phone — the same twelve books read as twelve books: the `separator` hairline, the
arched heads and the dark titles all carry. **The overview was lying about the scale**, which is the
same class of error as validating a colour policy on thirteen drawn books.

This reverses the spec's original argument that one dark-on-pale label in a row of white ones "looks
like a mistake". That was reasoning from a corpus where 1 book of 13 was pale. At roughly half a real
library it reads as intentional.

### Bug 4: the pale outline had no head — reported from a device screenshot

The outline was a `Border.all` **inside** the `ClipPath`, under a comment claiming the clip made it
"trace the head rather than boxing it". It does no such thing. A box border's top edge is a straight
line at `y = 0`; the arch reaches `y = 0` only at its centre and is at `y = 5` at both corners. So the
clip **erased** almost the whole top edge and kept the two vertical sides.

Every pale book therefore rendered as two hairlines with no head, and on a white jacket that is a spine
whose top has dissolved into the sheet. Measured: **2 of 30 columns** carried an outline pixel in the top
8 rows.

Fixed by extracting `bookSpinePath` — shared by the clipper and a new `BookSpineOutlinePainter` — and
stroking the real silhouette as a `foregroundPainter` over the clip instead of a rectangle under it. The
painter insets by half a stroke width, because a stroke is centred on its path and tracing the clip
boundary itself would leave half the line outside the shape.

**No tree-shaped test could have caught this, and that is the lesson.** The `DecoratedBox` was in the
tree with the right colour and the right border width. `find.byType` would have found it; every
assertion about it would have passed. Only pixels knew, and it took a screenshot from a device to
notice. `test/book_vertical_outline_test.dart` reads them, and was verified by reintroducing the bug and
watching it fail.

One trap in writing that test, kept because the first draft of it **passed against the reintroduced
bug**: it compared a gamma-space channel mean against `computeLuminance() * 255`, which is linear-light.
On those mixed scales the `#EFF5EF` sheet showing _outside_ the arch scored as "darker than the fill" and
satisfied the assertion. The pixel tests now draw white-on-white, where the only non-white thing in the
frame is the thing under test; whether the outline fires on the real sheet colour is a separate,
genuinely tree-shaped question and is asserted separately.

### The outline was also measuring the wrong background

`BookVertical` decided a spine needed an outline by measuring contrast against `context.colors.surface`
(`#FFFFFF`), but the pile is the `collapsedBody` of a sheet whose background is `sheetBackground`
(`#EFF5EF`). Fixed: `BookVertical` takes an optional `background` and `ReadPile` passes the sheet's.

A real gap rather than an inelegance, and it failed in the unsafe direction. `#E4E4E4` scores 1.27:1
against `surface` and 1.15:1 against the sheet, so the old code declared "no outline needed" for a spine
that has no edge where it is actually drawn.

### `docs/mockups/read-pile-turn/` is knowingly stale

Its JS port still implements the chroma-lift design, and `verify.sh` still passes because it tests its
own self-consistent port. Rebuilding it around the background-colour design is a follow-up.
`kSpineTintMinSaturation` and `kSpineTintChromaLift` survive in `book_chassis.dart` as `@Deprecated`
constants only so a reader comparing the drawing to the code finds the numbers.

---

## Risks

| risk                                                        | mitigation                                                                                       |
| ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| the write-back is a mutation from a render path             | Task 4: owner-only, null-only, debounced, silent, no invalidation                                |
| two taps to the details page where there is one today       | a tap anywhere on the open book navigates immediately; the first tap is the only new step        |
| the row's clip shaves the open book's shadows               | cross-axis visible, horizontal hidden; **verify on device**                                      |
| `_rowExtent` and the base drift apart, clipping a tall book | derive the base from `_rowExtent`, and assert no drawn book exceeds it                           |
| dark mode was never drawn                                   | `spineTintFor` darkens toward black, which is wrong on a dark surface — check it before shipping |

**The last one is the least examined thing in this plan.** The drawings are light-mode only. A tint
that darkens for contrast against white type is still fine on a dark sheet — the type is white in
both — but the 1pt separator at black 28% will disappear, and `BookChassisColors.of` already has a
precedent for the fix: its dark map does not simply reuse the light values, and says why.

---

## Deliberately not in this plan

- The month grid keeps `jitter: false` and gains no hero.
- No change to the empty state, the filter, the plank, or the sheet's detents.
- No stage-two long press, no reorder, no swipe-to-remove in the pile.
- `taller-pile` (base 124) stays a rejected branch in the drawings, browsable, not built.
