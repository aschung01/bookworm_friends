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

**Goal:** Ways to draw a shelf — `covers` (today) and `spines` — cycled from one button in the
library bar and persisted per reader; plus reading books first on every shelf in every state.

**`leaning` (shingled) was a third state.** It was built by Task 8, fixed twice, and then withdrawn
whole — see "Withdrawn" in the progress log. Tasks 7 and 8 below describe code that no longer
exists; they are kept because the reasoning in them is the argument against reviving it.

## Progress

| task                                              | state                                  | commit    |
| ------------------------------------------------- | -------------------------------------- | --------- |
| 0 Housekeeping                                    | done                                   | `7d041aa` |
| 1 Reading first                                   | **done**                               | `1a057c7` |
| 2 `ShelfDensity` + provider                       | **done**                               | `1a057c7` |
| 3 Thread density in, extract the drawing          | **done**                               | `9384720` |
| 4 Spine plumbing + the inherited bug              | **done**                               | `12451ce` |
| 5 The `spines` state                              | **done**                               | `cf85ca5` |
| 6 `TurningBook`, two-step tap, spine delete badge | **done**                               |           |
| 7 GATE — measure `leaning`, settle the step       | ~~done — step 0.16~~ **withdrawn**     |           |
| 8 The `leaning` state                             | ~~done~~ **withdrawn** (was `2d2f9d4`) |           |
| 9 Drop-index clamp                                | **done**                               | `4832d63` |
| 10 The control                                    | **done**                               | `d10e7a9` |
| 11 Transitions + label reserve                    | **done**                               |           |
| 12 Close the loop                                 | **done**                               |           |

Tasks 6, 11 and 12 are **uncommitted by request** — the working tree already carries a large amount
of unrelated in-flight work, so nothing after `d10e7a9` was committed.

**Task 7's measurement, recorded so it is not rediscovered.** On a sixty-book shelf, `covers`
builds **11** tiles and `leaning` built **60** — a `Stack` has no laziness. Accepted at the time: the
density existed for shelves that fit, and a shelf that fits would have built all its tiles anyway.
The step was settled at **0.16** (20.3pt, 24% of a cover); 0.124 was declined because 24% is the
figure the "colour, not type" argument was made about. `spines` stayed a lazy `ListView`, so with
`leaning` withdrawn this cost is gone from the feature entirely.

**One design revision made during Task 11, with a concrete cause — and then superseded, see below.**
The transition was specified as a cross-fade. An `AnimatedSwitcher` cannot deliver it: it keeps the
outgoing row alive beside the incoming one, and a `ShelfRow` cannot exist twice — `_slotKeys`,
`_handoverKeys` and `_rowKey` are `GlobalKey`s, so the framework reparents on the second sighting and
destroys the drag they carry, and the row's Hero tags would collide the moment a reader tapped a book
mid-fade. This was found by a duplicate-`GlobalKey` assertion, not by reasoning. The row then **faded
out, swapped at the bottom of the dip, and faded back** — 90ms each leg — which needs only one copy of
the row to exist.

**A second revision, made after Task 12, from a bug report.** `leaning`'s tap-to-reveal "functioned
weird": the hit slots were placed at each cover's **leading** edge, which in a left-on-top cascade is
the edge hidden under the neighbour — so every target sat under a book and taps landed on whichever
box happened to span the point. Two things followed from the same misreading, and the plan and design
both carried it: the group's fully-drawn book is the **first**, not the last (nothing paints on top of
book 0), and a reveal has to open air on **both** sides of the surfaced book, because the book to its
left is painted over it. Fixed in `shelf_lean_metrics.dart` (`shelfLeanSlotLeft`,
`shelfLeanShowsWholeCover`, `_clearance`) and `_leanSlot`.

Three things this turned up that are worth keeping:

- **Right-anchoring is not just the fix, it is the better geometry.** Book heights jitter ±6%, so a
  cover's real width is not `base · kDefaultCoverAspect`. A visible strip is the distance between two
  _right_ edges, so anchoring there makes every strip exactly one step whatever the heights are;
  anchoring left would have made the strips ragged. Assertions about placement must be made on right
  edges or on slots, never on a cover's left edge.
