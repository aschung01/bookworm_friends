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

- [x] `lib/ui/widgets/shell_tab_bar.dart` — Library / Friends / Card plus the detached search control,
      native on iOS 26 via `CNTabBar` and a Flutter pill fallback elsewhere, gated by `useNativeGlass`.
- [x] Tab state in `library_shell_provider.dart`; switching a tab swaps only the sheet's contents, never
      the background.
- [x] The two sheet bodies deferred from Task 3: **Friends** → the Everyone list (decide first whether
      Phase 1 shows each friend's currently-reading book and read count, or only names — that is the
      data question Task 3 refused to open); **Card** → header and empty state only, since stats are
      Phase 3. **Decided: names and avatars only.** What each friend is reading and their read count
      are per-friend queries (`userLibraryProvider`, `userFinishedBooksProvider` are keyed by user id),
      so drawing the row as designed means one round trip per row the moment the tab opens. That wants
      one batched query, which is a data change. The row is already enough to be the way into a visit,
      which is all the shell needs from it — same reason the design puts Activity after Phase 1. Noted
      in `friends_sheet.dart` so the gap against the drawing is not mistaken for an oversight.
- [ ] Remove the app bar's search-friends and settings buttons; the bar becomes "My Library" with share
      and profile per the design. New l10n keys in `app_en.arb` / `app_ko.arb`, then `flutter gen-l10n`.
      **Moved to Task 5.** Add Friend has already moved into the Friends sheet, but the app bar's title
      slot is currently occupied by `FriendRail`, and where the rail lives is Task 5's first decision.
      Retitling the bar before the rail moves would mean fitting a title and a rail into one row for
      the length of one commit.

**Decision needed here.** `CNTabBar` has a first-class `searchItem` that iOS 26 renders as exactly the
detached circular button the design draws — but it expands into an _inline search field_
(`onSearchChanged`), whereas the design says the button opens Add Book as a 95% modal. Since Add Book
_is_ a search ("Title, author, or ISBN"), the native pattern may be the better version of the same
intent. Try the native search tab first; fall back to a plain button opening the modal if the inline
field cannot host results well.

**Settled — and the premise was wrong.** Read against `cupertino_native_better` 1.5.4's actual source:
on iOS 26 the search item is _already_ a plain button. The Swift view behind it
(`CupertinoTabBarSearchView.swift`) builds an ordinary `UITabBar` with a `.search` system item and
contains no text field, `UISearchTab` or `UISearchController` at all; `onSearchChanged` and
`onSearchSubmit` are published on the channel `CNSearchScaffold` uses and never fire from the tab bar.
The only hook is `onSearchActiveChanged(true)`, which is the tap. So there is no trade-off: we get the
native detached orb _and_ the modal.

Two consequences worth knowing:

- The inline field the package documents is **fallback-only**. So `CNTabBar`'s fallback is deliberately
  not used — off iOS 26 it would grow a search field in the bar, which is a different interaction that
  would appear on exactly the platforms we cannot see. The pill and circle are hand-rolled instead.
- The native bar leaves the search item selected after a tap and never puts it back, so
  `CNTabBarSearchController.deactivateSearch()` is called right after opening Add Book. Without it the
  bar claims you are on a fourth tab that does not exist.

Also settled by reading the source: `height` is passed explicitly rather than letting the bar measure
itself, because the measured height is private with no constant and no callback — and the sheet has to
reserve exactly that much room. And with a search item set the native view ignores rasterised icons and
icon sizes entirely, so the three tabs must be SF Symbols.

**Tests:** widget test that all three tabs render and switch the sheet body; a test that the fallback pill
is used when `useNativeGlass` is false (which is what `flutter test` reports, so the fallback is the
path under test by default — assert the native path only through the gate, not by pumping it).

**Done.** `test/shell_tab_bar_test.dart`, six tests, 195 green with no existing test edited. The one
that earns its keep asserts that a tab switch keeps the **same `ShelfRow` `State` object** — a `State`
survives a rebuild but not a replacement, so it is the sharpest available proof that the background
persisted rather than merely looked the same. Also pinned: the bar's floating geometry, and that it
covers none of the sheet's contents.

