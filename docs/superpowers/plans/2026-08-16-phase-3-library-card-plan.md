# Phase 3: the Library Card — Implementation Plan

> **Status: complete.** All 39 items done, **including the migration and the backfill against the live
> database.** 320 tests green (250 before the phase), `flutter analyze lib test` unchanged at its
> 11-issue baseline, and the card verified on an iPhone 17 Pro / iOS 26.4 simulator — including opening
> the exported PNG, which is where two of the four bugs were hiding.
>
> **The audit was the phase.** Counting the rows and querying the catalogues before writing code cut
> two of the five drawn stats and changed the shape of a third, and none of that would have been
> discoverable afterwards — a `page_count` column would have shipped 35% full and looked fine.
>
> Four bugs came out of building it, and the pattern from Phases 1 and 2 held: **the ones that
> mattered were found by measuring and by looking.**
>
> |                                                                              | found by                                                   |
> | ---------------------------------------------------------------------------- | ---------------------------------------------------------- |
> | `CrossAxisAlignment.stretch` in a `Row` inside a min-height `Column` — crash | writing the geometry test before the device run            |
> | **the uncapped card overflowed the library by 95pt at 2× text**              | re-measuring the clearance, which is what that file is for |
> | **every glyph in the exported PNG had a yellow double underline**            | **opening the exported file**, not the share sheet         |
> | the tiles' labels were unreadable and their edges dissolved into the sheet   | **looking at the first device screenshot**                 |
>
> The third is the one worth remembering. The card renders correctly on screen, its widget tests pass,
> and the share sheet reports a plausible 251 KB PNG — and the image was still wrong, because the
> capture hosts the card in the `Overlay`, which has **no ancestor `Material`**, and `MaterialApp`
> installs a fallback `DefaultTextStyle` for that case carrying a yellow underline. Every `Text` on
> the card sets its size, weight and colour, so all of those were overridden and the _decoration_ was
> not. Nothing short of looking at the artifact would have caught it, which is exactly why Task 5's
> "done when" was written that way.
>
> The second changed a design decision. This plan argued the Card should stay uncapped because "a card
> that has to scroll is a card that says too much" — and `card-open` was drawn at **h:74** all along.
> The drawing was right and the plan was wrong; the Card now shares the read view's cap.
>
> **A fifth bug, reported by the user rather than found here:** the collapsed sheet's title was
> **centred**. `LibrarySheet`'s chrome column used the default `center` cross-axis alignment, so a
> header that fills the width (the read view's, Friends') looked right while the Card's bare
> `LibrarySheetTitle` — a `Row(mainAxisSize: min)` — sat dead centre. Fixed at the root with
> `stretch`, which is the same trap `GeneratedCover` and `BookPageBlock` both fell into.
>
> One drawing did not survive contact, and it is recorded in `decided.html`'s `stats()`: the hero's
> page figure and the Rating tile are gone, and Pace now states its sample size.

> **For agentic workers:** Implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax for
> tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this project has
> established Given-When-Then and layer-isolation conventions.

**Design:** `docs/superpowers/specs/2026-08-14-library-shell-design.md` — "Library Card", "Phasing"
**Drawings:** `docs/mockups/library-shell/decided.html` — `card-open`, `card-down`, the `library-card`
flow, and the "Stat card" element
**Phase 1:** `docs/superpowers/plans/2026-08-14-phase-1-shell-plan.md` — Task 7 has the device recipe
**Phase 2:** `docs/superpowers/plans/2026-08-16-phase-2-read-view-plan.md` — read its Task 1 and Task 3
before touching `LibrarySheet` or the year filter; both are reused here rather than rebuilt.

**Goal:** Turn the Card tab from a 96pt empty state into the Library Card — a hero tile and a small set
of stat tiles derived from the books you have finished, with the card shareable as an image. One new
column (`books.authors`) and one backfill; every other stat is a pure derivation over rows the app
already fetches.

---

## The data audit, done first, because it changes the phase

The design record says this phase:

> **Needs `books.page_count` and `books.authors` plus a backfill** — both are already returned by every
> search provider and currently discarded, so capturing them early is cheap.

**That is half wrong, and the wrong half is the expensive one.** Checked against the code and against
the live catalogue APIs:

