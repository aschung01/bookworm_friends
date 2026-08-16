# Phase 1: the library shell — Implementation Plan

> **For agentic workers:** Implement task-by-task, in order. Steps use checkbox (`- [ ]`) syntax
> for tracking. Read `.agents/skills/flutter-tester/SKILL.md` before writing any test — this
> project has established Given-When-Then and layer-isolation conventions.

**Design:** `docs/superpowers/specs/2026-08-14-library-shell-design.md`
**Drawings:** `docs/mockups/library-shell/decided.html` — screens, elements and flows

**Goal:** Replace today's app-bar-plus-pager library with the decided shell: a floating tab bar
(Library / Friends / Card) over one persistent library background, each tab's content in one
draggable sheet, and a friend's library as a **visit** that hides the tab bar and carries its own
rail with a glass ✕.

**No new data.** No migrations, no new columns, no new queries beyond composing what
`followingListProvider`, `libraryProvider`, `finishedBooksProvider` and `userLibraryProvider`
already return. That is what makes this phase safe to do first.

**Not in scope:** month grouping and the cover grid (Phase 2), Library Card _stats_ (Phase 3 —
this phase gives the Card tab its sheet, not its contents), the Activity feed (Phase 4), and the
shelf-hint praise proposal (undecided).

---

## Current state

`lib/ui/pages/home_page.dart` is 1,297 lines and holds everything:

| Lines    | Class                           | Role                                                                                                                                                                              |
| -------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 32–41    | six `StateProvider.autoDispose` | `_libraryMode`, `_selectedFriend`, `_filterYear/_filterMonth`, `_friendFilterYear/_friendFilterMonth` — **all private to the file**                                               |
| 43–366   | `HomePage` / `_HomePageState`   | `_pageController` sync, add-book, add/rename/delete shelf, delete book; `Scaffold` with `AppBar(title: _FriendAvatarBar, bottom: _LibrarySubHeader)` and `body: PageView.builder` |
| 368      | `_FriendLibraryPage`            | one friend's page inside the pager                                                                                                                                                |
| 425      | `_FriendAvatarBar`              | the rail — today **always** in the app bar                                                                                                                                        |
| 470      | `_LibrarySubHeader`             | username, edit, add, done, manage shelves, poke                                                                                                                                   |
| 620      | `_AvatarCircle`                 |                                                                                                                                                                                   |
| 784      | `_LibraryWithFinishedBooks`     | `Column(Expanded(library), FinishedBooksSheet)`                                                                                                                                   |
| 958–1234 | `_ShelfRow` / `_ShelfRowState`  | `_buildBookContent`, `_buildEditableBookList`, drag-reorder                                                                                                                       |
| 1235     | `_DeleteBookButton`             |                                                                                                                                                                                   |
| 1283     | `_DelayedReorderableListener`   |                                                                                                                                                                                   |

Those six private providers are the reason the file cannot be split: every extracted widget would
need them. **They move first.**

What already exists and must be reused, not rebuilt:

- `FinishedBooksSheet` (418 lines) — two snap positions, under-damped spring, overdrag with
  rubber-band, springs shut and goes inert in edit mode. The drag-down gesture the design calls for
  is **already built**; it is currently hard-wired to read books.
- `native_glass.dart` — `useNativeGlass` gates on target platform _and_ OS version, with a documented
  trap about `flutter test` reporting Android.
- `CNTabBar` in `cupertino_native_better`, and `CNTabBarRouteObserver()` is **already registered** in
  `main.dart:97`.
- `test/support/home_page_harness.dart` — `pumpHome`, `enterEditMode`, `simulateSystemBack`,
  `FakeLibraryNotifier`, and two documented traps (wiggle defeats `pumpAndSettle`; back is a
  platform-channel message).
- `test/library_sheet_layout_test.dart` — pins that the sheet and library never overlap.

---

## Task 1: Lift the six providers out of `home_page.dart`

- [x] Move `_libraryModeProvider`, `_selectedFriendProvider` and the four filter providers into
      `lib/providers/library_shell_provider.dart`, made public.
- [x] Replace the two filter pairs with one family keyed by whose library it is, if they turn out to
      be the same shape — check before merging; the friend pair exists because a visit filters a
      different pile. **Checked, not merged:** the friend pair is deliberately shared by every friend
      so paging keeps the filter, and `user_library_page.dart` holds a third pair — unifying them is a
      behaviour change that belongs to Task 5, where that page's fate is decided.
- [x] `home_page.dart` imports them; no behaviour changes.

**Why first:** nothing else can be extracted while the state is file-private.

**Done when:** `flutter test` is green with zero changes to any test, and `home_page.dart` declares no
providers. A green suite here is the whole point — this task must be behaviour-neutral.

