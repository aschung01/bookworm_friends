# Shelf density — Implementation Plan

> **For agentic workers:** Implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax
> for tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this
> project has established Given-When-Then and layer-isolation conventions.

**Design:** `docs/superpowers/specs/2026-09-08-shelf-density-design.md`
**Prior drawing:** `docs/mockups/shelf-overflow/index.html` — the same arithmetic, three _vertical_
answers. Task 12 annotates it. Do not treat its `capped-wrap` recommendation as live.
**Prior art to read first:**

- `docs/superpowers/plans/2026-08-22-read-pile-spines-plan.md` — built `readSpineMetrics`,
  `spineToneFor`, `BookVertical`'s fill/ink pair and the spine→cover turn. Tasks 4, 5 and 6 here
  generalise four things that plan created; read its reasoning before moving any of them.
- `docs/superpowers/plans/2026-08-11-book-3d-chassis-plan.md` — built `BookMetrics`, `BookJitter`
  and `BookChassis`. Task 4 adds a caller, not a capability.
- `docs/superpowers/plans/2026-08-14-phase-1-shell-plan.md` — why `LibraryPane` takes everything as
  parameters and reads no shell state. Task 3 must not break that.

**Goal:** Three ways to draw a shelf — `covers` (today), `leaning` (shingled), `spines` — cycled
from one button in the library bar and persisted per reader; plus reading books first on every
shelf in every state.

**What is genuinely new:** one persisted enum, one shingled `Stack` layout, and a drop-index clamp.
Everything else is either a pure display transform of data the app already has, or an extraction
that gives an existing read-pile mechanism a second caller.

---

## What this changes, stated carefully

**⚠️ `shelf_row.dart` is under active edit by someone else.** Between this plan being drafted and
being committed the file grew from 1021 to **1282 lines** and `_ShelfRowState` gained
`TickerProviderStateMixin` (`shelf_row.dart:132`) plus two controllers, `_liftTurn`
(`shelf_row.dart:206`) and `_liftScale` (`shelf_row.dart:247`) — an in-flight lift animation on the
drag path. Line citations below were re-derived against that state and **will drift again**.

Before starting Task 3 or Task 9, both of which restructure that file: confirm the lift animation
has landed, and re-run `cite_check.py`. Task 3 moves the resting row out and Task 9 edits
`_dropIndexFor`; neither touches the lift, but both will conflict textually with an unfinished
branch. **Do not start those two tasks against a dirty `shelf_row.dart`.** Tasks 1, 2 and 4 are
unaffected and can proceed regardless.

**`LibraryPane` must keep reading no shell state.** `library_view.dart:13-21` is explicit that the
pane "takes everything it draws as parameters and reads no shell state itself", because the shell
keeps it persistent across tab switches. So `ShelfDensity` is **passed down from `HomePage`**
exactly as `mode` is (`home_page.dart:480` watches `libraryModeProvider` and threads it through).
Do not `ref.watch` the density inside `LibraryPane`, `ShelfRow` or `ShelfBooksRow`.

**"Edit mode always draws face-out" is enforced structurally, not by a conditional.**
`_ShelfRowState.build` (`shelf_row.dart:915`) already branches on `isEditMode` and sends the edit
path to `_buildEditableBookList`. Thread `ShelfDensity` into **only the non-edit branch**. Then
there is no code path by which a spine or a shingle can reach the drag machine, the delete badge at
`top: -22, left: -22` (`shelf_row.dart:1203`) keeps its room, and `_dropIndexFor`
(`shelf_row.dart:442`) keeps measuring full-width covers. If you find yourself passing density into
the edit path, stop — the design says you should not be able to.

**Task 1 changes today's view on its own.** Reading-first applies to `covers` too, so the moment
Task 1 lands, existing shelves reorder. That is intended (design: "Reading first"), but it means
Task 1 is the one task in this plan with a user-visible effect before the feature exists. Land it
deliberately, not as a drive-by.