| Stat as drawn               | Ships? | Why                                                            |
| --------------------------- | ------ | -------------------------------------------------------------- |
| Books read — **12**         | ✅     | `status` + `finish_date` exist and are already fetched         |
| **4,180 pages**             | ❌ cut | no provider can answer for these books — see below             |
| **86 days**                 | ✅     | recomputed as elapsed span, over books that have one           |
| Pace — **9d** per book      | ✅ ⚠️  | ships, but only over books with a real span, and says how many |
| Rating — **4.2** of 12      | ❌ cut | 624 of 624 rows are `rating: null`, and no UI can set one      |
| Most-read author — Han Kang | ✅     | needs the new column; Kakao answers for 40/40 sampled books    |

### "4,180 pages" cannot be built, and it is not close

`BookSearchResult` has no page-count field at all (`lib/services/book_search_service.dart:10-49`), so
"already returned by every search provider" is not true of pages. Worse, checking each provider:

- **Kakao** — the primary provider for Korean titles, which is what this library is. Its book document
  has exactly eleven fields, dumped live for a real ISBN: `authors, contents, datetime, isbn, price,
sale_price, publisher, status, thumbnail, title, translators`. **There is no page count to capture.**
- **Google Books** — has `pageCount`, and `_mapVolume` never reads it. Sampling 40 random finished books
  from `migration_data/book.jsonl` through the keyed API: **14 had a `pageCount` (35%)**, 2 were in the
  catalogue with none, and **24 were not in the catalogue at all**. Mean page count when present was
  179, which is low enough for a Korean trade paperback to suggest the metadata is poor even when it
  exists. Note also that a Google volume can return `pageCount: 0` rather than omitting the key, so a
  naive read banks a zero as knowledge.
- **Open Library** — its requested `fields` list does not include `number_of_pages`, and its coverage of
  Korean trade books is thinner than Google's.

So the hero's page figure would be built from about a third of the shelf and would understate a real
reader by a factor of three, silently. **Cut it.** A stat that is confidently wrong is worse than a
missing one, and this is the one figure on the card a reader could check by hand.

### The Rating tile has no data and no way to get any

`rating real` exists on `books` and **all 624 migrated rows are null**. `BookRating`
(`lib/ui/widgets/book_rating.dart`) is defined and **never instantiated anywhere in `lib` or `test`** —
there is no control that sets a rating. So "Rating 4.2 of 12" is a tile over an empty column.
**Cut the tile; do not build a rating-entry UI in this phase.** Rating entry is a book-detail feature
with its own design questions (stars vs. 5-point vs. thumbs, whether it is private) and adding it here
to feed one tile would be the tail wagging the dog. Noted as a follow-up in the design record instead.

### The dates are present but half of them are degenerate, which reshapes Pace

Every finished book has both dates — 293 of 293, no nulls, no inverted pairs. But
**168 of 293 (57%) have `finish_date == start_date`**, and that is structural rather than legacy noise:
`book_info_bottom_sheet.dart:131-133` sets both to today when a book is flipped straight to finished.

```dart
default:
  startDate ??= DateTime.now();
  finishDate ??= DateTime.now();
```

A same-day pair means "logged as read", **not "read in zero days"**. Computed naively, pace would read
`0d per book` for **29 of the 55 users** who have finished anything, including the heaviest reader in
the data, whose 28 books are all same-day.

So: **a span counts only when `finish > start`**, and the Pace tile carries its sample size — which is
what the drawing's "of 12" idiom on the Rating tile was for, reused where it is actually true. When no
book has a real span the tile is omitted rather than shown as zero.

### What the shape of the data means for the card's design

Median finished-book count per user is **2** (distribution: 23 users at 1, max 28). The drawn hero of
**12** is above the 95th percentile. **The card has to look deliberate at n=1 and at n=0**, which is the
opposite of the drawing's assumption, and is a first-class requirement of Task 3 rather than an edge case.

Finish years in the data run 2022–2024, so the drawn `All-Time / 2026 / 2025` capsules would both be
empty. `readFilterYears` already returns `[0]` alone when there are fewer than two years, so reusing it
handles this for free — which is Task 4.

---

## What this phase actually changes, stated carefully

**No new query.** Phase 2 already made `finishedBooksProvider` fetch the whole finished set, and said
why in its own doc comment: the year capsules are the set of years you have finished books in, which a
filtered query cannot tell you. The Card wants exactly the same set, so every shipping stat is a pure
function of a list the app already has in memory. The only data work is the `authors` column.