- **`OverflowBox` inherits its parent's `minWidth`**, and a `Positioned` with a `width` makes that
  tight — so the child filled the slot and `ShelfBookTile` bottom-_centred_ the cover, silently
  undoing the alignment on exactly the full-cover slots where it mattered. `minWidth: 0` is load-
  bearing.
- **`test/shelf_density_render_preview.dart` exists now**, for the reason the read pile's preview
  exists: this bug passed every measurement the design named. Note that the root layer's coordinate
  space is **physical** pixels, so a capture rect built from `view.size` grabs the top-left corner and
  scales it up — which looks enough like a legitimate close-up to be believed.

**A third revision, also from a bug report: the surfaced book was one _per shelf_.** `_surfacedBookId`
was a field on `_ShelfRowState`, so "at most one book forward" was true of each row independently and
a five-shelf library could stand five covers among its spines. Moved to `surfacedBookProvider` in
`library_shell_provider.dart` — one id for the library, resetting itself when the density changes.
Every single-shelf test passed either way, which is why `shelf_two_step_tap_test.dart` now carries a
two-shelf fixture. Two things worth keeping:

- The provider resets on density change by **watching `shelfDensityProvider` from its own `build`**,
  not from any row. A row clearing it in `didUpdateWidget` would mutate a provider from a widget
  lifecycle callback, once per shelf, in the frame already handling the change.
- The per-row version also cleared the id when the book left the shelf. That case stopped existing:
  ids are unique, so a dangling id names nothing, and a book dragged to another shelf is still the
  book being looked at.

**And a latent bug found next to it.** `_onBookTap` did `if (!_reduceMotion) _surfaceTurn.forward()`,
but the turn _is_ the drawing — `TurningBook` renders a spine at 0 and a cover at 1 — so a reader with
Reduce Motion on tapped a spine, got a spine, and got a details page on the second tap. It now jumps
the controller to 1.

Baseline was 1072 passing / 3 failing and 14 analyzer issues. At Task 12: **1150 passing / 4
failing**. Three of the four are the pre-existing `library_read_books_test.dart` failures, about
`BookVertical` not rendering in the read _pile_ under test. The fourth is `cover_sample_test.dart`,
which belongs to whoever is concurrently editing `lib/ui/widgets/book/cover_sample.dart` — that file
was mid-save with compile errors during this work. Analyzer issues are all in files this work never
touched.

After the reveal fix: **1152 passing / 4 failing**, 17 analyzer issues, none in a file this work
touched. The four are the same three plus `book_info_bottom_sheet_test.dart`, which now fails to
_compile_ because the concurrent cover-colour work added a `coverColor` parameter to `onSavePressed`
without updating it. Every shelf and density test file passes: **79 passing, 0 failing**.

After the one-per-library fix: **1163 passing / 3 failing**, 17 analyzer issues, again none in a file
this work touched. Back to the baseline three; `book_info_bottom_sheet_test.dart` compiles again,
fixed by whoever owns it.

**A fourth revision, and it replaces the transition outright.** Asked for "the best possible transition
between the two view modes", and the fade could not be it: nothing moved, so nothing was explained.
Switching density is now **every compressed book turning on its binding**, hinged at its left edge, in
a wave from the left, with the row narrowing as they turn. 260ms per book —
`kBookTurnDuration`, the same as a book turning anywhere else — plus a 0.35 stagger, so 400ms for the
row. Books in progress do not turn, since they are face-out at both densities.

