# Library shell — design record

**Date:** 2026-08-14
**Status:** Decided. **Phase 1 (Shell) complete** — see
`docs/superpowers/plans/2026-08-14-phase-1-shell-plan.md` for what shipped, what it deviated
on and why, and the eight bugs building it surfaced. **Phase 2 (Read view) complete** — see
`docs/superpowers/plans/2026-08-16-phase-2-read-view-plan.md`, which records four more bugs, the
drag-versus-scroll decision, and why `user_library_page.dart` survived. **Phase 3 (Library Card) next.**
**Visual record:** `docs/mockups/library-shell/decided.html` — every screen, UI
element and flow, browsable. Open it from disk; no server needed.

This is the written half of the design: the decisions, why they were made, what
was rejected, what is still open, and the phasing. The HTML page is the drawings.
Nothing here should be duplicated there — when they disagree, this file wins for
reasoning and `decided.html` wins for what a screen looks like.

## Context

A Flighty-inspired reshaping of the app: a floating tab bar, one persistent
library background, a per-tab bottom sheet, and a "Library Card" (도서관 카드)
stats page. It took four rounds of exploration and nine branched versions, eight
of which are superseded (see below) and were folded away once `visit-model` won.

## The axiom, corrected

We borrowed Flighty's persistent background, but **the globe is one shared
space** — your flights and a friend's are drawn on the same Earth, so panning
between them really is one world. **A bookshelf is personal property.** Yours and
jisoo's are two different objects, so swapping the background was substituting
one for the other, which is why "where did Friends go?" and "how do I get back?"
kept biting for four rounds.

Corrected: **your library is home and is always the background; a friend's is
somewhere you visit.** Naming it a visit gives departure and return for free.

Everything below follows from that.

## Settled decisions

### Architecture

A library is always the background; each tab's content lives in one bottom
sheet. Any sheet drags down to its title, revealing the library beneath. The
library is never drawn twice.

### Tab bar

Floating pill — Library, Friends, Card — plus a detached circular search button
that opens Add Book as a modal at 95% height. Real Liquid Glass on iOS 26 via
`cupertino_native_better`, blur fallback elsewhere.

**Hidden during a visit.** A tab bar that is visible but cannot say where you are
is the lie every rejected version had to work around; focused dismissible
contexts drop their chrome, and that makes the way out unambiguous.

### Encasing

Preserved: white surface bar with elevation 4 above, `#F8F9FA` well between,
white sheet with an upward shadow below.

### Bar

"My Library" (new l10n key) with share and profile; a friend's view shows
"jisoo's Library" with Poke instead. Edit and `+` are gone — long-press a book to
edit, search button to add. Edit mode swaps in manage-shelves and Done.

### The sheet sits above the library, on every tab

Library, Friends and Card all behave the same way, and the behaviour is stated as
**what it looks like**: the sheet reads as sliding up _over_ the library, which
stays exactly as it is. Nothing scales — shelves and covers keep their size and
you simply see less of them — and nothing is stranded underneath, so anything
behind the sheet stays reachable.

**How** that is achieved is left to whatever is cheapest to build. Today it falls
out of the sheet reporting its height to a `Column` whose other child is an
`Expanded` library, so the two never overlap at all
(`finished_books_sheet.dart`, pinned by `library_sheet_layout_test.dart`). An
overlay would do just as well provided the library carried a matching bottom
inset. The distinction is invisible on screen, which is the point: implementation
choice, not design.

### Read books

One sheet, two snap positions: collapsed is today's spine pile with the count;
expanded is covers grouped by month. Sheet position replaces any Shelves/Read
toggle.

### Filters

iOS 26 capsules when expanded, glass popover select when collapsed. Month-level
filtering dropped — the grid is already grouped by month.

### Library Card

Name: **Library Card** (도서관 카드), our Passport equivalent. Stats and shareable
artifacts only — **no read-books list**. Read books belong entirely to the
Library tab, which already groups them by month, so a sortable
Date/Title/Author/Rating list here would be a second home for the same data.

### Friends

Sheet titled "Friends" with Everyone / Activity capsules and an icon-only Add
Friend (home for `search_user_page`). Everyone lists friends with what they are
reading and their read count; it works on existing data, so Activity can ship
later. The avatar rail appears only inside a visit, and holds friends only — not
you.