**No new sheet mechanics.** `LibrarySheet` already takes `header`, `expandedHeader`, `collapsedBody`,
`collapsedBodyExtent`, `expandedExtent` and `initiallyExpanded`. The Card currently passes neither
`collapsedBody` nor `expandedExtent`, so it collapses to handle + header — which is exactly what
`card-down` draws. **That is already correct and must not be broken**; the Card stays on the Phase 1
path and only its `body` changes.

**This claim did not survive, and it went twice.** The Card took `expandedExtent` after the clearance
measurement, and `initiallyExpanded` no longer exists — it is `initialDetent: LibrarySheetDetent`, because
the sheet has three positions and the Card opens at the middle one. Both corrections are in Task 6, with
the measurements that forced them.

|              | Phase 1 / today           | Phase 3                                   |
| ------------ | ------------------------- | ----------------------------------------- |
| collapsed    | handle + header           | unchanged — handle + header (`card-down`) |
| expanded     | header + 96pt empty state | header + share + capsules + stat tiles    |
| header       | `LibrarySheetTitle`       | same, plus a share affordance             |
| data fetched | none                      | none new — `finishedBooksProvider`        |

The drawing puts share **on the sheet**, not on the tab bar, with the note "Sheet carries its own share,
since the card is the shareable artifact". Keep that.

---

## Task 1: `books.authors`, and a backfill that only Kakao can do

- [x] New migration adding `authors text[]` to `books`, defaulting to `'{}'` rather than nullable, so
      "not backfilled yet" and "genuinely has no author" do not have to be told apart by callers.
      **Do not add `page_count`** — see the audit.
- [x] `BookSearchResult` already carries `authors`; persist it on the two write paths that currently
      discard it (`add_book_bottom_sheet.dart`, and wherever `book_info_bottom_sheet` saves). Add
      `authors` to the `Book` model, `fromJson`, and `copyWith`.
- [x] `book_details_tab_view.dart:32` re-fetches authors from the catalogue **at display time** through
      `getByIsbn`. Once the column is populated, prefer the stored value and fall back to the fetch, so
      the detail page stops making a network call for something it now owns.
- [x] A one-shot backfill script under `scripts/`, **not** a SQL migration — it has to call an HTTP API
      per ISBN, which a migration cannot. Rules it has to respect: - **Kakao is the provider**, not Google. Sampled 40 random finished books: Kakao returned a
      document for **40/40** with authors on **40/40**; Google Books found only 16/40. For a Korean
      library the difference is the whole result. - Kakao is keyed (`KAKAO_REST_API_KEY` in `env.json`) and rate-limited; throttle, and make the
      script resumable so a 429 halfway through is not a restart. - **15 of 624 rows have no ISBN** and cannot be looked up. They keep `'{}'` and must not be
      retried forever. - Books are per-user rows, so the same ISBN appears many times — **look up per distinct ISBN**,
      not per row.
- [x] Backfill the migrated corpus and record the achieved coverage in this plan.
      **Done, against the live database.** `supabase db push` applied the migration (the CLI was already
      linked and logged in, and `supabase migration list` showed the remote history in sync, so the push
      carried exactly this one migration and nothing else). The backfill then wrote **437 of 472 rows**.

      The live numbers differ from the corpus numbers above, and the difference is worth recording:
                      `migration_data/book.jsonl` has 624 books and 559 distinct ISBNs, and the live table has **472
                      books and 430 distinct ISBNs** — 152 of the exported rows never landed or have since been deleted.
                      Coverage on what actually exists: 407 of 430 ISBNs resolved, leaving 35 rows unfilled (20 ISBNs
                      Kakao has no document for, 3 it lists with no author, and 12 rows with no ISBN at all). Of the 230
                      *finished* books — the only ones the card counts — **217 (94.3%)** carry an author.

                      Re-running is now a no-op on everything that succeeded: a second `--dry-run` sees only the 35
                      leftovers, because the query selects rows that still hold the default.

                      End-to-end effect, measured rather than assumed: **9 of the 45 readers** with a finished book now
                      clear `kTopAuthorFloor` and see the tile. The other 36 do not, which is the design working — it is
                      the same ~20% the corpus predicted.