The design's cost argument against this was wrong, and worth recording as wrong: it equated the turn's
chassis-per-book with `leaning`'s, but `leaning` would have paid it **at rest, forever, on every
shelf**, whereas the turn pays it for 400ms on one row and hands back to `ShelfSpineTile` — so `spines`
still needs no cover decode and stays a lazy `ListView`. New: `shelf_density_turn.dart` (timing and
wave), `turningBookWidthFactor`/`turningBookHingeFraction` in `turning_book.dart` (the projection as
_ratios_, which cancels the decoded cover width nothing above layout knows), `ShelfBookTile.pose`/
`.spine`, and `_ShelfRowState._densityTurn`/`_densityTurning`/`_turningTile`. `_densityFade` and the
lagging `_drawnDensity` are gone. Tested in `test/shelf_density_turn_test.dart`; frames in
`build/shelf_preview/turn_*.png`.

**And the bug that cost the most, because a measurement could not see it.** The row's `build` chooses
which tile each book gets, and it runs on the frame the density changed — the frame the controller was
started on, when it still stands at the endpoint it is leaving. Keyed off `_densityTurn.value`, every
book was chosen as a resting cover, nothing re-chose, and the row animated its margins closed around
books that never turned. Every number was right. A rendered frame showed it immediately. Fixed with
`_densityTurning`, a flag raised before the controller starts — and this is the **second** time this
row has been saved by a PNG rather than an assertion.

After the turn: **1201 passing / 3 failing**, 16 analyzer issues, none in a file this work touched.
The three are the same baseline `library_read_books_test.dart` failures. The passing count is well
above the previous note's because a concurrent piece of work added tests of its own; the nine new ones
here are `test/shelf_density_turn_test.dart`.

**Three notes for whoever continues.**

1. `lib/l10n/app_localizations*.dart` is **gitignored** (`.gitignore:79`) and goes stale. When
   analysis or a test fails with "getter isn't defined for the type 'AppLocalizations'", run
   `flutter gen-l10n`. Do not run it _during_ a suite run — doing so raced the compile and produced
   two spurious load failures.
2. Stage precisely. `git add -A lib test` in this repo sweeps up a very large pre-existing
   uncommitted working tree; commit `9384720` did exactly that and carries 200 files it should not.
3. `enterEditMode` in `test/support/home_page_harness.dart` holds a `BookWidget`, so it cannot reach
   a shelf drawn entirely as spines. Give such a fixture one book in progress. The gesture itself
   works on a spine — the draggable wraps whatever the density drew — it is only the helper that
   looks for a cover.

**What is genuinely new:** one persisted enum, a spine-drawn row and a drop-index clamp.
Everything else is either a pure display transform of data the app already has, or an extraction
that gives an existing read-pile mechanism a second caller.

## Withdrawn: `leaning`

Removed whole on request, after being built and fixed twice. **The reason is not the two bugs — it is
what they were symptoms of.** Both were consequences of the overlap that the design had not reasoned
through: the hit slots sat on each cover's _leading_ edge, which is the edge hidden under the
neighbour, and a reveal had to push its neighbours _both_ ways because the book to the left paints on
top of it. Fixing them worked. But the overlap is the thing a reader has to reason about in order to
use the shelf, and a spine is a thing readers already know how to look at. It cost about two books of
density per row to say so.

What came out:

- `lib/ui/widgets/shelf/shelf_lean_metrics.dart` and `test/shelf_leaning_layout_test.dart`, deleted.
- `_buildLeaningRow`, `_leanSlot`, `_leanSurfacedIndex` in `shelf_row.dart`.
- `_effectiveDensity`, the getter holding the edit-mode fallback — **it existed only for `leaning`.**
  Both remaining densities are edited as themselves, so `_drawnDensity` is now the only answer to
  "what is this row drawing".
- The `slotExtent` override in `_slotExtentOf`, for the same reason: it existed only for the one
  density whose drawing changed on entering edit mode. **Worth knowing before adding a third
  density** — one that redraws in edit mode brings both of these back.
- `shelfDensityLeaning` from both ARBs, and the `square.stack`/`Icons.filter_none` arm of
  `_ShelfDensityButton`.

What stayed, deliberately:

- **The cycle.** `ShelfDensityCycle.next` is still a modulo over `values` rather than a boolean, so
  the button never learns how many states there are. That is where a third one goes.