**How the bar and the sheet share the bottom**, taken from the drawings rather than invented:
`decided.html` gives the sheet `padding-bottom: 32px` of its 340px frame and floats `.tb` at
`bottom: 8px` with `z-index: 9` over the sheet's `5`. So the bar overlaps only the sheet's reserved
band, never its contents. In Flutter that is `LibrarySheet.bottomReserve`, set to `ShellTabBar.reserve`
(`gap + height + gap`), with the bar positioned at the same `gap` above the home-indicator inset the
sheet already reserves. Both sides read the same constants, so the clearance is fixed by construction
and is not a measurement — which is the shape Task 6 wants.

**Found while building, not in the design:** in edit mode the tab bar is still live, so you can switch
to Friends or Card mid-edit. `FinishedBooksSheet` springs shut for an edit; `FriendsSheet` and
`LibraryCardSheet` take no `isEditMode` and stay expanded, so the library gets less room to rearrange
in than it does today. Neither the design record nor the mockups say what the bar does during an edit.
Left live rather than guessed at; settle it in Task 6 alongside the clearance, since both are about
what the bottom of the screen owes the library. **Confirmed on device — see Task 7.**

### Task 7 verified this task on an iOS 26.4 simulator, and it found three bugs

Run through `argent` against an iPhone 17 Pro / iOS 26.4 simulator using
`lib/main_shell_preview.dart` — a verification-only entrypoint that pumps the real `HomePage` with the
real `MaterialApp`, theme and `CNTabBarRouteObserver`, with the Supabase-backed providers replaced by
fixtures. It exists because reaching `HomePage` in the shipped app needs Apple or Google sign-in, and
because `flutter test` reports Android — so **every widget test in this repo exercises the fallback
chrome, and the native path had never once been rendered.** All three bugs below were invisible to the
195 green tests.

1. **The native bar was squashed: labels drawn on top of icons.** `height: 50` was a guess. Measured by
   building with `height: null` and reading the rendered `UITabBar`'s frame: an iOS 26 tab bar with
   three labelled items plus a search item wants **83**. Fixed by making the height path-specific — 83
   native, 50 for our own pill — with the provenance recorded at the constant.
2. **The sheet's last row was covered.** `reserve` was derived from the wrong height, so the shelf the
   read pile stands on sat behind the bar. Fixed by the same change; `reserve` is a getter over
   `height`, so the two cannot drift again.
3. **The search orb stayed lit after Add Book closed.** `deactivateSearch()` was called immediately
   after pushing, which runs while the pushed page covers the bar; the item came back still tinted as
   the active tab. Fixed by making `onAddBook` awaited and deactivating once Add Book closes — which is
   also the truthful behaviour, since the search item _is_ active while its UI is open.
4. **The bar floated ~20pt too high** (spotted by eye on the real app, then measured). The box was
   pinned at `viewPadding.bottom + gap` = 42pt off the screen bottom, which is right — but the visible
   glass is **not** the box. iOS lays the platter out as **62pt anchored to the top of the 83pt frame**,
   keeping 21pt of padding at the bottom of its own box, because a `UITabBar` expects to sit flush with
   the screen edge and own the home-indicator strip itself. So the glass ended up 63pt up, not 42.
   Fixed by splitting `_boxHeight` (83) from `visualHeight` (62) and subtracting the difference in
   `bottomOffset`; `reserve` is now derived from `visualHeight`, so the sheet reserves what is actually
   drawn. Verified by reading `_UITabBarPlatterView`'s window frame: its bottom edge is now at 42pt.

   Worth generalising: **a native platform view's frame is not its drawing.** Positioning by the frame
   is what put the glass in the wrong place, and only the view hierarchy showed the difference.

What the run confirmed as correct: the native path renders the design as drawn — a floating glass pill
with a genuinely detached circular orb, no hand-rolling needed. A tab switch swaps only the sheet; the
shelves keep their size and position and you simply see more or less of them, which is the "nothing
scales" rule holding on real chrome. The collapsed sheet leaves handle and header above the bar. And
there is **no native-view-over-Flutter bleed** on either pushed page (Add Book, book details), which is
the `CNTabBar` failure mode `CNTabBarRouteObserver` exists to prevent.

What it confirmed as a genuine gap: switching to Card mid-edit leaves the Card sheet **expanded** while
the covers are still wiggling, so the library has less room to rearrange in than the Library tab gives
it. Nothing is stranded — the shelf list is scrollable and `Column(Expanded(library), sheet)` still
holds — but it is visibly the wrong sheet state for the mode. Task 6.

