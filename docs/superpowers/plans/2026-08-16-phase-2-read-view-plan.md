# Phase 2: the read view — Implementation Plan

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

- [ ] `LibrarySheet` takes `collapsedBody` (optional) and `expandedBody`. Collapsed snap = handle + header +
      `collapsedBody`; expanded snap = `min(natural height, cap)`.
- [ ] The cap is expressed as **"one shelf stays visible"**, not as a magic percentage — the drawing's 79%
      is a consequence, not the rule. `bookRowExtent(bookHeight)` in `book_widget.dart` is the same function
      the library uses to size a shelf row, so the cap is `screen − chrome − bookRowExtent(...)`. Deriving it
      that way means the sheet and the library cannot disagree about what "one shelf" is.
- [ ] When the expanded content exceeds the cap, the body scrolls inside the sheet. When it does not, the
      sheet is shorter than the cap and nothing scrolls.
- [ ] Keep every Phase 1 behaviour: the under-damped spring, overdrag with rubber-band, inert in edit mode,
      the home-indicator inset, `bottomReserve`, and nothing stranded underneath.

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

**Done when:** the sheet still passes `test/library_sheet_test.dart` (adjusted for the new collapsed
definition), the grid scrolls at the cap, and `library_clearance_test.dart` asserts the cap instead of the
pile's fixed height.

---

## Task 2: the two bodies

- [ ] `ReadPile` — extract today's spine row out of `FinishedBooksSheet` unchanged. It becomes the
      collapsed body, and it is already a fixed-height horizontal `ListView` of `BookVertical`.
- [ ] `ReadMonthGrid` — the expanded body: for each month, a header row of month name + count
      (`.mh` in the drawings: name left, count right), then a **4-column grid of covers at aspect ratio
      2:3** (`.mg`, 3px gaps). Newest month first, which is the order the query already returns.
- [ ] Group client-side off `Book.finishDate`. Books with a null `finish_date` are finished-but-undated:
      decide where they go — a trailing "no date" group, or excluded from the grid — and say which, because
      silently dropping rows from a count the header shows is the kind of bug nobody reports.
- [ ] Reuse `BookWidget` for the covers rather than a new widget, so long-press, the press effect and the
      details push behave as they do on the shelves.

**Done when:** collapsed shows the pile and expanded shows the grid, the header count matches the number of
books actually rendered across all groups, and a book with no finish date is accounted for one way or the
other by a test.

---

## Task 3: the filter changes shape with the sheet, and loses months

- [ ] Expanded: an **iOS 26 capsule row** of `All time / <year> / <year> …` below the header.
      `CNSegmentedControl` already does this natively with a Flutter chip fallback — copy the pattern in
      `status_selector.dart`, including its note about why the selected segment is untinted.
- [ ] Collapsed: a **glass popover select** in the header, where the filter label sits today.
      `CNPopupMenuButton` with `CNButtonStyle.glass` already does this — copy `shelf_selector.dart`, which
      also shows the checked-item idiom.
- [ ] Month-level filtering is **dropped**: the grid is already grouped by month, so a month filter would
      leave a grid with one group in it.
- [ ] `showYearMonthFilterBottomSheet` loses all three call sites (`home_page.dart` ×2,
      `user_library_page.dart`) and should go with them — along with its private `_YearMonthFilterSheet`,
      which is the first ~290 lines of `select_date_bottom_sheet.dart`. **The file itself stays:**
      `showSelectDateBottomSheet` at the bottom of it is the start/finish date picker that
      `book_info_bottom_sheet` uses, and it is unrelated. Removing the filter half is also the chance to
      clear the `unnecessary_import` that file carries in the pre-existing 12.
- [ ] The `yearMonthLabel` l10n key goes if nothing else uses it; `yearLabel` and `all` stay.

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

- [ ] Drop `month` from `finishedBooksProvider` and `userFinishedBooksProvider`'s family keys and from both
      date-range branches in `library_provider.dart`.
- [ ] Drop `readsFilterMonthProvider` and `friendReadsFilterMonthProvider` from
      `library_shell_provider.dart`.
- [ ] Whichever shape Task 3 picks, keep the `order('finish_date', ascending: false)` — the grid's month
      order depends on it, and losing it turns grouping into a sort.