- **A migration, not a fallback, for a stored `'leaning'`** — it parses to `spines`. The withdrawn
  state was the _other_ compressed one, so a reader who had chosen it asked for a shelf that fits;
  dropping them to `covers` would answer a question they did not ask. Removable once no stored
  preference can plausibly still say it.
- **`_shelfLabelReserve`.** It was added for both compressed states and `spines` still needs it.
- **`test/shelf_density_render_preview.dart`**, retargeted at the two remaining states. It was
  written because `leaning`'s hit-slot bug passed every measurement the design named, which is a
  lesson about this row rather than about that density.

After the withdrawal: **1147 passing / 3 failing** — the same baseline three — and 16 analyzer
issues, none in a file this work touched. The drop of 16 is the deleted `leaning` test file and its
cross-shelf case.

---

## What this changes, stated carefully

**⚠️ The lift animation has landed, and it changed the architecture this plan assumed.**
`shelf_row.dart` grew from 1021 to 1282 lines; `_ShelfRowState` gained `TickerProviderStateMixin`
(`shelf_row.dart`, `_ShelfRowState`), `_liftTurn` and `_liftScale`. Re-run
`cite_check.py` before trusting any line number below.

**There is no separate resting row to extract.** `_buildBookRow` (`shelf_row.dart`) serves both
modes, and every book at rest is a `LongPressDraggable` (`:623`), because a hold at rest both
enters edit mode and lifts the book in one gesture (`_onLift`, `:550`) — and per the doc at
`:557-560`, "a `Draggable` that appears after the finger is down can never adopt that pointer".
An earlier draft of this plan proposed extracting a resting row and claimed edit mode was
structurally firewalled from compressed drawings. Both were wrong. What moves out is the
**drawing**; the row, the draggable and the drag machinery stay put.

**Edit mode is per-density, not always face-out.**

| density       | edit mode draws       | consequence for the drag machine                               |
| ------------- | --------------------- | -------------------------------------------------------------- |
| `covers`      | covers                | unchanged                                                      |
| `spines`      | **spines, draggable** | measured `slotExtent` is already correct — nothing to do       |
| ~~`leaning`~~ | ~~covers~~            | ~~needs `slotExtent` from cover width, not the measured step~~ |

The `slotExtent` hazard is worth stating once, because it is subtle and it bites silently.
`ShelfBookDrag.slotExtent` is measured from the rendered slot (`_slotExtentOf`, `:439`) and is
documented as "the width of the gap the receiving shelf has to open for it". Any density whose
drawing _changes_ on entering edit mode therefore reports a gap for the wrong-sized book. `spines`
avoids this by not changing; `leaning` cannot, so Task 9 overrides it there and only there.

**`LibraryPane` must keep reading no shell state.** `library_view.dart:16-21` is explicit that the
pane "takes everything it draws as parameters and reads no shell state itself", because the shell
keeps it persistent across tab switches. So `ShelfDensity` is **passed down from `HomePage`**
exactly as `mode` is (`home_page.dart` watches `libraryModeProvider` and threads it through).
Do not `ref.watch` the density inside `LibraryPane`, `ShelfRow` or `ShelfBooksRow`.

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
      `withoutFinishedBooks` (`library_provider.dart`). **Stable partition**: books at
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
- [ ] Compose it in `library_view.dart:116`:
      `withReadingFirst(withoutFinishedBooks(shelves))`.
- [ ] Tests in `test/shelf_reading_first_test.dart`: stability (two reading books keep their
      relative order; two non-reading books likewise), a shelf with no reading books is returned
      unchanged, a shelf where every book is reading is returned unchanged, composition with
      `withoutFinishedBooks` in both orders yields the same list, and `readingHeadCount` on
      promoted / empty / all-reading shelves.

**Do not** touch `shelvedBookCount` (`library_provider.dart`). Membership is unchanged by
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

## Task 3: Thread the density in, and extract the drawing

**Mostly a refactor. No new density behaviour.** The existing suite staying green _is_ the test for
the extraction. Do not add `leaning` or `spines` geometry here.

