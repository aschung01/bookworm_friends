# Phase 2: the read view — Implementation Plan

> **Status: complete.** All 25 items done. 242 tests green (206 before the phase, 209 after the
> provider rewrite), `flutter analyze lib test` at 11 issues against the 12 it started at — the
> `select_date_bottom_sheet` `unnecessary_import` went with the filter sheet — and the read view
> verified on an iPhone 17 Pro / iOS 26.4 simulator.
>
> Four bugs came out of building it, and the pattern from Phase 1 repeated: the two that mattered
> most were found by measuring and by looking, not by reading.
>
> |                                                                                     | found by                                                   |
> | ----------------------------------------------------------------------------------- | ---------------------------------------------------------- |
> | **the cap left 40pt of library, not 106** — it forgot the tab bar's own reservation | re-measuring the clearance, which is what that file is for |
> | collapsed header overflowed at 2× text once the count reached two digits            | the same measurement, at the accessibility scale           |
> | the glass popover filled half the header — a platform view has no intrinsic width   | **looking at the first screenshot**                        |
> | covers in the grid sat at different heights — shelf jitter inside a uniform grid    | **looking at the second screenshot**                       |
>
> The first is the one worth remembering. `expandedExtentFor` subtracted a shelf row from the band
> the sheet shares with the library, which is the rule the plan asked for — but the sheet's box is
> its content _plus_ the room it reserves for the floating tab bar and the home indicator, so the
> 66pt reservation came out of the library instead of out of the grid. The rule was right and the
> arithmetic was wrong, and only a measurement could tell the difference.
>
> Two drawings did not survive contact, both in `lib-popover`: a real `UIMenu` opened from the
> collapsed header opens **upward**, so iOS reverses the item order to keep the first option nearest
> the button, and the current option carries a checkmark rather than a filled row. Left as the
> platform does it — the flip puts the most recent years closest to the thumb.

> **For agentic workers:** Implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax
> for tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this
> project has established Given-When-Then and layer-isolation conventions.

**Design:** `docs/superpowers/specs/2026-08-14-library-shell-design.md` — "Read books", "Filters", "Phasing"
**Drawings:** `docs/mockups/library-shell/decided.html` — `lib-collapsed`, `lib-expanded`, `lib-popover`, `card-down`
**Phase 1:** `docs/superpowers/plans/2026-08-14-phase-1-shell-plan.md` — complete; read its Task 3 and Task 6
notes before touching `LibrarySheet`, because this phase deliberately breaks two of its invariants.

**Goal:** Make the Library tab's sheet a real two-state view of read books — the spine pile when collapsed,
covers grouped by month when expanded — and replace the year+month filter sheet with a year-only control
that changes shape with the sheet. **No new data**: `books.finish_date` is already fetched and already
ordered, so month grouping is a client-side regrouping of rows the app has.

---

## What this phase actually changes, stated carefully

It is easy to read this as "add an expanded state". It is not. **The two snap positions get relabelled,
and one new state appears:**

|           | Phase 1 (today)              | Phase 2                                             |
| --------- | ---------------------------- | --------------------------------------------------- |
| collapsed | handle + header              | handle + header + **spine pile**                    |
| expanded  | handle + header + spine pile | handle + header + **capsules + month grid**, capped |

So today's _expanded_ becomes tomorrow's _collapsed_, and the month grid is genuinely new. The pile is not
being replaced — it is being demoted to the resting state, which is what "collapsed is today's spine pile
with the count" means in the design record.

`card-down` (h:14) is drawn as a sheet collapsed to nothing but its title, with the note "Any sheet
collapses to its title". Read together with Library's two heights, the general rule is **collapsed =
handle + header + whatever minimal body that sheet has**, which is title-only for Card and Friends because
they have no minimal body. That is the formulation to build, because it leaves Card and Friends exactly as
Phase 1 left them.

### Two Phase 1 invariants are deliberately broken