**Not done, and it is a real deviation from the design:** the orb opens Add Book as a **full-page push**
(the existing `AppRoutes.search`), not the 95%-height modal the design specifies. Preserved rather than
changed because re-presenting that page is its own piece of work — but it is unfinished Task 4 scope,
not a decision. **Now done — see below.**

### Both Task 7 gaps closed

**The edit-mode sheet state.** An edit now hides the bar, and every sheet takes `isEditMode`. The
design's own rule decided it: focused dismissible contexts drop their chrome, which is the stated reason
a visit hides the bar, and an edit is one — it has a Done. Hiding the bar alone was not enough, because
an edit can start from any tab, so `FriendsSheet` and `LibraryCardSheet` spring shut too and
`bottomReserve` drops to 0. Rejected: forcing the tab back to Library on entering an edit, which works
but silently moves you and then makes Done decide whether to move you back.

**Add Book is a 95% modal.** `search_book_page.dart` moved to
`ui/widgets/bottom_sheets/add_book_bottom_sheet.dart`, and the `/search` route is gone — nothing pushed
it but the orb, so keeping the pushed presentation would have left dead chrome. The field is extracted
as `SearchTextField` / `SearchFieldPill` so the sheet and `search_user_page`'s header cannot drift.

One trap worth recording: **`showDragHandle: true` adds Material's handle _outside_ the builder's
child**, so its height lands on top of an exact requested height. A sheet asked for 95% measured ~98%,
with no barrier left to see and no rounded corners — it read as a full-screen page, which is the one
thing the modal was supposed not to be. Fixed by drawing `SheetGrabHandle` inside the box instead, and
the test now pins the sheet's top edge at 5% ± 2pt rather than its height within a loose tolerance,
because the loose bound is exactly what failed to notice.

Verified on device: rounded corners, handle, visible dimmed barrier, real search results over the
network, and the nested `book_info_bottom_sheet` still working over it. The native tab bar auto-hides
behind the modal rather than being drawn dimmed behind it as `decided.html` shows — deliberate: a
`UITabBar` composited over Flutter modal content is a real rendering bug, and auto-hide is the mechanism
that prevents it.

### Found on the way, pre-existing, not fixed

**The app bar's native glass icon buttons bleed over stacked modals.** With Add Book open _and_ the
book-info sheet open on top of it, `native-find-views --className ChildClippingView` reports the home
app bar's search and menu buttons at y=70, x=299 and x=347, `hidden=false, alpha=1` — drawn over both
sheets as a white rectangle beside the close button. Under a _single_ modal they hide correctly, so
whatever depth tracking they use handles one level and not two. Reproducible today without any of this
phase's changes (manage shelves → rename is two stacked sheets from the same app bar), so it is
pre-existing and belongs to whatever revisits `AdaptiveIconButton`, not to Phase 1.

---

## Task 5: A visit

- [x] Entering: tapping a friend in the Everyone list enters a visit — tab bar hidden, `FriendRail` inside
      the visit with the glass ✕ at its head, lateral swipe between friends on the existing `PageView`.
- [x] Leaving: the ✕ clears the selection and restores the tab bar with Friends still lit.
- [x] Keep `_syncPageToFriend`'s two existing guards: the pager sync when selection changes by tap, and the
      fallback to your own library when the viewed friend is no longer followed.
- [x] `PopScope` must now handle three states, not two: edit mode exits first, then a visit ends, then the
      page may pop.
- [x] The app bar retitle deferred from Task 4.

**Known-fine:** `home_page.dart` already nests horizontal drag-reorder inside the friend `PageView` and
already gates paging physics by mode, so the swap is choreography, not gesture arbitration.

**Tests:** entering a visit hides the tab bar and shows the rail; the ✕ restores it; system back exits a
visit before it pops the page (extend `library_back_navigation_test.dart`).

**Done.** 203 green. What landed, and the one thing that turned out to be broken all along:

**The bar is now the whole of the top chrome.** The old `AppBar` held the rail plus a glass search and a
hamburger; all three are gone. Search-friends moved into the Friends sheet in Task 4, settings became the
profile action, and the rail moved into the visit — so outside a visit `toolbarHeight` is 0 and
`_LibraryBar` (was `_LibrarySubHeader`) is the only row. Three states, title fixed: "My Library" +
profile / "jisoo's Library" + Poke / ⇅ + Done.

**Share is deliberately absent**, though the design draws it beside profile. There is nothing to share:
the shareable artifacts it would offer belong to the Library Card, which is Phase 3, and a share sheet
that can only offer a screenshot is worse than no button in the bar. Add it with the artifacts.

**Edit and `+` are gone**, as the design says. `+` was already duplicated by the tab bar's orb, and
`ShelfRow` already wired a long press to edit — which is where this got interesting.

### Long-press-to-edit never worked, and removing the pencil exposed it

With the pencil gone, long press is the only way into an edit, so it had to be checked rather than
assumed. A probe test held the press and printed the mode each 100ms:

```
after 700ms: editing=false
after 800ms: editing=true
after release: editing=false      <-- letting go closed what the press opened
```

The cause is structural. Entering edit mode replaces the shelf's whole list — the plain row becomes a
`ReorderableListView` of `Draggable`s — so the `BookWidget` element holding the in-flight tap is
destroyed at the instant the mode flips. Its gesture-arena entry goes with it, and the page-level "tap
anywhere to leave edit mode" handler inherits the release. `ShelfRow` already has a no-op `onTap` whose
comment says it exists to stop cover taps reaching that handler; it cannot help here, because the widget
that would swallow the tap no longer exists by the time the finger lifts.

This was **pre-existing** — nothing in this phase caused it. The pencil simply masked it, and the earlier
device attempt at a long press (which appeared to do nothing) was this bug, not a missed gesture.

Fixed with a one-shot latch in `_HomePageState`: `_enterEditMode` sets it, the stray tap consumes it, and
a `Listener(onPointerDown:)` clears it so it can never outlive the gesture that set it — which matters if
that gesture ends in a drag rather than a tap, because then nothing consumes it. Verified on device: a
long press now leaves the covers wiggling after release.

### Two test-support changes, both deliberate

`enterEditMode` no longer taps a pencil that does not exist. It hand-rolls the press rather than using
`tester.longPress`, for two reasons worth keeping written down:

- `BookWidget` does not use `GestureDetector.onLongPress`. It runs its own two-stage hold off a `Timer`
  from `onTapDown`, and `kBookStageTwoDelay` is 700ms, so a 500ms `longPress` releases first and reads as
  a plain tap — which pushes the book's details page.
- It needs **two** pumps. `onTapDown` does not fire on pointer-down; the tap recogniser holds it until it
  wins the arena or its ~100ms deadline passes, and only then is the 700ms timer scheduled. A single
  750ms pump advances past the deadline in one step, so the timer lands at 800ms and never fires.

`enterVisit` is new, and goes through the Friends sheet because there is no other way in — your avatar is
not in the rail, and the rail only exists once you are already visiting.

### Also fixed here

A friend's sheet no longer reserves `ShellTabBar.reserve`. A visit hides the bar, so the reservation left
an empty white band under the pile — visible in the device screenshots before the change.

### Known, and left as it is

The pager is still `[your library, ...friends]`, so swiping right off the first friend lands on page 0 and
ends the visit. The design scopes the swipe to friends, which would mean clamping. Left unclamped because
"your library is home" makes arriving home a reasonable outcome of swiping past the edge, and it is a
second way out rather than a wrong one. Revisit if it reads as an accident on device.

---

## Task 6: Fix the 5.8px clearance

- [x] Measure the real bar-to-sheet clearance on a friend screen in a widget test, then fix it — a shorter
      expanded sheet, or the rail participating in layout rather than overlaying.
- [x] Assert a minimum clearance so it cannot regress.
- [x] Settle what the tab bar does during an edit. Task 7 confirmed on device that switching to Card
      mid-edit leaves that sheet expanded while the covers wiggle. Options: hide the bar for an edit
      (an edit is a focused context, and the design already hides the bar for the other one — a visit),
      or give every sheet `isEditMode` so they all spring shut. **Done — both, see Task 4.**