**Done** in `6e8b2a4`: 183 tests green, no test edits.

---

## Task 2: Extract the pieces that do not care about the shell

- [x] `lib/ui/widgets/shelf_row.dart` — `ShelfRow`, `_DeleteBookButton`, `_DelayedReorderableListener`
      (~350 lines, the largest single lift).
- [x] `lib/ui/widgets/avatar_circle.dart` — `AvatarCircle`.
- [x] `lib/ui/widgets/friend_rail.dart` — `FriendAvatarBar`, renamed `FriendRail`: the design scopes it
      to a visit and gives it a lead slot for the glass ✕, so it stops being an app-bar strip.
- [x] `lib/ui/views/library_view.dart` — `LibraryWithFinishedBooks`, which is the background plus sheet.

**Done when:** `home_page.dart` is under ~400 lines and the suite is still green with no test edits.
Same rule as Task 1: pure motion, no behaviour.

**Done** in `b8c7281`, but at **563 lines**, not under 400. What is left is `HomePage`,
`_FriendLibraryPage` and `_LibrarySubHeader` — and those are exactly the three things Tasks 4 and 5
rewrite, so splitting them further now would be churn against code about to change. 183 tests green,
no test edits.

---

## Task 3: One sheet, per-tab contents

- [x] Generalise `FinishedBooksSheet` into `LibrarySheet`: keep the spring, snap positions, overdrag
      and inert-in-edit-mode behaviour; take the header row and body as parameters.
- [x] Keep a thin `FinishedBooksSheet` wrapper, or update both call sites (`home_page.dart`,
      `user_library_page.dart`) — decide by which produces less churn. **Wrapper wins:**
      `FinishedBooksSheet` stays as the Library tab's contents and composes `LibrarySheet`, so both
      call sites and both test files are untouched. The name also matches the l10n keys
      (`finishedBooksTitle`, `noFinishedBooks`), so renaming it would desync the vocabulary.
- [ ] Sheet contents per tab: **Library** → today's read-books pile; **Friends** → the Everyone list;
      **Card** → header and empty state only, since stats are Phase 3.
      **Moved to Task 4.** Only the Library body is built here. A Friends or Card body written now
      would be unreachable — nothing can select it until the tab bar exists — and the Everyone list
      needs a per-friend currently-reading book and read count, which is a data question Phase 1 said
      it would not open. Task 4 builds the bar and the two remaining bodies together, where each is
      reachable and testable.