1. **`LibrarySheet`'s body must not scroll vertically.** Its doc says so, because the body is _clipped_
   rather than squeezed. A month grid does not fit and must scroll.
2. **The sheet's expanded height is bounded because the pile is a fixed-height horizontal scroller.**
   `library_clearance_test.dart` asserts exactly that, and says in its own comment that a grid ends it.
   That test failing is this phase starting, not a regression — but it must be **rewritten to assert the
   new cap**, not deleted.

---

## Task 1: give the sheet a capped expanded state and a scrolling body

- [x] `LibrarySheet` takes `collapsedBody` (optional) and `expandedBody`. Collapsed snap = handle + header +
      `collapsedBody`; expanded snap = `min(natural height, cap)`.
- [x] The cap is expressed as **"one shelf stays visible"**, not as a magic percentage — the drawing's 79%
      is a consequence, not the rule. `bookRowExtent(bookHeight)` in `book_widget.dart` is the same function
      the library uses to size a shelf row, so the cap is `screen − chrome − bookRowExtent(...)`. Deriving it
      that way means the sheet and the library cannot disagree about what "one shelf" is.
- [x] When the expanded content exceeds the cap, the body scrolls inside the sheet. When it does not, the
      sheet is shorter than the cap and nothing scrolls.
- [x] Keep every Phase 1 behaviour: the under-damped spring, overdrag with rubber-band, inert in edit mode,
      the home-indicator inset, `bottomReserve`, and nothing stranded underneath.

**Built:** `expandedHeader`, `collapsedBody`, `collapsedBodyExtent`, `expandedExtent` and
`initiallyExpanded`. Two invariants had to be separated to make it work: `_showExpanded` (the body
currently rendered) is not `_isExpanded` (the target), and it flips at the drag midpoint so a drag shows
the state it is heading for. The collapsed body's height is **passed in rather than measured**, because
the sheet needs the collapsed snap position while the grid is the subtree on screen — honest here because
`ReadPile.extent` is a constant by construction. Bodies only swap when `collapsedBody != null`, which is
what leaves Card and Friends exactly as Phase 1 left them.

`_snapTo` swaps the body, waits a frame, and only then springs. Without that the target is measured
against the header the sheet is _leaving_, and since the read view's header grows a capsule row when it
expands, collapsing landed 39pt too tall. `library_sheet_test.dart` pins it with a deliberately 40pt-taller
expanded header.

**The cap's arithmetic was wrong on the first pass and the clearance test caught it** — see the status
block. `expandedExtent` is a _content_ height, inside the padding that reserves the tab bar and the home
indicator, so both come off `maxExtent` before a shelf is set aside.

**The one real risk in this phase: drag versus scroll.** Phase 1 needed no gesture arbitration — the design
record says so explicitly ("choreography, not gesture arbitration") because the sheet's body never
scrolled vertically. That stops being true here. A vertical drag inside an expanded sheet has to either
scroll the grid or move the sheet, and the handoff at the boundary (grid at scroll offset 0, dragged down →
the sheet should collapse) is where this kind of widget usually goes wrong.

Decide the mechanism deliberately and write down why:

- Simplest: the sheet is draggable only from the handle and header, and the grid owns all body gestures.
  Cheap, predictable, and it costs the "drag anywhere on the sheet" feel Phase 1 has.
- Standard: coordinate with the body's `ScrollController` — the sheet moves while the grid is at offset 0
  and a downward drag continues, and the grid takes over otherwise. This is what
  `DraggableScrollableSheet` does; consider whether adopting it wholesale is cheaper than teaching
  `LibrarySheet` to do it, given `LibrarySheet` also owns a spring, an overdrag and an edit-mode latch that
  `DraggableScrollableSheet` does not have.

**Do not** decide this from the drawings — they are static and cannot show it. Prototype both on a device.