### Friend paging

Horizontal swipe pages between friends, as `PageView` does today, scoped to
inside a visit, with the rail as the map showing how many are left in each
direction. **The rail and the swipe are a matched pair** — the rail is the map,
the swipe is the movement, and neither works without the other.

### Praise is one emoji, not text

"Praise" (칭찬하기) writes one emoji to `book_compliments`, chosen from
`AwesomeEmojiPicker` — any of ~3,500, not a curated set. Still exactly one emoji:
the column caps at 16 code points, which fits the widest emoji that exists and
refuses prose. It is the only **persisted** social object in the app —
`poke_user()` fires a push and writes no row — so praise is what Activity can be
built from today, and it is the payoff of a visit.

Gated to **finished** books: `_ComplimentButton` returns `SizedBox.shrink()`
unless `status == 2`, so praise is for accomplishment, never for what someone is
currently reading.

Detail in `2026-08-14-free-emoji-praise-design.md`.

### Book details, redrawn from the widget

The mockup's details page was wrong and was rebuilt against
`book_details_tab_view.dart`: circular back button; delete and edit **only on
your own book**; a 180px cover standing on a shelf with its label; the status
badge in the top-right corner — the corner the Praise button takes over on a
friend's book, which is why a friend's badge moves down above the shelf label.
Then title, authors (from the search API, since `books` has no author column) and
the reading-period card, shown only when `status >= 1` and a start date exists.
Finally the pinned Book info / Notes tabs. There is no Status/Shelf/Rating list
and no inline memo — both were invented.

## Where it landed

### ★ `visit-model` answers both open decisions

Friends stays a real destination — a hub of people and what each is reading, not
a picker you summon. Tapping someone enters a focused **visit**: the tab bar
steps aside because it cannot honestly report a position there, the rail becomes
the visit's own chrome, and the **glass ×** at its head ends the visit.

"How do you get back?" is answered rather than dodged, because a visit is a thing
that _has_ an end. "What does tapping a friend do?" is reframed: mechanically
close to a pushed page, but for the opposite reason — not a page that
unfortunately covers the tab bar, a focused context that _should_.

### ✓ Received praise is visible again — `e67ca75`

`_ComplimentButton` **and** the received-emoji block both sat inside
`if (!isSelf)`, so the person praised never saw it anywhere in the app; the push
notification was the only trace. Hiding the _button_ is right — you should not
praise yourself — but hiding the _praise_ defeated the point of storing it.

The fix also retired `ComplimentBlock` from being dead code: it was never
referenced, and its `List<dynamic>` fallback would have rendered
`Instance of 'BookCompliment'` if it had been. Pinned by
`book_details_compliments_test.dart`.

### ✓ One praise per person per book — applied to production 2026-08-15

`UNIQUE (book_id, from_user_id)`, plus reads widened to match the book's own
visibility so a count means the same thing to every viewer. A tap is a **toggle**:
the same emoji withdraws, a different one replaces, and the Praise pill wears
your own emoji so you can tell which is yours among chips that do not name their
senders.

Verified against the real database: all 39 rows were already unique so nothing
was deleted, a third party went from seeing 0 of a book's praises to 2, the old
bare `insert` now fails with a duplicate-key error, and the upsert swaps the
emoji in place without adding a row. Pinned by `praise_toggle_test.dart`.

### ✓ The palette lost to the data

28 of the 39 live praises were emoji the fixed 16 never offered — 🦄 🐲 🧸 🛸 ☘️
☃️ — dating from 2022–2024 and carried over from the archived project. Their
shape gives away the source: ✌🏻 carries a skin-tone modifier and ☃️ a variation
selector, which is system-keyboard output. The curated set was never what people
used.

It is now `AwesomeEmojiPicker` — search, Recents, categories, skin tones — with
the sixteen demoted to seeding an empty Recents run so a first-timer is not
dropped into 3,500 emoji with no shortlist. Both emoji columns widened from
`varchar(6)` to `text` first: 290 of the 3,544 emoji exceed six code points, and
Postgres rejects rather than truncates.

### Praise is the peak, but it is buried

