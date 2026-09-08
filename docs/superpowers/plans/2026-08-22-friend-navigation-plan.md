# Friend navigation: the Friends sheet as the one switcher — Implementation Plan

> **Status: implemented** (2026-08-22) — all seven tasks landed in one pass, then two rounds of review
> changes: the sheet's `‹ Friends` control was replaced by a Friends-tab reselect, and "every state carries
> the sheet" was made structural after an empty friend's library was reported with no sheet and therefore a
> dead tab bar. `flutter test`: 705 passing.
> Five failures remain in `library_read_books_test.dart` and are **pre-existing and unrelated**; see
> _What the implementation changed about this plan_ at the end for the diagnosis. Written against two
> reported defects in the shell's horizontal pager and the drawings in
> `docs/mockups/friend-paging/index.html`, version **`switcher-drilldown`**.
>
> **This plan deletes two things the Phase 1 shell decided on purpose**: the `FriendRail` and the lateral
> swipe between friends. `docs/mockups/library-shell/decided.html` argued both in, and its reasoning is
> quoted below where this plan overrides it. Nothing here is a correction of a mistake in that design — it
> is a different answer to the same question, taken with two bug reports and a measured cost sheet that
> the original round did not have.

> **For agentic workers:** implement task-by-task, in order. The ordering is load-bearing: **the deletion
> is Task 6**, so the app compiles, runs and demos at every earlier point, with the rail still present.
> Steps use checkbox (`- [ ]`) syntax. Read `.agents/skills/flutter-tester/SKILL.md` before writing any
> test — this project has established Given-When-Then and layer-isolation conventions. There is no
> migration and no schema change in this plan.

> **There is no installed base.** [Corrected 2026-08-30: the listing is **live**, not pulled —
> `id1643321634`, v1.0.6, last updated 2022-09-24, 2 ratings. The conclusion is unaffected: a
> two-year-stale binary with 2 ratings is a dormant app, which is all this paragraph relies on.]
> Read the 153 profiles and **37 follow rows** as a dormant migrated corpus, not
> as users. This matters twice over, and in opposite directions. It means no client in the wild breaks.
> It also means **the follow counts are not evidence about the feature** — "113 of 136 users following
> nobody" describes a dormant app, not a rejected idea, and any argument of the form "the rail is chrome
> for an empty set" is void. The relaunch should be planned for a real follow graph, which is what
> actually argues for a named, scrollable list over a strip of anonymous 40pt circles.

**Drawings:** `docs/mockups/friend-paging/index.html`, version `switcher-drilldown`. Every screen and flow
named below exists there. Verify the page with `node docs/mockups/friend-paging/verify.js` after any change.
**Superseded design:** `docs/mockups/library-shell/decided.html` — `switch-friend`, `return-to-friends`,
`el-rail`. Those three are what this plan replaces; leave them in place as the record.
**Shell design:** `docs/superpowers/specs/2026-08-14-library-shell-design.md`

**Goal:** one way to change whose library you are looking at, one way to leave, and no gesture that moves
you somewhere you did not ask to go.

---

## The audit, done first

Every figure is read out of the code or out of an existing test, not estimated.

