# Library shell — design record

**Date:** 2026-08-14
**Status:** Decided. **Phase 1 (Shell) complete** — see
`docs/superpowers/plans/2026-08-14-phase-1-shell-plan.md` for what shipped, what it deviated
on and why, and the eight bugs building it surfaced. **Phase 2 (Read view) complete** — see
`docs/superpowers/plans/2026-08-16-phase-2-read-view-plan.md`, which records four more bugs, the
drag-versus-scroll decision, and why `user_library_page.dart` survived. **Phase 3 (Library Card)
complete** — see `docs/superpowers/plans/2026-08-16-phase-3-library-card-plan.md`, which records
why two of the five drawn stats were cut, and note that **this record's own Phase 3 description
below was half wrong** (corrected in place). **Phase 4 (Friends activity) next.**
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

**The profile is the reader's own avatar**, 32pt inside the band's 44pt target —
the drawing has `ic pf`, a filled circle wearing their initials, the same control
the rail's "me" lead is. It was a `person_outline` glyph until profiles could
carry a photo; now it is `AvatarCircle`, so the one place a reader looks for
themselves shows them what everyone else sees.

**Share arrived with the artifact, not with the bar.** Through Phases 1 and 2 the
slot left of the profile was empty, because the only thing a share sheet could
have offered was a screenshot. Phase 3's Library Card is the artifact, so the
button is now the Card sheet's own — one export path (`shareLibraryCard`), so the
two places cannot hand out different images — and it is absent whenever it would
lie: nothing read, inside a visit, or mid-edit.

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

**A tab switch moves the sheet; it does not cut to it.** Tabs rest at different
heights, so switching is a change of height as well as of contents — and the two are
not treated alike. The contents swap at once, because the incoming tab is what you
asked for and there is nothing to be gained by showing the outgoing one on its way
out. The box travels, with the same spring a drag releases into. It is the same sheet
throughout, not a new one appearing at a new size, and that is structural rather than
apparent: all three tabs hand one `LibrarySheet` between them, which is what gives the
motion something to start from. Where the incoming tab's collapsed height is taller
than the height being left — Friends can rest below the read view's pile — the sheet
slides up from the bottom edge instead, because a sheet is never shorter than its own
header.

**A swipe inside a sheet belongs to the sheet until there is no more sheet to open.**
From the collapsed position, a swipe up on the list opens the sheet one detent; a second
reaches the cap; only a third scrolls the list. Going the other way, a downward drag
that runs the list out of offset carries on into the sheet rather than stopping dead, so
the sheet can always be put away from wherever the finger already is. This is Flighty's
Passport sheet and iOS's own, and it was arrived at the wrong way round first: the list
scrolled at every position, which meant the shortest viewport the sheet has — a fifth of
the screen — was also the one you were expected to read a whole list through, and it
snapped back to the top on any touch that moved the sheet at all.

The consequence worth stating is that **the collapsed position is a preview, not a
reading position**. It shows the top of the list cut off at the card's edge, and the way
to see the rest of it is to open the sheet. That is why no tab tries to fit its content
into the collapsed height.

### Read books

One sheet, three snap positions: collapsed is today's spine pile with the count;
expanded is covers grouped by month, and it takes the whole band. Between them is a
middle position at ~60% of the screen, which is where most people rest — the whole
band is the right ceiling for a year of covers and is also the entire shell gone.
Sheet position replaces any Shelves/Read toggle.

**Where a sheet _opens_ is a separate decision from what positions it has**, and it
is decided per tab by what that tab has to rest on. The read view opens collapsed
because its collapsed state is a real thing to look at — the pile. The Card opens at
the middle position because its collapsed state is a title and nothing else, so
launching there would show none of the card; see Library Card below. Friends opens at
the middle position too, and for the same reason: it has no separate collapsed state,
so the collapsed height is its list with most of it cut off — a preview of the tab
rather than the tab.

### Filters

Button-like capsules when expanded, glass popover select when collapsed.
Month-level filtering dropped — the grid is already grouped by month.

The expanded row is **not a `CNSegmentedControl`**, which it was at first and which
was the wrong shape: the native control spreads its segments across the full width
inside a grey track, so the row read as a toolbar with the years given as much
weight as "All time". The drawing — `.caps` in `decided.html`, taken from Flighty's
Passport — is a short row of pills hugging their labels, flush left, unselected
ones with no fill at all.

So **Flutter lays the row out and draws every label; the platform supplies the
material**. The selected capsule stacks a native `CNButton` styled
`UIButton.Configuration.glass()` behind the label, empty of content and inert, so
it is the pill's material and nothing more; the painted pill stands in elsewhere.

The division of labour is not fussiness — both halves were tried the other way
round and both failed:

- **A `CNButton` per option, label and all** (`.glass()` selected, `.plain()`
  otherwise) put the _text_ in the native view, and selecting a year restyled a
  live button. `setStyle` swaps the whole `UIButton.Configuration`, which restores
  the title as a plain string and drops its attributed font, and `setLabelStyle`
  re-applies 13pt several awaited channel hops later. For about half a second the
  label rendered at the system's 17pt in the theme's tint, wrapped onto two lines
  inside a view sized for 13pt.
- **`LiquidGlassContainer`** fixed that by leaving the text to Flutter, but it
  renders a _bare_ `Capsule().glassEffect(.regular)`. Glass refracts what is behind
  it, and behind it is an opaque sheet the platform view is composited over, so the
  pill came out flat — no rim, no shadow. (`CNGlassEffect.prominent` would not have
  helped; the plugin pins `Glass.regular` either way.) A button _configuration_
  carries its own material, rim and shadow, which is why the glass had to come from
  one.

Because the glass button only exists while its option is selected, its style is
fixed for its whole life and the restyle path never runs — a selection change
disposes one platform view and creates another. The cost is a single frame in which
the newly selected label has no pill yet, measured at ~33ms on an iOS 26.4
simulator; the label itself never flickers, because Flutter owns it. Laying the row
out natively via `CNGlassButtonGroup` was rejected too: it puts the row in one
SwiftUI `HStack` that centres itself in the width it is given and sizes on a
44pt-per-button estimate, which clips "All time". Selection haptics are asked for
explicitly, since glass is a material rather than a behaviour.

**Pressing is felt on both halves**, which is most of what separates a glass button
from a picture of one. The glass button stays interactive rather than being wrapped
in an `IgnorePointer`: `CNButton` watches raw pointers and pushes `isHighlighted`
to UIKit, so the selected capsule brightens and its halo pulls in under the finger.
An unselected capsule has no platform view to do that, so it **shrinks** under the
finger, as Flighty's tab pills do. The scale is not applied over the native pill —
transforming a platform view in hybrid composition is unreliable, and it answers a
press on its own. Letting the button see pointers also puts its tap recognizer in
the gesture arena, where it usually beats the row's, so it carries the same
callback: whichever wins, the year is reported once.

**One label weight throughout**, selected or not. The pill and the label's colour
carry the selection between them; `decided.html` originally drew the chosen label at
800 against 700, which reads as two type sizes in one row. The drawing is corrected
rather than the code.

### Library Card

Name: **Library Card** (도서관 카드), our Passport equivalent. Stats and shareable
artifacts only — **no read-books list**. Read books belong entirely to the
Library tab, which already groups them by month, so a sortable
Date/Title/Author/Rating list here would be a second home for the same data.

**What shipped, after the data was counted.** Three figures, not five: books read
(the hero), pace, and most-read author. Pages and rating are cut for the reasons in
Phasing below. The card is thinner than the drawing because **the readers are
thinner than the drawing assumed** — the median reader here has finished two books,
57% of finished books were logged same-day and so contribute no reading span, and 40
of the 53 readers with author data have a "top author" who wrote exactly one of their
books. So the governing rule is that **every tile is omitted rather than
zero-filled**, and a tile left alone in its row takes the full width. A card with one
true figure beats a card with four hollow ones.

The share renders the card **off-screen as a separate, pure-Flutter widget tree**
rather than screenshotting the sheet, for two reasons either of which would do. The
sheet is not the artifact — grab handle, share button, capsules, scroll offset,
phone width — while the export is pinned. And `RepaintBoundary.toImage` cannot
capture platform views: the year capsules put a native glass `CNButton` behind the
selected label on iOS 26, so a screenshot would arrive with a hole in it, and only
on a device.

**The sheet rests at the middle position, not at either end.** Both ends were built
first and both were wrong from opposite sides: expanded is the whole band, so the tab
opened onto a screen of mostly empty white with no cover left to long-press and no way
to start an edit; collapsed is `card-down`, a title and nothing else, so the Card tab
opened showing none of the card. `card-down` is what the grab handle gets you — the
drawing's "any sheet collapses to its title" still holds — it is just not where the tab
opens. What makes this the Card's answer and not the read view's is that the Card has
no collapsed body: a resting position needs something to look at there.

### Friends

Sheet titled "Friends" with Everyone / Activity capsules and an icon-only Add
Friend (home for `search_user_page`). Everyone lists friends with what they are
reading and their read count; it works on existing data, so Activity can ship
later. The avatar rail appears only inside a visit, and holds friends only — not
you.

**Everyone shipped in Phase 4a.** The row is name, what they are part-way through,
a colour swatch for it, and their read count in brand green — from **one** query
for the whole list (`friendsReadingProvider`), not one per friend, which is why it
could not ship in Phase 1. The chevron is gone; the count sits where it was.