**Decided: the simplest option, and it is right rather than merely cheap.** Drag versus scroll is resolved
by **gesture-arena depth**: the grid's scroll view is deeper than the sheet's drag recogniser, so a vertical
drag inside the body scrolls the grid, and the sheet is dragged from the handle or the header. Confirmed on
device — swiping the grid scrolled it with the header and capsules staying put, and dragging the header down
collapsed the sheet. `library_sheet_test.dart` asserts both halves.

`DraggableScrollableSheet` was rejected: it does not have the under-damped spring, the rubber-band overdrag
or the edit-mode latch, so adopting it means reimplementing three behaviours Phase 1 already pinned in order
to inherit one.

The cost is stated rather than hidden: **when the grid does not overflow, dragging on it does nothing.** You
reach for the handle or the header. That is accepted — the alternative is coordinating with a
`ScrollController` for a case that only arises when the sheet is barely full.

**Done when:** the sheet still passes `test/library_sheet_test.dart` (adjusted for the new collapsed
definition), the grid scrolls at the cap, and `library_clearance_test.dart` asserts the cap instead of the
pile's fixed height.

---

## Task 2: the two bodies

- [x] `ReadPile` — extract today's spine row out of `FinishedBooksSheet` unchanged. It becomes the
      collapsed body, and it is already a fixed-height horizontal `ListView` of `BookVertical`.
- [x] `ReadMonthGrid` — the expanded body: for each month, a header row of month name + count
      (`.mh` in the drawings: name left, count right), then a **4-column grid of covers at aspect ratio
      2:3** (`.mg`, 3px gaps). Newest month first, which is the order the query already returns.
- [x] Group client-side off `Book.finishDate`. Books with a null `finish_date` are finished-but-undated:
      decide where they go — a trailing "no date" group, or excluded from the grid — and say which, because
      silently dropping rows from a count the header shows is the kind of bug nobody reports.
- [x] Reuse `BookWidget` for the covers rather than a new widget, so long-press, the press effect and the
      details push behave as they do on the shelves.

**Undated books get a trailing group**, titled `readNoDate`. Excluding them would make the sheet's header
count, the month counts and the covers disagree, and `read_month_grid_test.dart` asserts the three add up.

The grid is a lazy outer `ListView` of months with a `shrinkWrap` `GridView` per month, so a heavy reader's
history builds only the months that fit — each `BookWidget` resolves its cover through its own `ImageStream`,
and a `Column` in a `SingleChildScrollView` would build every one of them.

**Reusing `BookWidget` needed one opt-out**, found by looking at the device: it hashes a ±6% height jitter
off the ISBN so a shelf reads as physical books of different heights, and inside uniform 2:3 cells that same
variation reads as misalignment. `BookWidget` now takes `jitter`, defaulting to true, and the grid passes
false — `BookJitter.neutral` already existed for books with no ISBN, so this is a flag, not new geometry.

**Done when:** collapsed shows the pile and expanded shows the grid, the header count matches the number of
books actually rendered across all groups, and a book with no finish date is accounted for one way or the
other by a test.

---

## Task 3: the filter changes shape with the sheet, and loses months

- [x] Expanded: an **iOS 26 capsule row** of `All time / <year> / <year> …` below the header.
      `CNSegmentedControl` already does this natively with a Flutter chip fallback — copy the pattern in
      `status_selector.dart`, including its note about why the selected segment is untinted.
      **Superseded after review, twice.** The native _segmented control_ was the wrong shape: it spreads
      equal-width segments across the full width inside a grey track, which is a toolbar, not the short
      row of content-width pills `decided.html`'s `.caps` draws. The row is laid out by Flutter now, and
      so is every label — iOS 26 supplies only the _material_, a glass `CNButton` stacked behind the
      selected label. Giving the native button the text instead wrapped it onto two lines for half a
      second on every change (`setStyle` drops the attributed title; `setLabelStyle` lands hops later),
      and `LiquidGlassContainer`'s bare `glassEffect` had no material of its own to show over an opaque
      sheet. The glass button stays _interactive_ so the selected capsule answers a press the way a glass
      button should, and the ones Flutter draws **shrink** under the finger instead, as Flighty's do. One
      label weight throughout, too — the drawing's bolder selected label read as two type sizes in one
      row, and `decided.html` is corrected rather than the code.
      `HapticFeedback.selectionClick()` stands in for the haptics the segmented control gave for free. The
      collapsed popover below is unaffected. See the design record's "Filters".