The seam is the **contents of a slot**, not the row. `_buildBook` (`shelf_row.dart`) wraps every
book in a `LongPressDraggable` and hands the drawing to `_buildBookContent` (`:331`) in three
places — `childWhenDragging` (`:709`), `child` (`:716`), and the drag `feedback` (`:679`). Density
changes what goes in those, plus the slot's width. Everything else stays.

- [ ] `lib/ui/widgets/shelf/shelf_book_tile.dart` — `ShelfBookTile`, lifted from
      `_buildBookContent` (`shelf_row.dart`). Keeps the `Wiggle`, the `BookWidget`, the
      `ReadingBookmark` at `book.status == 1`, the delete badge and the `_liftScaled` tail.
      It takes what it needs (`landing`, `turnDrive`, callbacks) as parameters rather than reading
      `_ShelfRowState`, which is what makes it movable at all.
- [ ] Thread `ShelfDensity` from `HomePage` → `LibraryPane` → `ShelfRow` as a constructor
      parameter, alongside `mode`. `HomePage` is the only place that `ref.watch`es it. See "What
      this changes" — `library_view.dart:16-21` forbids the shortcut.
- [ ] A single private `_drawingFor(book, ...)` on `_ShelfRowState` that `switch`es on the
      **effective** density and returns the tile. Effective, not active: `covers` in edit mode when
      the active density is `leaning`, per the table above. Put that resolution in one getter
      (`_effectiveDensity`) so the rule exists once.
- [ ] For now every arm of the `switch` returns `ShelfBookTile`. A `switch` with three identical
      arms is deliberate scaffolding: Tasks 5 and 8 fill two of them, and an
      `if (density == covers)` would hide which ones are missing.
- [ ] Run the full suite. `library_clearance_test`, `library_background_regression_test`,
      `book_hero_flight_test` and `library_delete_book_test` are the ones most likely to notice an
      accidental change of box; they must be green **without edits to them**.

**Do not** move `_EdgeFades` or `_DeleteBookButton` (both in `shelf_row.dart`). An earlier
draft had `_EdgeFades` going public for a `ShelfBooksRow` that no longer exists; nothing outside
this file needs either of them, so moving them is churn.

**Do not** try to make `shelf_row.dart` smaller. It will grow slightly. The earlier draft's
"confirm the file got smaller" check was predicated on extracting a row that turned out not to
exist — the win here is three drawings in three small files instead of three inline, not line count.

---

## Task 4: Spine plumbing, and one inherited bug

Extractions plus a doc correction. Still no new UI.

- [ ] `spineMetricsFor(Book book, {required double baseHeight})` in
      `lib/ui/widgets/book/book_geometry.dart`, holding what `readSpineMetrics`
      (`read_pile.dart`, `readSpineMetrics`) does today. `readSpineMetrics` becomes a delegation passing
      `ReadPile.spineBase`.
      Preserve its doc's guarantee verbatim — "**One** function, used by the flat spine, by the
      chassis that replaces it, and by the row that lays both out" — and extend it to name the third
      caller.
- [ ] Lift `_spineTone` (`read_pile.dart`) to a top-level function so a shelf spine and a pile
      spine of the same book cannot come out different colours. It is
      `spineToneFor(book.coverColor ?? generatedCoverColor(book.isbn))`; `spineToneFor` is at
      `book_chassis.dart:142`.
- [ ] **Fix the comment at `book_vertical.dart:145-146`.** It claims the `surface` default "is right
      on a shelf". It is not: `library_view.dart` paints the library `surfaceVariant`
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
spines do not overlap, so the row stays a lazy `ListView.builder` — which it already is.

- [ ] `lib/ui/widgets/shelf/shelf_spine_tile.dart` — `ShelfSpineTile`, the widget that goes in a
      slot, plus `shelfSpineWidth(book, baseHeight)` for the slot itself. Not a whole row: the row
      is `_buildBookRow` and it stays.