**The `leaning` cost is a gate, not a footnote.** Task 7 measures it before Task 8 builds it. Do not
reorder those two, and do not pre-emptively write a windowing scheme.

---

## Task 0: Housekeeping

- [ ] Add both new docs to `DOCS` in `docs/superpowers/plans/cite_check.py:21-24`, which is
      currently hardcoded to the `2026-08-28-friends-invites-*` pair.
- [ ] Run `python3 docs/superpowers/plans/cite_check.py --show` and read the output. It proves a
      cited line **exists**, not that it says what the prose claims — reading is the mitigation, and
      the plan cites files that Tasks 3–9 then edit, so re-run it at the end.
- [ ] Record the baseline before touching anything: `flutter test` pass/fail counts and
      `flutter analyze lib test` issue count. Every task below reports against this baseline, and
      the read-pile plan's Task 1 note shows why (it inherited five pre-existing
      `library_read_books_test.dart` failures and had to say so).

---

## Task 1: Reading first

Pure functions and one call site. No widgets.

- [ ] `withReadingFirst(List<Shelf>)` in `lib/providers/library_provider.dart`, immediately after
      `withoutFinishedBooks` (`library_provider.dart:38`). **Stable partition**: books at
      `bookStatusReading` (`library_provider.dart:26`) in authored order, then everything else in
      authored order. Not a `sort` — Dart's `sort` is not stable, and two books swapping for no
      reason is the kind of thing nobody reports and everybody notices.
- [ ] `readingHeadCount(Shelf)` beside it: the length of the **leading run** of reading books.
      Defined on an already-promoted shelf, so it is `takeWhile`, not `where`. Document that, since
      a caller passing an unpromoted shelf gets a wrong answer rather than an error.
- [ ] Doc comment on `withReadingFirst` stating the two things a reader will want to know: that
      `Book.position` is never written by it, and that once a drag persists a promoted row the
      promotion becomes the authored order (design: "A consequence, named rather than discovered").
      This is a real departure from what `withoutFinishedBooks` boasts at
      `library_provider.dart:36-37`; say so rather than leaving the two docs to contradict each
      other silently.
- [ ] Compose it in `library_view.dart:110`:
      `withReadingFirst(withoutFinishedBooks(shelves))`.
- [ ] Tests in `test/shelf_reading_first_test.dart`: stability (two reading books keep their
      relative order; two non-reading books likewise), a shelf with no reading books is returned
      unchanged, a shelf where every book is reading is returned unchanged, composition with
      `withoutFinishedBooks` in both orders yields the same list, and `readingHeadCount` on
      promoted / empty / all-reading shelves.

**Do not** touch `shelvedBookCount` (`library_provider.dart:60`). Membership is unchanged by
promotion, so the shelf-tab hero keeps the same width at both ends of its flight — and that
invariant is load-bearing per `shelf_label.dart`'s own doc.

---

## Task 2: `ShelfDensity` and its persisted provider

Inert — nothing reads it until Task 3.

- [ ] `lib/providers/shelf_density_provider.dart`. Copy the shape of
      `lib/providers/theme_provider.dart` exactly: `const String _prefKey` (`theme_provider.dart:6`),
      a `Notifier` whose `build()` reads `sharedPreferencesProvider`
      (`theme_provider.dart:10-15`), a `set()` that writes then assigns (`theme_provider.dart:19`),
      and a `NotifierProvider` (`theme_provider.dart:46`).
- [ ] `enum ShelfDensity { covers, leaning, spines }`. Doc why it is not a widening of `LibraryMode`
      (`library_shell_provider.dart:20`): the two are orthogonal, so one enum of six would have
      three aliases.
- [ ] `_parse` returns `covers` for null **and** for an unrecognised string. A serialised name that
      no longer exists must not throw on launch.
- [ ] A `next` extension or method for the cycle, so the button in Task 10 does not hand-roll the
      order.
- [ ] Doc why this is persisted and not in `library_shell_provider.dart`: everything there is
      `StateProvider.autoDispose` session state, and this is a preference in the same category as
      theme and search source.