The real path is four taps and runs through **book details**, where
`_ComplimentButton` actually lives: cover → details → Praise → emoji. So
**nothing on any shelf hints that praise exists**, in either direction: you
cannot see that a friend's book can be praised, and you cannot see that yours has
been. Drawn in `decided.html` as a labelled proposal ("Proposed — not built")
rather than folded in as fact, because surfacing it costs a new shelf-level count
query.

## Superseded explorations

Eight branched versions argued the shell out. They were deleted from
`decided.html` when `visit-model` was folded into `main` — each stored only a
_patch over the old root_, so against the decided design they would render
hybrids nobody proposed. What they taught is here; the drawings are in git
history (before `9820701`).

### What tapping a friend does

"Sheet grows" was ruled out early: it recreates the library duplication and nests
paging inside a draggable sheet. That left a **background swap with the rail
dropping in** versus a **pushed page**. Statically the two differ only by the tab
bar; the real question was what happens to the persistent world.

Worth knowing for Phase 1: `home_page.dart` already nests horizontal
drag-reorder inside the friend `PageView` and already gates paging physics by
mode, so the swap's cost is choreography, not gesture arbitration.

### Getting back out of a friend

Four explicit controls were drawn — a bar chevron, a glass × at the head of the
rail, your own avatar there instead, and a named "‹ Everyone" in the sheet
header. Drawing them is what killed them:

- The glass × was cheapest and the only one whose semantics matched a selection
  rather than a navigation, but it would have been the third glass surface on one
  screen.
- The sheet-header back label **breaks its own layout**: collapsed, back label +
  title + count + filter do not fit 170px, the title wraps and the spine pile is
  pushed under the tab bar. The name it exists to show is exactly what does not
  fit.
- **The permanent rail is self-undermining.** Drawn on all nine states it would
  have to appear on, it showed that a sheet measured from the bottom is not
  pushed down by a rail above it: clearance under the bar falls from 38.8px to
  5.8px. The fixes are a shorter expanded sheet or hiding the rail when the sheet
  is up — and hiding it makes the rail conditional again, which is the premise
  collapsing.

The visit model made all four moot: the × lives _inside_ the visit, which is the
one context where a dismissal is unambiguous.

### Is the tab bar a control or a readout?

Two versions swiped the background and the tab highlight together, making your
own library the leftmost page rather than a different mode. That dissolves the
way-back question — the way home is the Library tab, already on screen and
already named — and turns the friends list into a modal picker you summon.

Rejected because it costs a tab bar that changes selection without being tapped,
and one of three tabs behaving as a picker rather than a destination. The
rail-less sibling was **judged worst on UX, and rightly**: deleting the map to
fix a 33px layout collision optimised pixel cost over comprehension. The
collision is a geometry bug, not an argument against the affordance.

## Still open

- **Praise discoverability.** Only reachable from a detail page. The shelf hint
  that would advertise it needs a shelf-level count query; until then praise is
  something you only meet if you already know it exists.
- **Aggregating praise.** The vocabulary is unbounded now, so counts are safe but
  "top praise" has a long tail to handle.
- **Bar-to-sheet clearance on friend screens: 5.8px.** Measures the same in every
  version, `main` included, so it is pre-existing rather than caused by the visit
  model. Phase 1 lays out that screen, so that is the moment to fix it.
- **Praise policy gaps** (API-only, unreachable from the UI): you can praise your
  own book, and a stranger's book with no follow. Both are INSERT-policy
  tightenings.

## Phasing

Each phase gets its own implementation plan in `docs/superpowers/plans/` when it
starts.

### 1 — Shell

Tab bar, one-world/one-sheet architecture, chrome removal, per-tab sheets,
drag-down gesture, and friend selection as a visit. **No new data.** Includes
splitting `home_page.dart`, which is 1,297 lines and holds eleven classes. Also
the moment to fix the 5.8px clearance.

### 2 — Read view

Month grouping, cover grid as the expanded state, capsule date filter. **No new
data.**

### 3 — Library Card

Stat providers, card UI, share. **Needs `books.page_count` and `books.authors`
plus a backfill** — both are already returned by every search provider and
currently discarded, so capturing them early is cheap and unblocks this phase.

### 4 — Friends activity

Feed query for the Activity tab. Optional `poke_events` table if pokes should
appear in it, since `poke_user()` writes no row today.