- [ ] Width from `spineMetricsFor(book, baseHeight: bookHeight).metrics.thickness` — **29–47pt**,
      not `BookVertical`'s 26pt default. Two drafts of the design got this wrong; the default is a
      value no real spine uses.
- [ ] `BookVertical` with `fill`/`titleColor` from Task 4's shared tone, `separator: true` (two
      similar covers otherwise read as one wide block), `arch: true`, and
      **`background: context.colors.surfaceVariant`** per Task 4.
- [ ] Spines touch: the per-slot `_kSlotMargin` (7.5 each side) is dropped for a spine, and the
      reading head keeps its 15pt gaps with one 15pt gap before the first spine. Split with
      `readingHeadCount` from Task 1.
- [ ] Verify `bookRowExtent(bookHeight)` (`book_widget.dart:518`) still reserves enough. It should,
      because spine heights come from the same `BookJitter` bounded by
      `BookJitter.maxHeightFactor` (1.06) — but assert it rather than assume it.
- [ ] Hero tags on face-out books only. A spine carries none.
- [ ] **Spines are draggable, and nothing has to be done to make that true.** The slot is already a
      `LongPressDraggable` and the measured `slotExtent` is already the spine's own width, so the gap
      a receiving shelf opens is correct by construction. Add a test that pins it — lifting a spine
      reports a `slotExtent` in the 29–47pt band and not a cover width — because this is the
      invariant the whole per-density edit rule rests on.
- [ ] The lifted spine's `feedback` stays a **spine**, not a turned-out cover: picked up where it
      stood, dropped into a spine-width gap. No `turnDrive` on the lift.
- [ ] `test/shelf_density_render_preview.dart`, following `library_sheet_render_preview.dart`. This
      is how you look at the state before Task 10 gives you a button.
- [ ] `test/shelf_spine_background_test.dart`: the pale-spine outline fires for a near-white fill
      against `surfaceVariant`. Extends `book_vertical_outline_test.dart`; check whether
      `color_contrast_test.dart` also wants the case.

---

## Task 6: `TurningBook`, the two-step tap, and delete in spine edit mode

- [ ] `lib/ui/widgets/book/turning_book.dart` — `TurningBook`, lifted from `_turnedBook`
      (`read_pile.dart`, `_turnedBook`). It owns `kReadSpinePose`, the `_slotWidth`
      projection `width·|cos| + thickness·|sin|`, the `hinge` offset, `kTurnMargin`
      `kTurnMargin`, the `BookChassis` (`book_chassis.dart:332`) driven from
      `kReadSpinePose` to 0, and the `arch: false` rule for a spine that has become a face of a
      solid object.
- [ ] `ReadPile` uses it. Its on-screen behaviour must not change — `read_pile` tests and the pile
      render preview are the guard.
- [ ] The surfaced book id lives in `surfacedBookProvider` (`library_shell_provider.dart`), **one for
      the whole library** rather than a field per row. First tap on a compressed book surfaces it via
      `TurningBook`; second tap opens details. Tapping another surfaces that one instead, on this
      shelf or any other. The provider watches `shelfDensityProvider` so it resets itself on a
      density change — a row clearing it from `didUpdateWidget` would mutate a provider from a widget
      lifecycle callback, once per shelf, in the frame already handling the change.
- [ ] Reduced motion sets the turn controller to **1**, not zero: `TurningBook` draws a spine at 0
      and a cover at 1, so skipping the animation by leaving the controller alone means tapping a
      spine and getting a spine.
- [ ] The surfaced book gains the hero tag while it is face-out, so the flight to details always
      starts from a fully visible cover — the pile's own rule.
- [ ] **Delete in spine edit mode rides the same interaction.** `_DeleteBookButton` sits at
      `top: -22, left: -22` (`shelf_book_tile.dart:96`), outside its cover, so a 44pt disc on a ~37pt
      spine would blanket the touching neighbours. So in `spines`, the badge is drawn **only on the
      surfaced book** — tap a spine to turn it out, and the turned-out cover carries the badge. One
      book face-out at a time **in the whole library** means one badge at a time, so nothing can
      collide, and no new affordance is invented.