| Measure                                                     | Value                                                                                                 |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Pager physics gate                                          | `mode == LibraryMode.library` **only** — nothing about the tab or the visit                           |
| Pager page count                                            | `following.length + 1` — your library is index 0, on the same axis as every friend                    |
| `onPageChanged`                                             | fires per **page crossed**, not on settle — a position report, not an arrival report                  |
| `_syncPageToFriend`                                         | `animateToPage(target, 250ms, easeInOut)` whatever the distance                                       |
| Queries wasted by a tap on friend _k_                       | **2(k−1)** — two `autoDispose.family` reads per intermediate page, mounted then dropped               |
| `ScrollPhysics.shouldAcceptUserOffset`                      | `pixels != 0 \|\| min != max`, fed to `setCanDrag` by `applyNewDimensions`                            |
| Surfaces that therefore hand a horizontal drag to the pager | a shelf whose books fit, `ReadPile` when it does not overflow, **the whole Card tab**                 |
| `_FriendLibraryPage` loading state                          | `.when(loading: CircularProgressIndicator.adaptive())` — blanks the pane                              |
| `bottomReserve` on a friend's sheet                         | **0** — a visit hides the tab bar today, so it reserves nothing                                       |
| `FinishedBooksSheet` band                                   | `available = maxExtent − bottomReserve − viewPadding.bottom`                                          |
| Tab bar reserve                                             | **78pt** on a 375×667 phone (`library_clearance_test.dart`)                                           |
| `_railRow` reserved by `_barExtent`                         | **56pt** (the `FriendRail` widget itself is 48pt)                                                     |
| Library band, own vs visit, measured                        | **319pt** own, **329pt** visit; **304pt** at 2× text (`library_clearance_test.dart`)                  |
| `AvatarCircle.diameter` default                             | **40** — so `_FriendRow` is **56pt** (40 + 8 vertical padding each side)                              |
| `sheetMinHeightFraction` / `sheetMidExtent`                 | **0.2** of screen / **0.65** of the band                                                              |
| Friends sheet `collapsedBody`                               | **none**, declined on the record: "a strip of avatars with no names … was worse than the list itself" |
| Self row in the Friends list                                | **does not exist** — `ListView.builder(itemCount: following.length)`                                  |
| `LibrarySheet.expandedHeader`                               | varies a header by **detent**, not by level. No sheet draws a back affordance at all                  |
| `_tabs`                                                     | `LibraryTab.values` → a **native** `CNTabBar` with three fixed items                                  |
| `shellBarVisibleProvider`                                   | returns false when `selectedFriend != null`                                                           |
| Only shell-level route to follower counts                   | `FriendRail`'s long-press dialog — dies with the rail unless migrated                                 |
| Unfollow, elsewhere                                         | `user_library_page.dart`, reached from search and the settings follow lists — survives                |
| Test files referencing `FriendRail`                         | `shell_tab_bar_test.dart`, `library_back_navigation_test.dart`                                        |
| `enterVisit` in the harness                                 | already taps a **Friends row**, not a rail avatar — only its doc comment is stale                     |

### What the audit changes about the plan

Two things, both of which reordered it:

1. **The caching fix is a prerequisite, not a follow-up.** Once the sheet is the switcher, a switch is a
   content swap on a pane whose providers are `autoDispose.family` and whose loading state is a blank.
   Shipping the switcher without Task 1 makes a blank pane the primary experience rather than an edge case.
   Task 1 also stands on its own: it reduces the harm of the pager's sweep on `main` today.

2. **`switcher-drilldown` is the cheaper branch, not the dearer one.** An earlier reading of this had it
   backwards. Because all three tabs keep meaning _yours_, this branch needs **no** self row in the
   Friends list, **no** `collapsedBody` work, and **no** friend-facing Library Card — three additions the
   `sheet-switcher` alternative required. What it adds instead is one enum provider and one optional
   parameter.

---

## The design, in one rule

> **All three tabs always mean yours. Everything about a friend lives at the second level of the Friends tab.**

- **Library** — your books read. Always.
- **Card** — your card. Always.
- **Friends** — your list at level 1; the friend you tapped at level 2. **Tapping Friends again comes back
  up to the list**, which is the friend switcher: the list reappears over her library and the next friend is
  one tap away. The sheet carries no back control of its own — see Task 2, which built one and cut it.
- The **background** library is whoever `selectedFriendProvider` names.
- Tapping **Library** or **Card** therefore ends a visit, because those tabs are about you. So does the
  **`✕`** that moves out of the rail and into the library bar's leading slot.
- `‹ Friends` — **cut.** A second tap on the Friends tab goes _up a level_ without ending the visit.

**The invariant this produces, which Task 7 asserts:** `selectedFriend != null` ⟹ the Friends tab is
selected. It is the whole design in one line, and it means `_LibraryBar`'s friend state and the Friends
tab are locked together.

### Where this overrides `decided.html`, and why