- [x] Collapsed: a **glass popover select** in the header, where the filter label sits today.
      `CNPopupMenuButton` with `CNButtonStyle.glass` already does this — copy `shelf_selector.dart`, which
      also shows the checked-item idiom.
- [x] Month-level filtering is **dropped**: the grid is already grouped by month, so a month filter would
      leave a grid with one group in it.
- [x] `showYearMonthFilterBottomSheet` loses all three call sites (`home_page.dart` ×2,
      `user_library_page.dart`) and should go with them — along with its private `_YearMonthFilterSheet`,
      which is the first ~290 lines of `select_date_bottom_sheet.dart`. **The file itself stays:**
      `showSelectDateBottomSheet` at the bottom of it is the start/finish date picker that
      `book_info_bottom_sheet` uses, and it is unrelated. Removing the filter half is also the chance to
      clear the `unnecessary_import` that file carries in the pre-existing 12.
- [x] The `yearMonthLabel` l10n key goes if nothing else uses it; `yearLabel` and `all` stay.

**Fetch-all won.** `finishedBooksProvider` is a plain `FutureProvider.autoDispose<List<Book>>` and the year
filter is applied where the capsules are derived, in `FinishedBooksSheet`. A year-filtered query cannot
report the years it filtered out, so the alternative was two queries to answer one question.

`readFilterYears` returns just `[0]` when a filter **could not change anything** — one year of reading and
nothing undated means "all time" and that year select the same books, and `ReadFilter` renders nothing for a
single option. One undated book is enough to make the year worth offering, because then the two differ.

**Deviation on the l10n line:** `yearMonthLabel` went as planned, and `yearLabel` stays — it is now what
labels a year capsule, which matters because Korean writes a year as `2026년` and `'$year'` would drop the
년. But **`all` went too.** The plan expected the control to say "All"; every drawing says "All time", so
`allTime` is the key in use and `all` was left with no callers.

Both native callbacks are **non-nullable**, so `enabled: false` is a gate _inside_ the callback rather than a
null one. `read_filter_test.dart` covers that on both paths, because it is exactly the kind of gate that gets
dropped in a refactor.

**Two device-only findings**, neither visible in a widget test:

- The glass popover needed `shrinkWrap: true` and a `ConstrainedBox`, the same idiom `shelf_selector.dart`
  uses. A platform view has no intrinsic width, so without it the button simply filled what the header gave
  it — a glass pill across half the header instead of a compact select.
- The `UIMenu` opens **upward** from the collapsed header and iOS reverses the items to keep the first one
  nearest the button. Left alone rather than forced with `preserveTopToBottomOrder`: the flip puts the most
  recent years closest to the thumb. `decided.html`'s `lib-popover` was corrected to match.

No z-order bleed — the menu drew over the sheet and the library cleanly, which the Phase 1 `CNSearchBar` and
`UITabBar` findings had made a real worry.

**Where the year list comes from is a real decision, not a detail.** The capsules need the set of years the
user has finished books in, and today's provider cannot supply it: filtered by year, it only returns that
year. Two options —

- Fetch all finished books once and filter/group client-side. Removes the family key entirely, makes the
  year list derivable, and costs one unbounded query whose size is "books this person has read".
- Keep the filtered query and add a distinct-years provider beside it. Two queries, but each bounded.