- [ ] Tests: a spine tap does **not** navigate; a second tap does; surfacing a second book
      un-surfaces the first; **surfacing a book on another shelf un-surfaces it too** — pin this on a
      two-shelf fixture, because every single-shelf assertion passes whether the id is the row's or
      the library's; in `spines` edit mode exactly one delete badge exists and it belongs to the
      surfaced book; in `covers` edit mode every book still has one; with animations disabled a
      tapped spine is fully turned out.

**Do not** let this become a rewrite of the pile. If `ReadPile` needs more than a mechanical
substitution, the extraction boundary is wrong — fix the boundary, not the pile.

---

## Task 7: GATE — measure `leaning`, and settle the step (WITHDRAWN — see "Withdrawn: `leaning`")

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

## Task 8: The `leaning` state (WITHDRAWN — see "Withdrawn: `leaning`")

- [ ] `kShelfLeanStep` in `lib/ui/widgets/shelf/shelf_leaning_row.dart`, a fraction of `bookHeight`
      (value from Task 7). Doc why it is **not** a fraction of cover width: `shelf_row.dart`'s note on `_slotKeys`
      records that a cover's width follows its decoded aspect and jitter, so no shelf can know the
      width of a book it does not hold — an absolute step needs no width at all.
- [ ] Head block as in Task 5, then one 15pt gap, then the shingle group: a `Stack` inside a
      horizontal `SingleChildScrollView`, children emitted **highest index first**, so book 0 paints
      last and lands on top. `clipBehavior: Clip.none`.
- [ ] **Each `Positioned` is `step` wide, anchored to its cover's _right_ edge, and the cover
      overflows it to the left.** A `RenderBox` hit-tests its whole rect regardless of what is
      painted there, so a slot sized to the full cover would let book 0 — hit-tested first, being
      frontmost — claim taps landing on the visible strip of book 3, which sits well inside book 0's
      rect. Sizing the slot to the exposed strip makes the hit area exactly the part a reader can
      see.
- [ ] **And it must be the _trailing_ strip.** The cascade leans right, so book _i_ is painted
      _under_ book _i−1_: the visible part of book _i_ is its right edge and the hidden part is its
      left one. A slot at `i * step` sits entirely under the neighbour, so it collects no tap anyone
      aimed at it and the tap they did make falls through elsewhere — tapping one book surfaces
      another. Left edge is `i * step + cover − slotWidth`; the cover aligns `bottomRight` inside it,
      and the `OverflowBox` needs `minWidth: 0` or the child fills the slot and `ShelfBookTile`
      bottom-_centres_ the cover, undoing it. **The first book of the group draws in full, not the
      last** — nothing is painted on top of book 0.
- [ ] The `Positioned` children are still `LongPressDraggable`s, so `leaning` keeps the one-gesture
      lift. A `Stack` holding draggables is fine.