| That design said                                                                                                      | This plan                                                                                                                                                                            |
| --------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| "the rail is the map, the swipe is the movement, and neither works without the other"                                 | Agreed — so both go together. Keeping the swipe without the rail leaves a gesture with no affordance, which is defect 1's complaint.                                                 |
| The tab bar hides in a visit, because one "that cannot say where you are" was what four rejected rounds worked around | Answered rather than reinterpreted: here no tab ever changes meaning, so there is no reading under which it misreports. This is the branch that earns the bar back.                  |
| The rail's `×` is unambiguous because "a visit is the one context where a dismissal has an obvious meaning"           | Kept, verbatim, including the glyph — only the row it sits in changes. `_LibraryBar` "keeps actions out of the slot where users expect Cancel", which reserves that slot _for_ this. |
| A friend's read view gains room because the visit frees the tab bar's band                                            | Given up. Net ~30pt worse (48pt rail out, 78pt reserve back in). Task 5 owns the number; it is the one place this is a downgrade.                                                    |

---

## Task 1 — A library that never blanks, and friends that stay warm

Independent of everything below, and worth landing on its own.

- [x] `ref.keepAlive()` in `userLibraryProvider` and `userFinishedBooksProvider`
      (`user_provider.dart` and `library_provider.dart` respectively — they live in different files). At a
      dormant mean of ~1.6 follows the memory cost is nil, and a second
      visit becomes free. Note in the doc comment _why_ `autoDispose` was wrong here: the family is keyed
      by user id and revisiting the same friend is the common case.
- [x] Replace the blanking loading state with a `valueOrNull` read plus a quiet in-flight affordance, so
      the outgoing shelves stay on screen while the incoming ones load. **Not** a spinner over a blank
      pane. Landed as `_HomePageState._onScreen` (a held shelves/reads _pair_), `LibraryPane.stale` (fades
      the shelves, not the sheet over them) and `_LoadingChip` ("loading minho…"). It went straight into
      the single pane rather than into `_FriendLibraryPage` first, since Task 6 deletes that widget — the
      behaviour is the plan's, the location is one step later.
- [x] Verified by test rather than by eye, since the pane it belongs to did not exist yet when this task
      was written: `friend_navigation_test.dart` holds a friend's library in flight with a `Completer` and
      asserts the outgoing shelves and the named chip are both on screen.

**Drawings:** `switch-cold` (today) and `switch-warm` (the target) on the mockup page.

## Task 2 — ~~`FinishedBooksSheet.leading`~~ (cut, after being built)

This task shipped and was then **reverted on review**, and the reason is worth keeping rather than the
code: a `‹ Friends` control in the sheet's header is the wrong answer to "how do you get back up a level".

- [x] Built as specified: one optional `Widget? leading`, drawn ahead of the title in `header` and
      `expandedHeader`, plus a shared `SheetBackControl` in `library_sheet.dart`.
- [x] **Removed.** It could not sit beside the year popover — three controls in one 375pt row is what
      `library_clearance_test.dart` catches overflowing at 2× text — so it displaced the popover and made
      a friend's read view a different shape from your own, for a control the tab bar can supply for free.
      Both the parameter and `SheetBackControl` are gone; `FinishedBooksSheet` is byte-for-byte what it was.
- The way back up is **Task 5's tab reselect** instead. Net cost of the level, after this reversal: one
  provider and no chrome at all.

## Task 3 — The Friends tab's second level

- [x] New `friendsSheetLevelProvider` in `library_shell_provider.dart`:
      `enum FriendsSheetLevel { list, friend }`, `StateProvider.autoDispose`, default `list`.
      It cannot be derived from `selectedFriendProvider`: backing up to the list keeps her library as the
      background, so whose-library and which-level are two independent bits.
- [x] `_sheetForTab(LibraryTab.friends)` returns the `FriendsSheet` at `list`, or a
      `FinishedBooksSheet(books: hers, filterYear: friendReadsFilterYearProvider, leading: ‹ Friends)` at
      `friend`.
- [x] `FriendsSheet.onSelectFriend` sets `selectedFriendProvider` **and** the level to `friend`.
- [x] The level goes back to `list` on a **tap of the Friends tab**, including when Friends is already the
      selected tab, and `selectedFriendProvider` is left alone. See Task 5 — it lives in
      `ShellChrome._selectTab` with the rest of the tab semantics, not in the sheet.
- [x] **Verified, not assumed:** the level swap changes `contentId` from `FriendsSheet` to
      `FinishedBooksSheet`, and `LibrarySheet` springs the height between the list's 65% and the pile.
      Nothing was built for it. `library_clearance_test.dart` pins the direction of that travel (the band
      _grows_ on the way down a level), which is what would break if the spring were lost.