- [ ] Tests in `test/shelf_density_provider_test.dart`: default is `covers` on empty prefs; a
      round-trip through `set` survives a fresh container; a garbage stored value yields `covers`;
      `next` cycles `covers → leaning → spines → covers`. Mock `SharedPreferences` per the
      flutter-tester checklist.

---

## Task 3: Cut the seam — extract the resting row

**Pure refactor. No behaviour change, no new state.** The existing suite staying green _is_ the
test. Do not add `leaning` or `spines` here.

`shelf_row.dart` is 1282 lines and most of it is the drag machine. This moves the resting row out
so Tasks 5 and 8 have somewhere to land.

- [ ] `lib/ui/widgets/shelf/shelf_book_tile.dart` — `ShelfBookTile`, lifted from
      `_buildBookContent` (`shelf_row.dart:331`). Keeps the `Wiggle`, the `BookWidget`, the
      `ReadingBookmark` at `book.status == 1`, and the delete badge. Used by both call sites
      (`shelf_row.dart:692` and `:699`).
- [ ] `lib/ui/widgets/shelf/shelf_edge_fades.dart` — `_EdgeFades` (`shelf_row.dart:1082`) moved and
      renamed `ShelfEdgeFades`, public because `ShelfBooksRow` needs it. Its
      `@visibleForTesting static const double extent` and whichever test reads it move too. Keep the
      entire doc comment — it argues for both ends being conditional, and that argument is not
      re-derivable from the code.
- [ ] `lib/ui/widgets/shelf/shelf_books_row.dart` — `ShelfBooksRow`, taking `Shelf`, `bookHeight`
      and `ShelfDensity`. For now it `switch`es on density and every arm returns today's
      `ListView.separated`. A `switch` with three identical arms is deliberate scaffolding: Tasks 5
      and 8 fill two of them, and an `if (density == covers)` would hide which ones are missing.
- [ ] `_ShelfRowState.build` (`shelf_row.dart:915`) delegates its non-edit branch to
      `ShelfBooksRow`. The edit branch is **untouched**.
- [ ] Thread `ShelfDensity` from `HomePage` → `LibraryPane` → `ShelfRow` → `ShelfBooksRow` as a
      constructor parameter, alongside `mode`. `HomePage` is the only place that `ref.watch`es it.
      See "What this changes" — `library_view.dart:13-21` forbids the shortcut.
- [ ] Confirm `shelf_row.dart` got **smaller**. If it did not, the seam was cut in the wrong place.
- [ ] Run the full suite. `library_clearance_test`, `library_background_regression_test` and
      `book_hero_flight_test` are the ones most likely to notice an accidental change of box; they
      must be green without edits.

**Do not** move `shelf_row.dart` itself, and do not move `_DeleteBookButton`
(`shelf_row.dart:1203`) — it belongs to the edit path, which is staying put. Churn in widely
imported files buys nothing here.

---

## Task 4: Spine plumbing, and one inherited bug

Extractions plus a doc correction. Still no new UI.

- [ ] `spineMetricsFor(Book book, {required double baseHeight})` in
      `lib/ui/widgets/book/book_geometry.dart`, holding what `readSpineMetrics`
      (`read_pile.dart:48`) does today. `readSpineMetrics` becomes a delegation passing
      `ReadPile.spineBase` (`read_pile.dart:53`, `:139`).
      Preserve its doc's guarantee verbatim — "**One** function, used by the flat spine, by the
      chassis that replaces it, and by the row that lays both out" — and extend it to name the third
      caller.
- [ ] Lift `_spineTone` (`read_pile.dart:271`) to a top-level function so a shelf spine and a pile
      spine of the same book cannot come out different colours. It is
      `spineToneFor(book.coverColor ?? generatedCoverColor(book.isbn))`; `spineToneFor` is at
      `book_chassis.dart:142`.