**Done when:** no `month` appears in any read-books provider or filter, and the grid's order comes from the
query rather than a client-side sort.

---

## Task 5: settle `user_library_page.dart`

- [ ] Decide whether this page survives. It shows a friend's library as a **pushed page** with its own
      private year/month filter pair and its own `FinishedBooksSheet` — which is a second home for what a
      visit now does properly.
- [ ] If it goes: `search_user_page.dart:44` and `settings_page.dart:880` — the only two places that push
      `AppRoutes.userLibrary` — should select the friend and let the shell show them, which is what the
      visit model is for. Note that `search_user_page` is now reached _from the Friends sheet_, so a search
      result leading to a visit closes the loop the sheet opened.
- [ ] If it stays: it inherits Tasks 1–4, and its third filter pair should become the shared one so a
      friend's library does not filter differently depending on how you arrived.

**This decision has been deferred twice** — once in Phase 1 Task 1 (whose commit message says to resolve it
"when the shell decides whether that page survives") and again in Task 5, which did not touch it. It cannot
be deferred a third time without leaving two divergent read views in the app, which is exactly what this
phase is meant to remove.

**Done when:** there is one read view, or two with a written reason why.

---

## Task 6: tests and verification

- [ ] Rewrite `library_clearance_test.dart`'s bounding assertion: the sheet is bounded by the cap now, not
      by the pile's fixed height. Keep the measurement style — it is what caught the 2× text overflow.
- [ ] Re-measure the clearance at 2× text on a 375×667 phone. The expanded state is taller than anything
      Phase 1 had, and the month header is new text that scales.
- [ ] Adjust `test/library_sheet_test.dart` for the new collapsed definition (handle + header +
      `collapsedBody`), and add a case with an empty `collapsedBody` so the Card/Friends behaviour Phase 1
      pinned is still covered.
- [ ] A grid test: month order, per-month counts, the header count matching the rendered total, and the
      null-`finish_date` decision from Task 2.
- [ ] Assert the native filter controls only through the `useNativeGlass` gate, never by pumping them —
      `flutter test` reports Android, so the fallback is what runs. Phase 1's
      `test/shell_tab_bar_test.dart` has the pattern.
- [ ] **Run it on a simulator.** Non-negotiable for this phase, more than for Phase 1: the drag-versus-
      scroll handoff, `CNSegmentedControl` and `CNPopupMenuButton` inside a moving sheet, and a popover
      anchored to a header that slides are all things no widget test reaches. Use
      `lib/main_shell_preview.dart` and the commands in Phase 1's Task 7.
- [ ] Update `decided.html` only where the build proves a drawing wrong, and say so in the note.

---

## Risks

- **Drag versus scroll** (Task 1) is the one that can eat the phase. Everything else is layout and data
  shape. Budget accordingly, and prototype it on a device before building the grid.
- **A native popover anchored inside a sheet that moves.** `CNSearchBar` has a documented z-order bleed
  through sheets, and Phase 1 found a native `UITabBar` drawing over modal content. Assume a `UIMenu`
  presented from a sliding sheet can misbehave until seen otherwise on hardware.
- **The cover grid is the first place many images render at once.** `BookWidget` loads through an
  `ImageStream` with per-instance listeners; a 4-wide grid of a heavy reader's year is a different load
  profile from a shelf row. Watch memory and first-paint on device, not in tests.
- **Phase 1's clearance numbers stop holding** the moment the grid lands. They are documented in Phase 1's
  Task 6 with the arithmetic, so re-derive rather than re-guess.

## Open questions to settle during, not before

- **Does the Library sheet get a third snap position** — title-only, as `card-down` draws for the Card tab?
  The Library tab is drawn at two heights only. Two positions is the reading this plan assumes; if a
  title-only state is wanted as well, the spring and the snap-nearest logic both need a third target and
  the "drag down reveals the library" gesture gets a middle stop.
- **Where undated finished books go** (Task 2).
- **Fetch-all versus filtered-plus-distinct-years** (Task 3).
- **Whether `user_library_page.dart` survives** (Task 5).
- **Whether the capsule row scrolls** when a long-time reader has eight years of history, or whether it
  collapses to the popover past some count. The drawings show three capsules and cannot answer it.