**Activity is deferred, and the reason is data rather than effort.** Measured on the
live database: **zero** start/finish events in the last 90 days for every user, the
most recent finished book 884 days old, the most recent praise 939 days old, and 113
of 136 users following nobody at all — so a feed of "what just happened" would ship
empty and stay empty until after release. Two of the four events the drawing shows
also need ratings, which do not exist. See the Phase 4 plan; the capsules land with
the feed.

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
- **The same gap on pokes.** `poke_user()` looks its target up by username and never
  checks that you follow them, so anyone can poke anyone. Phase 4b left this alone
  deliberately — it is a behaviour change, and that migration was about recording —
  but pokes are now written to `poke_events`, so an abusive one at least leaves a
  trace. Worth fixing alongside the praise policies, since it is the same shape of
  problem and the same kind of fix.
- **Nobody can rate a book.** `books.rating` has existed since the initial schema
  and every one of the 624 migrated rows is null, because `BookRating`
  (`lib/ui/widgets/book_rating.dart`) is defined and never instantiated — there is
  no control anywhere that sets one. Phase 3 cut the Rating tile from the Library
  Card over this rather than invent a rating UI to feed one tile. Whether ratings
  should exist at all is a product question (stars vs. five-point vs. thumbs, and
  whether a rating is private); if the answer is yes, the column and the card tile
  are both waiting.
- **Page counts are unobtainable for Korean books**, so anything that wants "pages
  read" is blocked on a data source rather than on code. Kakao has no page field;
  Google Books covered 14 of 40 sampled titles from the real library. A Korean
  bibliographic source (Aladin and Naver Books both expose page counts) would
  unblock the cut hero figure — that is a new provider, not a new column.
- **The Library Card is not shown on a visit.** `userFinishedBooksProvider` exists
  and `libraryCardStats` takes a plain list, so a friend's card would be nearly
  free — but whether your reading stats are yours alone is a privacy decision, not
  a technical one.

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

Stat providers, card UI, share. **Complete** —
`docs/superpowers/plans/2026-08-16-phase-3-library-card-plan.md`.

This entry originally read: _"Needs `books.page_count` and `books.authors` plus a
backfill — both are already returned by every search provider and currently
discarded, so capturing them early is cheap and unblocks this phase."_ **That was
true of `authors` and false of `page_count`,** and the false half was the expensive
one:

- **`books.authors` shipped as described.** Migration applied and backfilled through Kakao, which
  resolved 407 of the 430 distinct ISBNs in the live table — **437 of 472 rows**, and 217 of the 230
  _finished_ books (94.3%), which are the only ones the card counts. Kakao rather than Google Books
  because Google had only 16 of a 40-book sample — for a Korean library that difference is the whole
  result. Net effect: 9 of the 45 readers with a finished book clear the tile's floor of two.
- **`books.page_count` was not added, and the "4,180 pages" stat is cut.** No
  provider can fill it: Kakao has no page field at all, and Google Books answered
  for 14 of 40 sampled titles. A hero figure summed from a third of a shelf
  understates a reader threefold, silently, in the one number on the card a reader
  could check by hand.
- **The Rating tile is also cut.** `books.rating` exists and all 624 migrated rows
  are null, because `BookRating` is defined and never instantiated — there is no
  control anywhere that sets a rating. Rating entry is a book-detail feature with
  its own design questions and was not worth inventing to feed one tile.

What the phase did not need: **any new query.** Phase 2 already made
`finishedBooksProvider` fetch the whole finished set, so every shipping figure is a
pure function of a list the app has in memory.

### 4 — Friends activity

**Reordered after a data audit; see
`docs/superpowers/plans/2026-08-17-phase-4-friends-activity-plan.md`.**

- **4a — the Everyone row. Complete.** What each friend is reading and their read
  count, from one batched query. This was the real regression against the drawing:
  Phase 1 shipped the row as name + avatar because building it from the per-user
  providers meant a round trip per friend.
- **4b — `poke_events`. Complete.** `poke_user()` sent a notification and stored
  nothing, so a poke existed only as an alert on a lock screen. It now records a row
  too — shipped ahead of the feed that will read it, because history is not
  recoverable and every poke before the table existed was lost. Nothing reads it yet,
  by design. **One thing left unverified:** the insert is guarded on `auth.uid()`, so
  no service-role or anon call can exercise it — confirm on the first signed-in build
  that a real poke writes a row.
- **4c — the Activity feed. Deferred.** Not for effort: there is no activity. Zero
  events in the last 90 days for every user, the newest finished book 884 days old,
  the newest praise 939 days old, 37 follows in the whole app, and 113 of 136 users
  following nobody. Revisit after release, when the numbers can be checked again.