**Done when** a fresh book saved from search has its authors stored, the detail page reads them without
a network call, and the migrated rows are populated with a number written down here.

**Built, with two corrections.** Coverage: **537 of the 559 distinct ISBNs (96.1%)** resolved through
Kakao — 4 were in Kakao with no author listed and 18 were not in Kakao at all. At the row level that is
279 of 293 finished books (95.2%) with a usable first author.

Two things the plan had wrong:

- **The detail page still makes the network call.** The plan said reading stored authors would remove
  it; it does not, because the Book info tab below shows publisher, publication date and description,
  none of which the row owns. What the column actually buys is that the _header_ no longer waits — the
  name paints on the first frame instead of arriving a request later and resizing the hero. The comment
  in `book_details_tab_view.dart` says so rather than claiming the saving.
- **Kakao can return several documents for one ISBN**, and the first of them is not always the one with
  authors — querying `0000000000000` returns three, and only the second names anyone. The lookup takes
  the first document _with_ authors instead of `documents[0]`, or it would cache an empty answer for a
  book Kakao can name.

The backfill script writes by **row id, not by ISBN**, so a re-run cannot overwrite a copy of the same
title whose authors are already set — which is what the script's own docstring promises.

---

## Task 2: the stats, as a pure function

- [x] A `LibraryCardStats` value type and a `libraryCardStats(List<Book>, {int year})` function in
      `lib/models/` or `lib/ui/widgets/library_card/`. **A function over a list, not a provider that
      queries** — it is unit-testable with a fixture list and has no Supabase in it.
- [x] Fields, and only these: `booksRead`, `daysReading`, `pace`, `paceSampleSize`, `topAuthor`,
      `topAuthorCount`.
- [x] `daysReading` is the **sum of real spans** (`finish - start` where `finish > start`), not the
      elapsed time between your first and last book — that would make a lapsed reader's card grow while
      they read nothing.
- [x] `pace` is `daysReading / paceSampleSize`, where the sample is books with a real span. Both are
      exposed, because the tile shows the sample size and the UI must not recompute it.
- [x] `topAuthor` counts the **first** author of each book. A multi-author book is credited to its first
      listed author — Kakao lists the primary author first, and crediting all of them would let one
      anthology outvote a novelist. Ties break on the author whose most recent book was finished latest,
      so the tile is stable rather than dependent on map order.
- [x] Every field is nullable or zero-safe, and the widget decides what to hide. The function never
      returns a placeholder.

**Done when** unit tests cover: empty list, one book, all-same-day spans, mixed spans, a tie on author
count, books with `authors: []`, and a year filter that excludes everything.

**Built as planned**, and it is the one task that needed no correction — which is what writing it as a
pure function over a list bought. `test/library_card_stats_test.dart` covers all seven cases plus
whitespace-only authors and a co-author case proving only the first author is credited.

One constant carries the phase's whole argument: `kTopAuthorFloor = 2`. With a floor of one, 40 of the
53 readers with author data would see a "most-read author" who wrote one book — a fact about a
tie-break, not about their reading.

---

## Task 3: the card body — hero, tiles, and an honest empty state

- [x] Hero tile: uppercase label, oversized figure, sub-line. Gradient fill, per the "Stat card"
      element note. Figure is `booksRead`; sub-line is days and pace, **not pages**.
- [x] A row of two tiles below it, then the most-read-author tile — the arrangement `card-open` draws,
      minus the cut Rating tile. With Rating gone the row of two is Pace and Most-read author, and the
      author tile's own row disappears; **decide by drawing it, and update `card-open` with a
      "Built differently, and the drawing was wrong" note** if that is where it lands.
- [x] **n=0**: no tiles. Keep something close to today's empty state, since the median user is at 2 and
      a brand-new user is at 0. The empty string already exists (`libraryCardEmpty`).
- [x] **n=1**: the hero shows `1`, and any tile whose sample is empty is omitted rather than shown as a
      zero or a dash. A card with one true tile beats a card with four hollow ones.
- [x] Tiles are individually shareable per the element note, which means each one is its own widget with
      no dependency on its position — Task 5 renders them alone.
- [x] All figures through `intl` and all labels through l10n. Numbers are grouped (`NumberFormat`), and
      the day/pace units are localised — "9d" and "9일" are not the same string with a different suffix.