- [x] Consider measuring the bar's height at runtime instead of the constants Task 7 landed.
      **Decided against, and the reason is not effort.** The 21pt inset is the difference between the
      `UITabBar`'s frame and its `_UITabBarPlatterView`, and that platter is a **native subview** — not
      reachable from Flutter at all. Measuring the box at runtime would replace one constant (83) and
      leave the other (the inset) exactly as hardcoded, while adding a provider and a frame of resize on
      first build. Half a guess removed for a visible cost is a worse trade than a documented constant
      with a device check next to it.

This is pre-existing, measures the same in every mockup version including `main`, and Phase 1 is the moment
it gets touched. Do it here rather than discovering it on device.

**Measured, and the drawing's finding is inverted.** `test/library_clearance_test.dart` measures the band
of library left between the bar and the sheet — the library's own viewport, so `RefreshIndicator` is the
handle on it. On a 375×667 phone:

|                      | clearance |
| -------------------- | --------- |
| your own library     | **319pt** |
| a friend's (a visit) | **329pt** |
| a visit at 2× text   | 304pt     |

The mockup measured 38.8px and 5.8px and concluded the friend screen was the tight one. In Flutter the
friend screen is the **roomier** one, and the arithmetic says why: a visit costs the rail's 48pt row but
frees the tab bar's 78pt reservation, so it comes out 30pt ahead. There was nothing to fix.

The reason the mockup's number does not transfer is its idiom, not its geometry: `.rail` and `.bar` are in
flow while `.sheet` is `position: absolute; bottom: 0` at a percentage height, so adding a rail row pushes
the bar down without moving the sheet up and the gap between them absorbs the whole difference. Flutter
puts the rail in the app bar and the library in an `Expanded` between two measured siblings, so the same
pressure lands on the library's viewport, which is 300pt+ deep. **The design record was right to say
"measure it in Flutter" rather than carry the number over.**

What bounds it, and is now pinned: the read pile is a horizontally scrolling row of **fixed** height, so
forty books take exactly as much vertical room as two. If that ever becomes a wrap or a grid, the sheet
grows with the library and every number above stops holding — hence a test asserting the pile's axis and
height, not just the clearance.

**A real bug did fall out of measuring the worst case.** At 2× text on a 375pt phone the read-books sheet
header overflowed its `Row` by 195px: `LibrarySheetTitle` and the filter control were both unflexible, so
at accessibility sizes they simply did not fit. Fixed by giving the title the flex and letting both
ellipsize, in `LibrarySheetTitle`, `FinishedBooksSheet` and `FriendsSheet`. Nothing in the design or the
mockups would have surfaced this; only laying it out at a size nobody had tried did.

---

## Task 7: Tests and verification

- [x] Suite green throughout; Tasks 1 and 2 must not need a single test edit.
- [x] `flutter analyze lib test` clean of new findings — the 12 pre-existing infos are catalogued and none
      are in files this phase creates.
- [ ] Prove each regression test fails without its fix (`git stash push <files>`, run, pop).
- [x] **Run it on a simulator.** Native platform views inside and over scrolling content are the risk this
      phase carries, and no widget test reaches them: the tab bar's glass, the sheet's drag against the
      pager's horizontal swipe, and the visit transition. `CNSearchBar`'s documented z-order bleed through
      sheets (`autoHideOnModal`) is the precedent — assume the tab bar can do the same until seen otherwise.
      **Done for Task 4 on iOS 26.4 via `argent` + `lib/main_shell_preview.dart`; three bugs found and
      fixed, written up under Task 4.** The z-order bleed did not materialise. Re-run after Task 5, which
      adds the transition this bullet is most worried about.
- [ ] Update `decided.html` only where the build proves a drawing wrong, and say so in the note rather than
      quietly redrawing.

**How to re-run it.** The simulator has no signed-in session and sign-in is Apple/Google, so verification
goes through a fixture entrypoint:

```sh
flutter build ios --simulator --debug -t lib/main_shell_preview.dart --dart-define-from-file=env.json
xcrun simctl install <udid> build/ios/iphonesimulator/Runner.app
argent run launch-app --udid <udid> --bundleId com.unicorn.bookwormFriends
argent run screenshot --udid <udid> --out .argent-shots/shot.png
```

`argent run native-find-views --className UITabBar --fields windowFrame` is what turned "the bar looks
wrong" into "the bar is 50pt tall and wants 83" — reach for it before adjusting a number by eye.

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