**Drawings:** `visit-rest`, `visit-reads`, flow `f-switch` steps 2–3.

## Task 4 — The visit's exit moves into the bar

- [x] `_LibraryBar` gains a leading `AdaptiveIconButton(symbol: 'xmark', icon: Icons.close, diameter: 36,
symbolSize: 14, iconSize: 18, semanticLabel: l10n.endVisit)` when `!isSelf` — the same widget
      `FriendRail` built, relocated, so the glyph a reader already knows does not change.
- [x] It clears `selectedFriendProvider` **and** resets `friendsSheetLevelProvider` to `list`.
- [x] Update `_LibraryBar`'s doc: the leading slot is now occupied in one of the three states, and the
      reason is that a dismissal is the thing that slot was being kept free for. Note the doc also had to
      give up its "the title never moves between them" claim, which is now true of two states out of three.

## Task 5 — The tab bar returns to a visit

- [x] Drop the `if (ref.watch(selectedFriendProvider) != null) return false;` early return from
      `shellBarVisibleProvider`. Simplify that file's ordering comment accordingly — it now pins one
      `autoDispose` provider alive rather than two, so the constraint gets _looser_, and the comment
      should say so rather than being left describing two reads.
- [x] `ShellChrome._selectTab`: selecting anything other than `LibraryTab.friends` clears
      `selectedFriendProvider` and resets the level. This is what makes Library and Card into exits, and
      it is the only place that behaviour lives.
- [x] **The friend switcher, which this task acquired when Task 2 was cut:** a tap on `LibraryTab.friends`
      always resets the level to `list`, _including a reselect of the already-selected tab_. Inside a visit
      at level 2 that brings the list back over her library without ending anything, so the next friend is
      one further tap away. Verified in the package rather than assumed: `CNTabBar` forwards every native
      `valueChanged` — `tab_bar.dart` comments "Always fire onTap, even for reselects (Issue #13 fix)" — and
      the Flutter fallback's `_TabSegment`s call `onChanged` unconditionally. **This is a dependency on a
      third-party promise**, and it is written down at the call site because a package bump that silences
      reselects would silently remove the only way back up a level.
- [x] Pass `ShellTabBar.geometryOf(context).reserve` as `bottomReserve` to the friend read sheet, exactly
      as your own sheets already get it. Free, as it turns out: one `_sheetForTab` computes the reserve
      once and every tab and level gets the same number.
- [x] Do **not** touch `_tabs` or the `CNTabBarItem` list. Three fixed items, natively configured; no tab
      is ever inapplicable under this design, which is the point.

**The number to accept, as measured rather than as predicted.** `library_clearance_test.dart` now records
**320pt on your own library and 320pt in a visit** on a 375×667 phone, against 319/329 before, and 299pt at
2× text. The visit case lost the ~30pt this task predicted (48pt of rail row back, 78pt of reserve gone)
and nothing else: with the back control cut, a friend's read view carries no chrome yours does not, so the
test asserts the two bands are _equal_ — which is the tripwire for anything being added to one and not the
other. (The reverted `‹ Friends` draft cost a further 16pt, and that measurement is what condemned it.)

## Task 6 — Delete the pager and the rail

Last, so everything above is already working.

- [x] `home_page.dart`: remove `_pageController`, `_syncPageToFriend`, the `ref.listen<Profile?>`,
      `PageView.builder`, and `_FriendLibraryPage`. One `LibraryPane` remains, whose shelves and finished
      books come from your providers or from `userLibraryProvider(selectedFriend.id)`.
- [x] Remove the rail row from `_bar` and `_railRow` from `_barExtent`, which becomes
      `viewPadding.top + _libraryBarRow`. `_barExtent`'s `isSelf` parameter went with it — the bar is one
      row on every screen now, so a visit can no longer shove the shelves down mid-animation.
- [x] **Migrated `_showFriendInfoDialog`** out of `friend_rail.dart` before deleting the file. It landed in
      a new `lib/ui/widgets/dialogs/friend_info_dialog.dart` as `showFriendInfoDialog`, wired to
      `_FriendRow`'s long press **and** to the avatar inside it — `AvatarCircle` carries its own recogniser
      and would otherwise swallow the gesture on the very glyph that used to carry it. Follower counts,
      Poke and Unfollow all came across.