**Done when** the body renders at n=0, n=1, n=2 and n=28 from fixtures, and no tile displays a figure it
does not have data for.

**Built, and the arrangement question resolved by drawing it.** With Rating cut, the row of two is Pace
and Most-read author, and the author tile's own full-width row is gone — so `card-open`'s three-block
layout becomes two, and `decided.html`'s `stats()` is updated with a note saying so. The author tile
takes `figureIsText: true`, because its figure is a name: at figure size a Korean name longer than three
syllables overflows a half-width tile.

One crash, caught by the geometry test rather than the device: the tile row wants
`CrossAxisAlignment.stretch` so two tiles are the same height whatever their contents, and a `Row` inside
a min-height `Column` is offered _unbounded_ height — which makes `stretch` "BoxConstraints forces an
infinite height". `IntrinsicHeight` is what makes it legal.

Two colour corrections, both found by looking at the first device screenshot and now pinned by
`test/library_card_contrast_test.dart`:

- Non-hero tiles graded `surfaceVariant → surface`, ending at **pure white** — lighter than the
  `#EFF5EF` sheet behind them, so each tile's bottom-right corner dissolved into the sheet and stopped
  reading as a tile. They now grade _darker_.
- Their labels used `secondaryText` (`#ADB5BD`) on a `#E9ECEF` ground: about **2.0:1**, and visibly
  washed out. A 10.5pt uppercase label is the least forgiving text on the card.

The contrast test also caught something no screenshot would have: the hero's muted sub-line at 78% white
is **4.08:1** on `brandFill`, under AA. It is 88% now. A gradient has to be checked at both stops, since
a ratio that passes at the light end can fail at the dark one.

---

## Task 4: the year capsules — reuse, do not rebuild

- [x] Use `ReadFilter` and `readFilterYears` from Phase 2 unmodified. The drawn capsules
      (`All-Time / 2026 / 2025`) are the same control with the same semantics — `0` is all time.
- [x] The capsule row lives in `expandedHeader`, as the read view's does, so it is absent when collapsed.
      `card-down` is title-only and stays that way.
- [x] Selecting a year re-derives the stats through `libraryCardStats(books, year: y)`. The **hero label
      changes with it** — "All-time library card" is drawn on the hero, and it is a lie when 2024 is
      selected.
- [x] If `readFilterYears` returns `[0]` alone, render no capsule row at all rather than a single dead
      capsule. This is the common case in the current data.

**Done when** switching capsules changes every figure and the hero label, and a single-year library shows
no capsules.

**Built as planned — `ReadFilter` and `readFilterYears` are used unmodified**, which is the outcome the
task wanted. Verified on device: tapping 2025 moved the native `CNSegmentedControl`, relabelled the hero
to "2025 LIBRARY CARD", recomputed pace to `15d / of 2 dated`, and **dropped the author tile entirely**
— one Han Kang book in 2025 does not clear the floor of two — at which point the surviving Pace tile
expanded to the full width. Every rule in Tasks 2 and 3 visible in one screenshot.

**Since then the capsule row stopped being a `CNSegmentedControl`**: Flutter lays the row out and draws
every label, and iOS 26 supplies only the material — a glass `CNButton` stacked behind the selected
label — because the segmented control filled the sheet's width with a grey track, which is not the row
`decided.html` draws. Still `ReadFilter`, still unmodified from here — the change is inside it. See
Phase 2's Task 3.

Worth recording how rare the capsules are: only **12 of the 55** readers in the corpus have finished
books in more than one year, so 43 of them see no capsule row at all.

---

## Task 5: share — a new dependency and one hard constraint

- [x] Add `share_plus`. `path_provider` is already present transitively — note that
      `dependency_overrides` pins `path_provider_foundation: 2.4.1`, so check `share_plus` resolves
      against that pin before committing to the version.
- [x] **The card must be rendered off-screen for capture, not screenshotted from the sheet.**
      `RepaintBoundary.toImage()` **cannot capture platform views**, and the capsule row is native on
      iOS 26. Capturing the live sheet would produce a card with a hole where the capsules are. So build
      the shareable artifact as a **pure-Flutter widget tree with no native controls**, rendered into its
      own `RepaintBoundary` off-screen, at a fixed export size independent of the phone's width — which the
      sheet's handle, share button and scroll offset are a second reason for. (The capsules were one
      `CNSegmentedControl` when this was written and are a Flutter row with a glass `CNButton` behind
      the selected label now; same rule either way.)