Either is "no new data". Prefer the first unless the read count can plausibly reach the thousands.

**Done when:** the control is capsules when expanded and a popover when collapsed, both drive the same
state, and no month filter exists anywhere in the tree.

---

## Task 4: the providers

- [x] Drop `month` from `finishedBooksProvider` and `userFinishedBooksProvider`'s family keys and from both
      date-range branches in `library_provider.dart`.
- [x] Drop `readsFilterMonthProvider` and `friendReadsFilterMonthProvider` from
      `library_shell_provider.dart`.
- [x] Whichever shape Task 3 picks, keep the `order('finish_date', ascending: false)` — the grid's month
      order depends on it, and losing it turns grouping into a sort.

`finishedBooksProvider` lost its family key entirely; `userFinishedBooksProvider` is keyed by `String userId`
alone. The order is kept, and `read_month_grid_test.dart` asserts the group order rather than the row order,
so the two are pinned separately.

**Done when:** no `month` appears in any read-books provider or filter, and the grid's order comes from the
query rather than a client-side sort.

---

## Task 5: settle `user_library_page.dart`

- [x] Decide whether this page survives. It shows a friend's library as a **pushed page** with its own
      private year/month filter pair and its own `FinishedBooksSheet` — which is a second home for what a
      visit now does properly.
- [x] If it goes: `search_user_page.dart:44` and `settings_page.dart:880` — the only two places that push
      `AppRoutes.userLibrary` — should select the friend and let the shell show them, which is what the
      visit model is for. Note that `search_user_page` is now reached _from the Friends sheet_, so a search
      result leading to a visit closes the loop the sheet opened.
- [x] If it stays: it inherits Tasks 1–4, and its third filter pair should become the shared one so a
      friend's library does not filter differently depending on how you arrived.

**Decided: it stays, and here is the written reason the plan asked for.** A visit can only show someone the
shell can page to, and the pager's pages are the people you _follow_ — `_syncPageToFriend` ignores anyone
else and `HomePage` clears a selection that stops being followed. Both call sites reach past that:
`search_user_page.dart:44` searches **arbitrary** users and `settings_page.dart:880` lists **followers**.
Redirecting them into a visit would mean tapping a search result for someone you do not follow and landing
nowhere.

So it inherits Tasks 1–4 instead: it now shares `friendReadsFilterYearProvider` (the third private filter
pair is gone) and uses the new sheet API, so a friend's library filters the same however you arrived. There
are two routes to one read view, not two read views.

**This decision has been deferred twice** — once in Phase 1 Task 1 (whose commit message says to resolve it
"when the shell decides whether that page survives") and again in Task 5, which did not touch it. It cannot
be deferred a third time without leaving two divergent read views in the app, which is exactly what this
phase is meant to remove.

**Done when:** there is one read view, or two with a written reason why.

---

## Task 6: tests and verification

- [x] Rewrite `library_clearance_test.dart`'s bounding assertion: the sheet is bounded by the cap now, not
      by the pile's fixed height. Keep the measurement style — it is what caught the 2× text overflow.
- [x] Re-measure the clearance at 2× text on a 375×667 phone. The expanded state is taller than anything
      Phase 1 had, and the month header is new text that scales.
- [x] Adjust `test/library_sheet_test.dart` for the new collapsed definition (handle + header +
      `collapsedBody`), and add a case with an empty `collapsedBody` so the Card/Friends behaviour Phase 1
      pinned is still covered.
- [x] A grid test: month order, per-month counts, the header count matching the rendered total, and the
      null-`finish_date` decision from Task 2.
- [x] Assert the native filter controls only through the `useNativeGlass` gate, never by pumping them —
      `flutter test` reports Android, so the fallback is what runs. Phase 1's
      `test/shell_tab_bar_test.dart` has the pattern.