- [x] Delete `friend_rail.dart`.
- [x] Rewrite the `friends_sheet.dart` comment that begins "**No `collapsedBody`, deliberately.**" Its
      reasoning is still correct and still worth keeping — it now stands on the 1.6-row measurement rather
      than on a rail that no longer exists to be compared to.
- [x] **One thing deleting the pager exposed**, fixed in passing because one pane now draws both readers:
      `LibraryPane`'s empty state said "Your library is empty…" plus an add-a-book hint over _anybody's_
      shelves. It takes `isSelf` now and uses the `libraryEmptyOther` string that already existed and had
      no reader.

## Task 7 — Tests

All of the new ones live in **`test/friend_navigation_test.dart`** (11 tests), which is the regression
guard for the deletion as a whole.

- [x] `test/support/home_page_harness.dart` — `enterVisit` needed no code change; its doc is corrected and
      now also records that it leaves the sheet on level 2, so `find.text(username)` will not match after
      it. Added `backToFriendsList`, `endVisit`, and `shellContainer` — the last because the design is a
      claim about how two providers move together, and the UI only shows their consequences.
- [x] `test/shell_tab_bar_test.dart` — retargeted off `FriendRail`; asserts the bar is **visible** in a
      visit and sitting on Friends, and that the sheet drilled in.
- [x] `test/library_back_navigation_test.dart` — retargeted off `FriendRail`. `✕` ends the visit and resets
      the level; a tap on the **Friends tab** goes up a level **without** ending it; system back ends it via
      `PopScope`.
- [x] `test/library_clearance_test.dart` — a visit now settles at 320pt, not 329pt, and the test asserts it
      is _equal_ to your own library's band. Added the assertion the file has never had: the band left under
      the **Friends** sheet, at both levels, including that the band _grows_ on the way down a level.
- [x] **New:** a horizontal drag on the Library tab changes neither `selectedFriendProvider` nor the
      shelves — and the same on the Card tab, which was the worst of the three leaks.
- [x] **New:** the invariant — `selectedFriend != null` ⇒ `libraryTabProvider == LibraryTab.friends`.
- [x] **New:** tapping Library or Card during a visit clears `selectedFriendProvider` (one test each).
- [x] **New:** a shelf row that _does_ overflow still scrolls horizontally.
- [x] **New:** switching friends does not blank the pane, held with a `Completer` so the in-flight frame is
      actually observed rather than raced past.
- [x] **New:** a long press on a friend's cover does not open edit mode — the pane draws her shelves now,
      where before it was a different widget that ignored the gesture.
- [x] **New:** a reselect of the lit Friends tab brings the list back and leaves the visit running — from
      the collapsed pile _and_ from the expanded grid, since the sheet is wherever the reader last dragged
      it. This is the switcher, so it is asserted from both the tab-bar side
      (`shell_tab_bar_test.dart`) and the state side (`library_back_navigation_test.dart`).
- [x] **New:** a friend's read view has the year popover in its collapsed header, asserted by type rather
      than by label. It is the regression guard for the reverted `leading` control, which could only fit by
      taking that control's place.