- [x] Export at `devicePixelRatio` ≥ 3 so the image is not soft when it lands in a chat app.
- [x] The share sheet is invoked from the header affordance for the whole card, and from a long-press or
      per-tile control for a single tile. **Whole card first**; per-tile share is the drawing's ambition
      and can follow within the phase if the first lands cleanly.
- [x] The exported card carries the app's name and the reader's handle, because the artifact leaves the
      app and has to still say what it is.

**Done when** a real share sheet opens on the simulator with a correctly rendered PNG containing no
holes, verified by looking at the exported file rather than at the share sheet.

**Built, and the off-tree render the plan called for does not work.** The tidy design — a `RenderView`
with a `BuildOwner` and `PipelineOwner` the function owns, needing no tree and no frame timing — was
written, and it fails three ways in sequence: `View` sets its own `rootNode` (so presetting it trips an
assert), the owner it adopts inherits the binding's semantics state (so it needs an `onSemanticsUpdate`
sink), and finally `RendererBinding.addRenderView` asserts the view id is not already registered — and
the app's own window is registered under it. A second `ui.FlutterView` would be needed and there is only
one. **The subtree is hosted in the app's `Overlay` instead**, positioned off the left edge.

Why off-screen positioning specifically, and not the obvious alternatives: `Offstage`, `Visibility` and
`Opacity(0)` all skip painting, and a boundary that never painted has no layer to rasterise. An
out-of-bounds `Positioned` still lays out and paints.

`share_plus 10.1.4` resolved against the `path_provider_foundation: 2.4.1` override without complaint;
`path_provider` is now declared rather than used transitively. The export is **1080×1350** — 360×450
logical at 3×, portrait 4:5, which KakaoTalk, iMessage and Instagram all show uncropped.

**Per-tile share is not built.** The whole card landed and is verified; the drawing's "individually
shareable" ambition is left, because the drawing does not say what triggers it and the tiles are already
position-independent widgets, so it is a gesture decision rather than a rendering one.

**The bug this task existed to catch, caught exactly where the plan said to look.** The first exported
PNG had a yellow double underline under every glyph. The capture hosts the card in the `Overlay`, which
has no ancestor `Material`, and `MaterialApp` installs a fallback `DefaultTextStyle` for that case whose
`debugLabel` reads "fallback style; consider putting your text in a Material". The card's `Text` widgets
set size, weight and colour — all overridden — and not `decoration`. Fixed by giving
`ShareableLibraryCard` its own `Material`, and pinned by `test/shareable_library_card_test.dart`, which
pumps the card **without a `Scaffold`** on purpose and asserts the resolved style of every `Text`.