- [ ] Explicit `Stack` width from `kDefaultCoverAspect`, because a cover's true width is unknowable
      before decode. Doc it as the same approximation `readSpineMetrics` already makes and documents
      (`spineMetricsFor`'s doc) — a precedent followed, not a new liberty. Right-anchoring makes this
      end of the group exact: books wider than nominal overhang **leftward**, and the only one that
      overhangs past the group is book 0, into the margin the row already keeps in front of the
      cascade.
- [ ] Surfacing: the tapped book's slot animates from `step` to full cover width and it rises to the
      top of the z-order. 220ms `easeOutCubic`, in the family of `_kPartDuration` (280) and
      `_hiddenWhileEditing` (260).
- [ ] **The reveal opens air on _both_ sides.** The book to the left is painted _on top_ of the
      revealed one, so pushing only the books after it leaves the reveal half-covered and reads as
      the tap having done nothing. Revealed book moves right one clearance, everything after it two,
      where a clearance is `cover − step + kTurnMargin`. The book _after_ the revealed one then leads
      its own cascade and shows in full by the same rule — not a special case.
- [ ] Hero tags on face-out books only: reading books and the surfaced one.
- [ ] `test/shelf_leaning_layout_test.dart`: step arithmetic against the design's table, measured on
      **right** edges — book heights jitter ±6%, so left edges are ragged by design and only right
      edges and slots are placed exactly; **the `Stack`'s child order is reversed** — pin this,
      because it is the paint-order decision and a future reader will "tidy" it back; **each slot
      ends where its cover ends** — pin this too, it is the bug that shipped once; **a tap on a later
      book's strip hits that book and not book 0**; a reveal clears `kTurnMargin` on both sides; a
      shelf with no reading books starts the group at the row's left padding; a shelf where
      everything is reading renders identically to `covers`.
- [ ] `test/shelf_density_render_preview.dart`: frames of each density and of the reveal, because
      the hit-slot bug passed every measurement the design named and was obvious in a picture.

---

## Task 9: The drop-index clamp (and, at the time, `leaning`'s slot override)

Two changes to the drag machine, both small and both load-bearing.

- [ ] `_dropIndexFor` (`shelf_row.dart`) clamps against `readingHeadCount`: a tail book's index
      cannot fall below it, a head book's cannot rise above it. The gap therefore never opens where
      the book cannot land, and **nothing ever animates back**.
- [ ] Both call sites get the clamped value — check whether the
      clamp belongs inside `_dropIndexFor` or at each site, and prefer inside so a third caller
      cannot forget.
- [ ] A cross-shelf drop lands in the arriving book's own zone on the receiving shelf. `_onDrop`
      (`_onDrop`) already distinguishes same-shelf from cross-shelf via
      `ShelfBookDrag.shelfId`.
- [ ] **`leaning` overrides `slotExtent`.** `_slotExtentOf` (`:439`) measures the rendered slot,
      which in `leaning` is the 20.3pt step — but edit mode there draws face-out, so the gap a
      receiving shelf opens must be a cover's width. Override it for `leaning` **only**, and doc
      why the other two densities need nothing: `covers` measures a cover and draws a cover;
      `spines` measures a spine and draws a spine. This is the one density whose drawing changes on
      entering edit mode, and the override is the price of that.
- [ ] Tests in `test/shelf_drag_zone_clamp_test.dart`: a tail book dragged over the head opens its
      gap at `readingHeadCount` and never before; a head book dragged into the tail stays in the
      head; a cross-shelf drop of a reading book lands in the receiving shelf's head; a shelf with
      no reading books behaves exactly as today (the clamp is a no-op at 0); lifting from `leaning`
      reports a cover-width `slotExtent` while lifting from `spines` reports a spine-width one.
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
- [ ] `AdaptiveIconButton.svg` at `diameter: 44` in `_LibraryBar` (`home_page.dart`), inboard of
      `GlassAvatarButton` with an `AdaptiveIconButtonGap` between — the same slot relationship the gear has to Poke. Follow the call shape the Manage Shelves button uses.
- [ ] Present in the self **and** visit branches of the bar; absent in the editing branch.
- [ ] Extend `test/library_bar_test.dart`: present in self and visit, absent while editing, cycles
      through three states, and the semantic label changes with the state. Check
      `library_bar_separator_test.dart` still passes — the row's metrics changed.

---

## Task 11: Transitions and the label reserve

- [x] ~~Cross-fade the row on a density change: an `AnimatedSwitcher` around the row keyed by
      effective density, 180ms.~~ **Superseded — the transition is a per-book turn.** The
      `AnimatedSwitcher` was impossible (duplicate `GlobalKey`s), the 90ms fade that replaced it
      explained nothing, and the reason given here for refusing the turn does not survive contact
      with the code: `leaning` would have paid its chassis-per-book at rest forever, the turn pays it
      for 400ms and hands back to `ShelfSpineTile`. See the Progress log and
      `shelf_density_turn.dart`. Entering edit mode still needs no transition, now because `spines`
      does not redraw on entry.
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