- [x] **Run it on a simulator.** Non-negotiable for this phase, more than for Phase 1: the drag-versus-
      scroll handoff, `CNSegmentedControl` and `CNPopupMenuButton` inside a moving sheet, and a popover
      anchored to a header that slides are all things no widget test reaches. Use
      `lib/main_shell_preview.dart` and the commands in Phase 1's Task 7.
- [x] Update `decided.html` only where the build proves a drawing wrong, and say so in the note.

**The clearance file earned its keep twice.** Its new expanded assertions are sharp rather than
`greaterThan`: on a 375×667 phone the library left behind an expanded sheet is `106.1`, which is exactly
`bookRowExtent(667 * 0.15)`, at both the default scale and 2×. An uncapped grid would leave nothing and the
first version of the cap left `40.1`, so only a correct cap lands there. The 2× case also asserts
`takeException()` is null, which is what surfaced the header overflow — worth knowing that the test font
makes every glyph one em wide, so "All time" measures 224pt there against ~125 on a device. That makes it a
strict upper bound, and the fix (both halves of the collapsed header flexible, pinned apart with
`spaceBetween`) is a real improvement for long labels in any locale.

`library_sheet_test.dart` is now two groups. The Phase 1 group is unchanged and is the
**empty-`collapsedBody`** case by construction — it is what Card and Friends get. The new group covers the
collapsed body, the cap, the scrolling body, the taller expanded header, and the arena-depth decision from
Task 1.

New files: `test/read_month_grid_test.dart` (grouping as a unit test, the grid as a widget test) and
`test/read_filter_test.dart` (`readFilterYears`, both native shapes behind the gate, both fallbacks, and the
inert case on all four). The host reports macOS 26, so under the iOS override the native assertions really
do run.

**Deliberately not asserted:** that the cover grid's image-load profile is acceptable. It was watched on
device with a preview fixture, which has no real thumbnails — so the lazy outer list is the mitigation and
the real profile is still unmeasured. Flagged below rather than claimed.

---

## Risks, in hindsight

- **Drag versus scroll** (Task 1) was budgeted as the risk that could eat the phase. It did not: arena depth
  resolved it with no arbitration code, and the device run confirmed it in one swipe. The risk that actually
  cost time was the cap's arithmetic, which nobody had flagged.
- **A native popover anchored inside a sheet that moves.** Clean — the `UIMenu` drew over the sheet and the
  library with no bleed. What it _did_ do was reorder its items, which is a behaviour rather than a bug.
- **The cover grid is the first place many images render at once.** Mitigated by the lazy outer `ListView`,
  but **still unmeasured**: the preview fixture has no real thumbnails, so no real `ImageStream` load was
  exercised. This is the one risk this phase leaves open, and it wants a device run against real data.
- **Phase 1's clearance numbers stop holding** the moment the grid lands. Re-derived rather than re-guessed:
  the collapsed numbers barely moved (Phase 2's collapsed _is_ Phase 1's expanded), and the expanded ones are
  new and now measured.

## Open questions, settled

- **Does the Library sheet get a third snap position** — title-only, as `card-down` draws for the Card tab?
  **No.** Two positions, as this plan assumed. Nothing in building it wanted a third, and the drag-down
  gesture stays a straight two-way toggle.
- **Where undated finished books go** — a trailing `readNoDate` group (Task 2).
- **Fetch-all versus filtered-plus-distinct-years** — fetch-all (Task 3).
- **Whether `user_library_page.dart` survives** — it stays, because a visit cannot show a non-followed user
  (Task 5).
- **Whether the capsule row scrolls** when a long-time reader has eight years of history. **It scrolls** — a
  horizontal `SingleChildScrollView`, on every platform now that Flutter lays the row out rather than a
  single native control. (It used to split: `CNSegmentedControl` compressed its segments instead, which was
  the platform's own answer.) Not verified past three capsules, because no fixture has eight years — if it
  ever looks wrong, collapsing to the popover past some count is the fallback the drawings could not decide.