The rasteriser is split from the hosting for a testing reason worth knowing: PNG encoding needs
`WidgetTester.runAsync`, the hosting waits on two real frames that only arrive when the test pumps, and a
test cannot pump from inside `runAsync`. So `rasterizeBoundary` is tested (four cases, all asserting
_pixels_, including that a gradient's opposite corners differ) and the hosting is device-verified.

---

## Task 6: wire it into the sheet

- [x] `LibraryCardSheet` takes the finished books, the selected year and an `onFilterChanged`, and passes
      `expandedHeader` and the new `body`. It keeps `collapsedBody` unset.
      **Changed from the plan:** it does _not_ watch `finishedBooksProvider` or hold the year itself. It
      is a `StatelessWidget` fed by `home_page.dart`, exactly like `FinishedBooksSheet` — which keeps it
      pumpable in a widget test with no provider container, and is why
      `test/library_card_sheet_test.dart` needs no overrides.
- [ ] ~~Loading and error states: reserve the body's height across loading → data so expanding does not
      animate to one height and then resize.~~ **Not done, and deliberately left.** `home_page.dart`
      passes `finishedBooksAsync.valueOrNull ?? []`, so while the query is in flight the Card shows the
      same empty state a reader with no finished books sees, then grows. The sheet is capped now, so the
      _sheet_ does not resize — only its contents appear. Reserving a height would mean guessing which
      tiles are coming, and guessing wrong is a worse jump than the one it prevents. Flagged rather than
      claimed.
- [x] Stays inert in edit mode like every other sheet — `isEditMode` is already plumbed.
- [x] The Card tab must still leave the library behind it untouched, which is the invariant Phase 1
      built this tab to prove.

**Done when** `library_clearance_test.dart` still passes for the Card tab and the tab switch is verified
on device.

**Built, and the clearance measurement overturned Task 6's premise.** The plan and the sheet's own doc
both said the Card stays uncapped. At 2× text on a 375×667 phone that **overflowed the library view's
column by 95pt**: every figure and label on the card is text and all of it scales. `card-open` is drawn at
**h:74** — a tall sheet with the tiles at the top — so the drawing had the cap before the code did. The
Card now uses the same `sheetExpandedExtent` rule as the read view and scrolls its body.

That rule moved out of `FinishedBooksSheet` and into `library_sheet.dart` when it acquired a second
caller, with a forwarding alias left behind because the clearance and sheet tests name it. A cap with two
copies is a cap that ends up with two values, and the symptom would be the library jumping on a tab
switch.

The Card's own year state is `cardFilterYearProvider`, not the read view's. The two controls look
identical and mean the same thing, but narrowing the Library tab to 2024 is not a request for your card to
be about 2024.

**Later, and the third correction to this task: where the Card _opens_.** Task 6 shipped it opening
expanded, the cap above turned that into the whole band, and the fix for that was to open it collapsed —
which `library_clearance_test.dart` then asserted as "the Card opens to `card-down`". Both ends are
wrong, for opposite reasons:

| opens at  | what a reader sees on tapping Card                                                      |
| --------- | --------------------------------------------------------------------------------------- |
| expanded  | the whole band of mostly empty white; no cover left to long-press, so no edit can start |
| collapsed | a title and nothing else — the Card tab showing none of the card                        |
| medium    | the card, with a strip of library behind it                                             |

So it now opens at the **medium detent** (`sheetMidExtent`, 65% of the collapsible band — about 60% of the
screen). What made collapsed defensible for the read view does not transfer: that sheet has a collapsed
body worth resting on — today's spine pile — and `card-down` is title-only precisely because the Card has
none. A resting position is only a resting position if there is something to look at there.

This needed one new piece of sheet mechanics, and it is the piece the "No new sheet mechanics" claim above
lost last: `LibrarySheet.initiallyExpanded` is gone, replaced by `initialDetent: LibrarySheetDetent`,
because a boolean cannot name three positions. `LibrarySheetDetent` is the sheet's own detent enum, made
public for that reason. A `medium` start applies `midExtent` in `initState` rather than in a post-frame
callback — it is a number the caller gave rather than a measurement, and correcting it after layout would
have put one frame of full-band sheet on screen, which is the flash the whole change exists to avoid. The
handle tap is unchanged and still toggles the two ends, so from the Card's resting position it puts the
sheet away and a drag is what takes it to the band.

---

## Task 7: tests and verification

- [x] Unit tests for `libraryCardStats` — the six cases from Task 2. This is where the coverage lives,
      because it is where the logic is.
- [x] Widget tests for the card body at each n, asserting **geometry and absence**: that a tile with no
      sample is not in the tree, and that the hero's figure is the one the function returned. Phase 2's
      lesson was that four passing colour tests missed a 0pt-wide widget because they all tested the
      function — so **assert the rendered tile's size and position, not just its text**.
- [x] A test that the gradient hero actually has non-zero extent. `GeneratedCover`'s colour block was 0pt
      wide from the day it was written, for exactly the reason a gradient tile is at risk: a childless
      decorated box in a `Column` with default cross-axis alignment sizes to `constraints.smallest`.
- [x] Assert the capsules only through the `useNativeGlass` gate — `flutter test` reports Android, so the
      fallback is what runs. `test/read_filter_test.dart` has the pattern.
- [x] Re-measure clearance at 2× text. The card body is new text that scales, and the test font makes
      every glyph one em wide, so treat overflow assertions as a strict upper bound.
- [x] **Run it on a simulator.** Non-negotiable: the share sheet, the off-screen capture, and a native
      segmented control inside a sheet that moves are all things no widget test reaches. Use
      `lib/main_shell_preview.dart` and the commands in Phase 1's Task 7. Card tab is at
      approximately `--x 0.61 --y 0.918`.
- [x] Update `decided.html` only where the build proves a drawing wrong, and say so in the note. At
      minimum the cut pages figure and the cut Rating tile are drawing changes, and both are the build
      proving the drawing wrong.
- [x] Tick this plan, then update the status line in the design record — and correct its Phase 3
      description, which claims `page_count` is cheap.

---

## Risks, in hindsight

- **The backfill was budgeted as the risky part** because it is the only thing here that touches
  production data — and it ran cleanly. What made it safe was checkable rather than lucky:
  `supabase migration list` proved the remote history was in sync before pushing (had it not been,
  `db push` would have tried to re-apply the initial schema), and `--dry-run` printed the writes first.
  The script writes by row id, so the re-run afterwards touched nothing it had already done.
- **A dependency that was not there.** The script was written against the `supabase` Python package,
  which `import_to_supabase.py` uses — and it is not installed, on a Homebrew Python where installing it
  means a venv. Worse, `import supabase` _succeeded_ when tested from the repo root, because the repo has
  a `supabase/` **directory** that Python resolved as a namespace package. A false positive that would
  have failed only at the moment the script was needed. Rewritten to talk to PostgREST over `urllib`,
  which it already did for Kakao, and now needs nothing but a bare `python3`.
- **Off-screen render for share was budgeted as the risk that could eat the day, and it did.** Not for
  the reason given, though. The plan assumed the difficulty was getting a blank or stale image; the
  actual difficulty was that **the off-tree pipeline cannot be built at all** in an app that already owns
  its only `ui.FlutterView`, which took three successive framework asserts to discover. The overlay
  fallback then worked first time. The genuine surprise was the yellow underline, which nothing in this
  plan anticipated and only opening the file revealed.
- **Cutting two of the five drawn stats leaves the card thin**, and it does — at the median of two books
  the card is a hero and one tile. Everything considered as a replacement was checked against the data and
  degenerates the same way: "busiest month" is one book for 29 of the 55 readers. **The data is thin
  because the readers are light, and no cleverer stat fixes that.** So nothing was invented; the card
  shows what is true and the layout carries the rest.
- **`ReadFilter` got a second caller** and needed **no changes whatsoever**, which is the best possible
  outcome for that risk and a credit to how Phase 2 wrote it.
- **Phase 2's unmeasured image-load risk does not apply here** — the card renders no covers. Still open
  for the read view.
- **New, and left open: the exported card is bottom-heavy at the median.** A hero and one tile in a fixed
  360×450 frame leaves roughly the lower third empty. It reads as deliberate room rather than as a bug,
  and the 4:5 aspect is worth keeping because every messaging app shows it uncropped — but it is the one
  thing about the artifact that a designer would want another pass at.

## Open questions, settled

- **Does the author tile survive for a light reader?** **No, and by a measured margin.** `kTopAuthorFloor`
  is 2, which hides the tile for 40 of the 53 readers with author data. Verified live: the tile vanished
  when the year filter narrowed Han Kang to one book, and the surviving Pace tile took the full width.
- **Whether the hero's sub-line survives the cut.** **It survives, shortened.** Without pages it reads
  "books · 81 days reading", and the days clause drops entirely when nothing has a real span. It does not
  duplicate the Pace tile: one is a total and the other an average, and the tile states its sample size
  where the hero cannot.
- **Where per-tile share is triggered from.** **Still open, and now explicitly deferred** — whole-card
  share shipped and is verified. The tiles are already position-independent widgets, so this is a gesture
  decision rather than a rendering one whenever someone wants it.
- **Whether the card is worth showing on a visit to a friend's library.** Still a privacy decision, not a
  technical one. Moved to the design record's "Still open" so it does not get lost with this plan.
- **New question, answered by the drawing:** should the Card sheet be capped? **Yes** — `card-open`'s h:74
  said so all along, and the plan's argument for leaving it uncapped was wrong. See Task 6.
- **Where does the Card sheet open?** **The medium detent**, ~60% of the screen — not either end. Both ends
  shipped first and both showed the same fault from opposite sides: expanded is the library gone behind a
  mostly empty card, collapsed is the Card tab showing none of the card. `card-down` stays what the handle
  tap gets you, not what launching the tab does. See Task 6.