What landed: `lib/ui/widgets/library_sheet.dart` holds `LibrarySheet` (chrome and motion, taking
`header` / `body` / `isEditMode`) and `LibrarySheetTitle` (the shared title-and-count pair, so three
tabs don't become three type sizes). The handle, the 25px gutter, the corner radius, the shadow and the
home-indicator inset are chrome; interactive controls inside `header` and `body` stay the caller's to
gate, because children win hit tests and the sheet cannot disable them from outside — the read-books
filter therefore nulls its own `onTap` in edit mode, as before.

**The rule to preserve:** the sheet must keep reading as sitting _above_ the library, with nothing
stranded underneath. Today that falls out of `Column(Expanded(library), sheet)`. If this task moves to
a `Stack`, the library needs a bottom inset equal to the collapsed sheet height, and
`library_sheet_layout_test.dart` must be rewritten deliberately rather than deleted.

**Tests:** extend the existing sheet suite for a non-read-books body; assert the two snap positions
still hold and that edit mode still springs it shut.

**Done:** `Column(Expanded(library), sheet)` is unchanged, so `library_sheet_layout_test.dart` still
passes untouched and the rule still holds by construction. `test/library_sheet_test.dart` adds six
tests driving `LibrarySheet` with a 200px placeholder body; the sharp one asserts the collapsed height
equals handle + header and is **unchanged when the body doubles** — a sheet that collapsed to some
fraction of its content would pass every read-books test and still strand a tab's body underneath.
189 tests green, no existing test edited.

---

## Task 4: The floating tab bar

- [ ] `lib/ui/widgets/shell_tab_bar.dart` — Library / Friends / Card plus the detached search control,
      native on iOS 26 via `CNTabBar` and a Flutter pill fallback elsewhere, gated by `useNativeGlass`.
- [ ] Tab state in `library_shell_provider.dart`; switching a tab swaps only the sheet's contents, never
      the background.
- [ ] The two sheet bodies deferred from Task 3: **Friends** → the Everyone list (decide first whether
      Phase 1 shows each friend's currently-reading book and read count, or only names — that is the
      data question Task 3 refused to open); **Card** → header and empty state only, since stats are
      Phase 3.
- [ ] Remove the app bar's search-friends and settings buttons; the bar becomes "My Library" with share
      and profile per the design. New l10n keys in `app_en.arb` / `app_ko.arb`, then `flutter gen-l10n`.

**Decision needed here.** `CNTabBar` has a first-class `searchItem` that iOS 26 renders as exactly the
detached circular button the design draws — but it expands into an _inline search field_
(`onSearchChanged`), whereas the design says the button opens Add Book as a 95% modal. Since Add Book
_is_ a search ("Title, author, or ISBN"), the native pattern may be the better version of the same
intent. Try the native search tab first; fall back to a plain button opening the modal if the inline
field cannot host results well.

**Tests:** widget test that all three tabs render and switch the sheet body; a test that the fallback pill
is used when `useNativeGlass` is false (which is what `flutter test` reports, so the fallback is the
path under test by default — assert the native path only through the gate, not by pumping it).

---

## Task 5: A visit

- [ ] Entering: tapping a friend in the Everyone list enters a visit — tab bar hidden, `FriendRail` inside
      the visit with the glass ✕ at its head, lateral swipe between friends on the existing `PageView`.
- [ ] Leaving: the ✕ clears the selection and restores the tab bar with Friends still lit.
- [ ] Keep `_syncPageToFriend`'s two existing guards: the pager sync when selection changes by tap, and the
      fallback to your own library when the viewed friend is no longer followed.
- [ ] `PopScope` must now handle three states, not two: edit mode exits first, then a visit ends, then the
      page may pop.

**Known-fine:** `home_page.dart` already nests horizontal drag-reorder inside the friend `PageView` and
already gates paging physics by mode, so the swap is choreography, not gesture arbitration.

**Tests:** entering a visit hides the tab bar and shows the rail; the ✕ restores it; system back exits a
visit before it pops the page (extend `library_back_navigation_test.dart`).

---

## Task 6: Fix the 5.8px clearance

- [ ] Measure the real bar-to-sheet clearance on a friend screen in a widget test, then fix it — a shorter
      expanded sheet, or the rail participating in layout rather than overlaying.
- [ ] Assert a minimum clearance so it cannot regress.

This is pre-existing, measures the same in every mockup version including `main`, and Phase 1 is the moment
it gets touched. Do it here rather than discovering it on device.

---

## Task 7: Tests and verification

- [ ] Suite green throughout; Tasks 1 and 2 must not need a single test edit.
- [ ] `flutter analyze lib test` clean of new findings — the 12 pre-existing infos are catalogued and none
      are in files this phase creates.
- [ ] Prove each regression test fails without its fix (`git stash push <files>`, run, pop).
- [ ] **Run it on a simulator.** Native platform views inside and over scrolling content are the risk this
      phase carries, and no widget test reaches them: the tab bar's glass, the sheet's drag against the
      pager's horizontal swipe, and the visit transition. `CNSearchBar`'s documented z-order bleed through
      sheets (`autoHideOnModal`) is the precedent — assume the tab bar can do the same until seen otherwise.
- [ ] Update `decided.html` only where the build proves a drawing wrong, and say so in the note rather than
      quietly redrawing.

---

## Risks

**Sheet drag versus pager swipe.** One vertical gesture and one horizontal gesture over the same area, with
drag-reorder nested inside both in edit mode. It works today because paging physics are gated by mode; the
visit adds a third context. Watch for the sheet stealing horizontal drags near its handle.

**Native chrome in a scrolling world.** The tab bar floats over a scrolling library and a draggable sheet.
Platform views compose differently from Flutter widgets, and this package has a known z-order bug in exactly
that combination.

**`useNativeGlass` is false under test.** Every widget test exercises the fallback. The native path can only
be verified by eye on a device — state that in the final report rather than implying coverage.

**Scope creep into Phase 2.** The Library sheet's expanded state is _today's pile_, not the month grid. Ship
the shell with the old contents; the grid is the next phase.

---

## Open questions to settle during, not before

1. **Card tab before Phase 3.** Header plus empty state, or hide the tab until it has stats? Drawing it empty
   may look broken; hiding it changes the tab count the shell is built around. Decide when the sheet exists.
2. **`user_library_page.dart`.** Once a friend's library is a visit inside the shell, is that route still
   reachable, or does it become dead? It is **not** dead today: `search_user_page.dart:44` pushes it after a
   user search, and `settings_page.dart:880` pushes it from the follow lists. So either those two call sites
   learn to enter a visit instead, or the route stays as a second way to see the same thing. It also shares
   `FinishedBooksSheet` and is covered by `library_read_books_test.dart`, so it cannot be deleted casually.
3. **Settings' new home.** The menu button leaves the app bar; the design gives the bar a profile control.
   Confirm settings hangs off that rather than becoming unreachable.