- [ ] **Fix the comment at `book_vertical.dart:145-146`.** It claims the `surface` default "is right
      on a shelf". It is not: `library_view.dart:254` paints the library `surfaceVariant`
      (`#E9ECEF`), not `surface` (`#FFFFFF`). The comment already documents this exact failure mode
      for the read pile's `sheetBackground` and in the same unsafe direction — a fill can clear the
      1.25 threshold against white while having no edge against the surface it is actually on. Say
      that a shelf must pass `surfaceVariant` explicitly.
- [ ] Tests in `test/shelf_spine_metrics_test.dart`: `readSpineMetrics` returns byte-identical
      results to before the extraction for a fixed set of ISBNs (**a regression guard on the
      refactor — write this first and watch it pass before you refactor**), and
      `spineMetricsFor(baseHeight: bookHeight)` yields a height equal to the same book's face-out
      cover height, so a spine and its turned-out cover match.

**Do not** change any number in `book_geometry.dart`. `book_geometry_test.dart` pins goldens and the
shelf-overflow drawing ports them; a changed constant invalidates both.

---

## Task 5: The `spines` state

The cheap state: thickness comes from page count, so no cover decode is needed to lay out, and
spines do not overlap, so the row stays lazy.

- [ ] `lib/ui/widgets/shelf/shelf_spines_row.dart`. Head block of reading books face-out with 15pt
      gaps, one 15pt gap, then spines shoulder to shoulder with **no** gaps. Split the row using
      `readingHeadCount` from Task 1.
- [ ] `ListView.builder`, not a `Stack`. Per-item width from
      `spineMetricsFor(book, baseHeight: bookHeight).metrics.thickness`.
- [ ] Each spine is a `BookVertical` with `fill`/`titleColor` from Task 4's shared tone,
      `separator: true` (two similar covers otherwise read as one wide block), `arch: true`, and
      **`background: context.colors.surfaceVariant`** per Task 4.
- [ ] Verify `bookRowExtent(bookHeight)` (`book_widget.dart:518`) still reserves enough. It should,
      because spine heights come from the same `BookJitter` bounded by
      `maxHeightFactor = 1.06` (`book_geometry.dart:214`) — but assert it rather than assume it.
- [ ] Hero tags on face-out books only. A spine carries none.
- [ ] `test/shelf_density_render_preview.dart`, following `library_sheet_render_preview.dart`. This
      is how you look at the state before Task 10 gives you a button.
- [ ] `test/shelf_spine_background_test.dart`: the pale-spine outline fires for a near-white fill
      against `surfaceVariant`. Extends `book_vertical_outline_test.dart`; check whether
      `color_contrast_test.dart` also wants the case.

---

## Task 6: `TurningBook`, and the two-step tap in `spines`

- [ ] `lib/ui/widgets/book/turning_book.dart` — `TurningBook`, lifted from `_turnedBook`
      (`read_pile.dart:275`). It owns `kReadSpinePose` (`read_pile.dart:32`), the `_slotWidth`
      projection `width·|cos| + thickness·|sin|`, the `hinge` offset, `kTurnMargin`
      (`read_pile.dart:27`), the `BookChassis` (`book_chassis.dart:332`) driven from
      `kReadSpinePose` to 0, and the `arch: false` rule for a spine that has become a face of a
      solid object.
- [ ] `ReadPile` uses it. Its on-screen behaviour must not change — `read_pile` tests and any
      pile render preview are the guard.
- [ ] `ShelfBooksRow` owns a nullable surfaced book id. First tap on a spine surfaces it via
      `TurningBook`; second tap opens details. One per row; tapping another surfaces that one
      instead.
- [ ] The surfaced book gains the hero tag while it is face-out, so the flight to details always
      starts from a fully visible cover — the pile's own rule.
- [ ] Tests: a spine tap does **not** navigate; a second tap does; surfacing a second book
      un-surfaces the first.

**Do not** let this become a rewrite of the pile. If `ReadPile` needs more than a mechanical
substitution, the extraction boundary is wrong — fix the boundary, not the pile.

---

## Task 7: GATE — measure `leaning`, and settle the step