- [x] **New:** every state carries the sheet — the empty library (three tests, including that the art
      clears the sheet's top edge), the cold start (skeleton + sheet + a tab tap that still works), and a
      failed query (sheet present, Retry re-reads and recovers). `pumpHome` gained `settle: false` for the
      loading case, because `LoadingLibrary` shimmers on a repeating animation and `pumpAndSettle` never
      returns while it is up — the same trap `enterEditMode` documents for `Wiggle`.
- [x] Pinned the existing filter split deliberately: `readsFilterYearProvider` is yours and
      `friendReadsFilterYearProvider` is shared by every friend, so the year follows you from one friend to
      the next. Pre-existing, out of scope to fix, and now deliberate rather than accidental.

---

## Cut, and why

- **`sheet-switcher`** — the sibling branch, where Library and Card re-scope to the friend. Costs a self
  row in the Friends list, a `collapsedBody` plus `collapsedBodyExtent` for Friends, a friend-facing
  `LibraryCardSheet` with a share suppression flag, and a friend card year provider. Buys one-tap
  switching and a friend's card. Rejected as the dearer branch with the muddier rule, but it is drawn and
  it is the fallback if a tab tap proves an unacceptable way to leave.
- **A friend's Library Card.** Unreachable under this design; Card means yours. If it turns out to matter,
  the friend detail level is the natural home for its figures — additive later, no rework.
- **The cross-fade** on entering a visit, and any new sheet detent. Both drawn, neither needed.
- **Re-keying `friendReadsFilterYearProvider` per friend.** A real question, not this plan's.

## Risks

| Risk                                                                                  | Mitigation                                                                                                                                                                                                                                                                                                          |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Tapping Library or Card ends a visit** — a mis-tap loses your place                 | The single biggest judgement call here, and it cannot be settled in a test. Recovery is two taps. **Not eyeballed before Task 6**, because the whole plan landed in one pass at the user's request — so this is now a shipped behaviour awaiting a device check, with `sheet-switcher` still drawn as the fallback. |
| Two back-ish controls at level 2 — the Friends tab in the bar, `×` in the library bar | Different rows, different scopes (the sheet's level vs the whole visit), which is conventional. Still worth looking at rather than reasoning about.                                                                                                                                                                 |
| **The way back up a level has no affordance** — a reselect is invisible               | The trade taken when `‹ Friends` was cut. It is a learned iOS gesture, and the `×` is always visible as the escape hatch. Worth watching on a device: if nobody finds it, the honest fix is a `collapsedBody` on Friends (`sheet-switcher`'s answer), not a label back in her header.                               |
| A `cupertino_native_better` bump stops reporting tab reselects                        | Would silently remove the only way back up a level. Documented at `ShellChrome._selectTab` with the package's own comment quoted, and asserted twice — though both tests exercise the Flutter fallback, since a native `CNTabBar` cannot be pumped.                                                                 |
| Her expanded month grid nets ~30pt worse                                              | Accepted in Task 5, with the arithmetic written down. `library_clearance_test.dart` pins the floor at >150pt, which holds comfortably.                                                                                                                                                                              |
| The `contentId` swap on the level change springs a height the design did not intend   | Task 3 verifies it explicitly rather than assuming.                                                                                                                                                                                                                                                                 |
| Deleting the pager makes some horizontal drag dead that should not be                 | Task 7 asserts an overflowing shelf row still scrolls.                                                                                                                                                                                                                                                              |

## Open, and deliberately not resolved here

- Whether a tab tap is an acceptable exit at all, or whether Library and Card should be _inert_ during a
  visit — honest, but three dead controls. **Still the one thing a test cannot settle**, and it is now
  shipped rather than hypothetical: it wants five minutes on a device.
- Whether system back should pop the _level_ before it ends the visit. Implemented as this plan specified —
  back ends the visit outright, so back and the bar's `✕` agree — but the level is a real state the reader
  created by tapping a row, and popping it first is the more conventional unwind. Cheap to change: one
  branch in `PopScope.onPopInvokedWithResult`.
- Whether the friend read filter should be keyed per friend now that it is easier to notice. There is a
  test pinning today's shared behaviour, so changing it is a deliberate edit rather than a surprise.
- Whether `user_library_page.dart` should be folded into the shell. It is still needed for users you do
  not follow, reached from search, so it is not redundant — but it is now the only other friend-library
  surface and the duplication is easier to see.

---

## What the implementation changed about this plan

Five things worth reading before trusting any number above.

1. **The second level has no control of its own, and the tab bar carries it.** The plan specified a
   `‹ Friends` control in the sheet header (Task 2) and it was built and then cut on review. Two reasons,
   and the second is the one that matters. It could not coexist with the collapsed year popover — three
   controls in a 375pt row overflows at 2× text — so it displaced her filter and made a friend's read view a
   different shape from your own; and a **reselect of the lit Friends tab** does the same job for free,
   using a gesture iOS already trains. `docs/mockups/friend-paging/index.html` has been redrawn to match:
   `visit-rest`, `visit-reads` and the `f-switch` flow no longer carry a back label, and the flow's third
   step is now "Tap Friends again" with the segment drawn pressed _and_ lit.

2. **The level therefore costs one provider and nothing else.** No parameter, no chrome, no header variant.
   What it does cost is a **dependency on a package promise** — `CNTabBar` must keep reporting reselects —
   which is documented at `ShellChrome._selectTab` because nothing else in the app would notice it breaking.

3. **Three additions outside the plan's list.** `LibraryPane.isSelf` — one pane now draws both readers, so
   the empty state had to stop telling visitors to add a book to somebody else's library
   (`libraryEmptyOther` already existed and had no reader); the held-library machinery Task 1 asked for
   (`_HomePageState._onScreen`, `LibraryPane.stale`, `_LoadingChip`); and the empty-state fix in item 5.
   `SheetBackControl` and the `backToFriends` string were added and then removed with the control they
   served.

4. **A latent bug in `LibraryPane` became a real one, and the fix is now structural.** It returned its
   empty state _before_ the `Stack` that floats the sheet, so a library with no books had no sheet at all.
   That was invisible while a visit hid the tab bar and the sheet was only ever the read view; with the
   sheet as the switcher and the bar on screen throughout, visiting a reader with empty shelves left the
   Friends tab with nothing to open and the bar looking dead — which is how it was reported.

   The empty state is now library _content_, in the slot the shelves occupy. And because that bug had a
   _shape_ — "this state renders something other than the pane, so the sheet goes with it" — the same two
   holes one level up in `home_page.dart` were closed with it: a cold start showed `LoadingLibrary` with no
   sheet (and painted its skeleton over the library bar), and a failed query showed bare error text with no
   sheet, no pull-to-refresh and **no way to retry at all** except backgrounding the app.

   The arrangement is now one widget, `LibraryPaneFrame` (`library_view.dart`): library content below the
   bar, sheet floating over it, bar shadow between. All three states go through it, all three pass
   `_sheetKey` — so the sheet element is re-parented rather than rebuilt when the library lands — and the
   error state gained `_LibraryError` with a Retry that runs the same `_refreshLibrary` the pull-to-refresh
   does. Five tests pin it, and one of them earned its keep immediately: the first `_LibraryError` centred
   itself in the whole pane, which put Retry _underneath_ the collapsed sheet where it could not be tapped
   — the same forgotten `bottomInset` as the empty state, caught by a hit test rather than by reading.

5. **Five test failures are pre-existing, and two of them prove it.** `library_read_books_test.dart` fails
   in five places, two of which pump `UserLibraryPage` — a file this work never touched. The cause is
   elsewhere in the uncommitted working tree: `readsFilterYearProvider` and `friendReadsFilterYearProvider`
   now default to the current year (they defaulted to `0`, all time, at `HEAD`), and that file's fixtures
   build finished books with **no `finishDate`**, so every pile they assert on filters to empty. Verified by
   running the file at `HEAD` in a scratch worktree, where it passes. The same stale-fixture failure sat in
   `shell_tab_bar_test.dart`'s `_readBooks()` and **was** fixed here, because it blocked verifying this
   work; `library_read_books_test.dart` was left alone, because one of its tests ("the pile filter excludes
   them") is _about_ an excluding filter and deciding what it should now assert is that file's own call, not
   this plan's.

---

## The reselect, and what it replaced

Recorded because the tasks above specify a control that no longer exists, and because the drawings were
redrawn rather than left to disagree with the code.

`‹ Friends` in the sheet header was built exactly as Task 2 specified, then cut in favour of **a second tap
on the already-selected Friends tab**. What the reversal bought, measured:

|                            | `‹ Friends` in the header                                       | Friends tab reselect                                   |
| -------------------------- | --------------------------------------------------------------- | ------------------------------------------------------ |
| Her collapsed read header  | back + title + count, **year popover displaced**                | title + count + year popover — identical to yours      |
| Band left behind her sheet | 304pt                                                           | **320pt**, equal to your own library's                 |
| New code                   | one optional param, a shared `SheetBackControl`, an l10n string | **none**                                               |
| Affordance                 | a visible label                                                 | invisible, learned (iOS's "top of this tab")           |
| Depends on                 | nothing                                                         | `CNTabBar` reporting reselects — a third-party promise |

The last two rows are the whole of the case against it, which is why the risk table carries both. If the
gesture proves undiscoverable on a device, the fix is a `collapsedBody` on the Friends sheet
(`sheet-switcher`'s answer, which makes the list reachable _without_ leaving her reads) rather than a label
back in her header — that route was measured, and it costs her the year control.