**Stop here and report before starting Task 8.** Two open items, both cheap to resolve and
expensive to get wrong.

- [ ] **Cost.** A `Stack` builds every child, so `leaning` builds one `BookWidget` per non-reading
      book where today's list builds ~4. Build a throwaway shelf of 12, 30 and 60 books and measure
      build time and the image cache. Report numbers.
- [ ] **The step.** `kShelfLeanStep` is specified at 0.16 of `bookHeight` (20.3pt, showing 24% of a
      cover, ~9.7 books with one book in progress). 0.124 (15.7pt, 19%, twelve books fit) is the
      alternative. The design flags this as an open decision because the "colour does the
      recognising, not type" argument was made about 24%. **Ask before choosing.**
- [ ] Only if the measurement is bad: propose a mitigation and get it agreed. Do **not** design
      windowing pre-emptively — the design says so explicitly, and `BookWidget` already caches
      decoded covers.

---

## Task 8: The `leaning` state

- [ ] `kShelfLeanStep` in `lib/ui/widgets/shelf/shelf_leaning_row.dart`, a fraction of `bookHeight`
      (value from Task 7). Doc why it is **not** a fraction of cover width: `shelf_row.dart:141-142`
      records that a cover's width follows its decoded aspect and jitter, so no shelf can know the
      width of a book it does not hold — an absolute step needs no width at all.
- [ ] Head block as in Task 5, then one 15pt gap, then the shingle group: a `Stack` inside a
      horizontal `SingleChildScrollView`, children emitted **highest index first** with
      `Positioned(left: i * step)`, so book 0 paints last and lands on top. `clipBehavior: Clip.none`.
- [ ] Explicit `Stack` width from `kDefaultCoverAspect` plus trailing slack, because the last
      book's true cover width is unknowable before decode. Doc it as the same approximation
      `readSpineMetrics` already makes and documents (`read_pile.dart:41-47`) — a precedent
      followed, not a new liberty.
- [ ] Surfacing: the tapped book's slot animates from `step` to full cover width, pushing later
      books right, and it rises to the top of the z-order. 220ms `easeOutCubic`, in the family of
      `_kPartDuration` (280) and `_hiddenWhileEditing` (260).
- [ ] Hero tags on face-out books only: reading books and the surfaced one.
- [ ] `test/shelf_leaning_layout_test.dart`: step arithmetic against the design's table; **the
      `Stack`'s child order is reversed** — pin this, because it is the paint-order decision and a
      future reader will "tidy" it back; a shelf with no reading books starts the group at the row's
      left padding; a shelf where everything is reading renders identically to `covers`.

---

## Task 9: The drop-index clamp

The only change the drag machine needs.

- [ ] `_dropIndexFor` (`shelf_row.dart:442`) clamps against `readingHeadCount`: a tail book's index
      cannot fall below it, a head book's cannot rise above it. The gap therefore never opens where
      the book cannot land, and **nothing ever animates back**.
- [ ] Both call sites (`shelf_row.dart:730`, `:890`) get the clamped value — check whether the
      clamp belongs inside `_dropIndexFor` or at each site, and prefer inside so a third caller
      cannot forget.
- [ ] A cross-shelf drop lands in the arriving book's own zone on the receiving shelf. `_onDrop`
      (around `shelf_row.dart:730`) already distinguishes same-shelf from cross-shelf via
      `ShelfBookDrag.shelfId`.
- [ ] Tests in `test/shelf_drag_zone_clamp_test.dart`: a tail book dragged over the head opens its
      gap at `readingHeadCount` and never before; a head book dragged into the tail stays in the
      head; a cross-shelf drop of a reading book lands in the receiving shelf's head; a shelf with
      no reading books behaves exactly as today (the clamp is a no-op at 0).
- [ ] Confirm `library_delete_book_test.dart` and the existing reorder tests are green. If a reorder
      test now expects a different list, understand why before editing it — it may be catching the
      persisted-promotion consequence, which is intended.

---

## Task 10: The control

- [ ] Three glyph pairs in `lib/ui/widgets/svg_icons.dart`, following `kStretchHorizontalIconAsset`
      (`svg_icons.dart:18`) and `kStretchHorizontalIconNativeAsset` (`svg_icons.dart:39`) exactly:
      a stroked SVG for Flutter with an explicit stroke (so no renderer has to resolve Lucide's
      upstream `currentColor`), plus a PNG for UIKit.
- [ ] Rasterise with `rsvg-convert -w 72 -h 72`. **Not `qlmanage`** — it bakes Quick Look's opaque
      backdrop in, iOS tints an `imageAsset` by using the image as a _mask_, and the button then
      renders as a solid square. This is documented at `svg_icons.dart:39` and has already been hit
      once. Verify transparency outside the glyph before committing the file.
- [ ] Lucide `gallery-horizontal`, `gallery-horizontal-end`, `library` are the candidates. **Eyeball
      them at 22pt** and say if they do not read; the design does not commit to them.
- [ ] Three semantic labels in `lib/l10n/app_en.arb` and `lib/l10n/app_ko.arb`, naming the state you
      are **in**. This is a mode indicator, not an action.
- [ ] `AdaptiveIconButton.svg` at `diameter: 44` in `_LibraryBar` (`home_page.dart:861`), inboard of
      `GlassAvatarButton` (`home_page.dart:1086`) with an `AdaptiveIconButtonGap`
      (`home_page.dart:1008`) between — the same slot relationship the gear has to Poke. Follow the
      call shape at `home_page.dart:999`.
- [ ] Present in the self **and** visit branches of the bar; absent in the editing branch.
- [ ] Extend `test/library_bar_test.dart`: present in self and visit, absent while editing, cycles
      through three states, and the semantic label changes with the state. Check
      `library_bar_separator_test.dart` still passes — the row's metrics changed.

---

## Task 11: Transitions and the label reserve

- [ ] Cross-fade the row on a density change: an `AnimatedSwitcher` around `ShelfBooksRow` keyed by
      density, 180ms. **Not** a per-book turn — that needs a `BookChassis` per book, which is the
      cost the design rejected for `leaning` itself, and spending it on a transition after refusing
      it for the drawing would be incoherent. The design records this as a withdrawn earlier draft;
      do not reinstate it.
- [ ] Entering edit mode from a compressed state uses the same cross-fade, for free, because the
      edit branch already returns a different subtree.
- [ ] Trailing room in `leaning` and `spines` equal to `ShelfLabel`'s measured width, reserved
      **unconditionally** in those two states. Not conditional on "does the row fit" — that is a
      post-layout fact, and a reserve that appeared after a decode would shift the row. On an
      overflowing row it sits at the far end where nobody sees it. `covers` is untouched.
- [ ] Test: the reserve is present in both compressed states and absent in `covers`.

---

## Task 12: Close the loop on the prior drawing

- [ ] Annotate `docs/mockups/shelf-overflow/index.html` — its lead, or its `capped-wrap` version
      note — to record that a horizontal answer was chosen first, so a reader arriving there is not
      misled into thinking `capped-wrap` is still the plan. Do **not** delete the options: wrapping
      and density are compatible, and a future `covers` could still wrap.
- [ ] Re-run `python3 docs/superpowers/plans/cite_check.py --show` and read it. Tasks 3–9 edited
      most of the files this plan cites, so line numbers will have moved.
- [ ] Report the final suite and `flutter analyze lib test` counts against Task 0's baseline.
- [ ] `docs/mockups/shelf-density/` is recommended but not required, and is a separate piece of work
      if wanted.

---

## Sequencing notes

Tasks 1, 2 and 4 are independent of each other and each ships alone. Task 3 must precede 5 and 8.
Task 7 gates Task 8. Task 9 needs Task 1's `readingHeadCount`. Task 10 can precede 8 only if the
`leaning` arm of the `switch` still falls back to `covers`, which is the one intermediate state
worth avoiding — prefer 8 before 10, and use Task 5's render preview to look at states meanwhile.
