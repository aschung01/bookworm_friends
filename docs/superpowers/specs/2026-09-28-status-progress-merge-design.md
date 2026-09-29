# Status and progress, as one sheet

Replace the three-segment status sheet and the separate percent-wheel sheet with **one
sheet whose hero is a glassy reading track**, derive the status word from the position
instead of picking it, and give a book the reader abandoned its own status so it can be
recorded without lying.

Mockups: `docs/mockups/status-progress-merge/index.html` (`track` is the chosen root;
`derived` and `derived-wheel` are kept as superseded branches).
Checks: `node docs/mockups/status-progress-merge/verify.js`.

## The problem this closes

Two questions arrived separately and turned out to be one.

1. **A reader who abandons a book has no honest way to say so.** Marking it Read inflates
   the read pile and every "N read" figure. Dropping it back to Interested writes
   `start_date = NULL` (`library_provider.dart`, the status UPDATE), destroying the only
   reading fact the row carried. There is no lossless representation of "I started this and
   stopped".
2. **Recording a position goes through two doors and a nested sheet.** `BandProgressRow` opens
   the wheel; the period card opens the status sheet; the status sheet's position row opens
   the wheel _again_, stacked on top of itself.

## The constraint everything follows from

**Status is largely a function of position, and the model already encodes the hard part.**
`progress == null` means "never asked" and `progress == 0` means "opened it and got
nowhere" — two different states, documented in `band_progress_row.dart` and enforced by
`kProgressPageFloor`. So:

| position          | state       |
| ----------------- | ----------- |
| `null`            | Not started |
| `0 ≤ p < 1`, open | Reading     |
| `p == 1`          | Finished    |
| `p < 1`, closed   | Set aside   |

Which means `BookStatusSelector` and the position field are **two controls for one fact**.
That is why every arrangement of them felt like a compromise, and it is what makes the
merge a simplification rather than a squeeze.

**Largely, not wholly — and that is why Set aside is its own status.** Position cannot tell
"at 46% and still reading" from "closed at 46%": the number is identical. A second bit was
always required. See _Set aside is status 3_ below for why that bit is a new value rather
than an overload of `status 2`.

**The invariant the design needs already exists.** `updateBookStatus`'s own doc: _"Null
means 'do not write', not 'clear' … A position is not derived from anything: it is a fact
about the text that the status has no opinion on."_ Position already survives every status
transition.

## Decisions

### One sheet, one door

The book-details band becomes a single card, and it opens one sheet. `BandProgressRow` is
deleted; `showSelectPercentBottomSheet` survives but is only reached from inside the new
sheet.

**This said "carrying status, dates _and_ position", it was built that way, and a reader
called the result messy.** Four values beside the badge, wrapping onto two lines at the
default text size on a 390pt phone — which is not a wrap valve opening, it is too much in
the card — and two of the four were redundant with the other two: the start date and the
elapsed day count are one fact, and so are the percent and the page.

So the card has **two slots**. The first is _where or when_ and takes the most specific fact
there is: the position if there is one, the finish date if there is not, nothing if there is
neither. The second is _how long_, always, because the day count is the one thing neither
the position nor the sheet behind the card states. Exactly one of the two is `brandText`;
the other recedes to `secondaryText`, since two green values beside a green badge was the
other half of "messy".

| state                    | where / when | how long  |
| ------------------------ | ------------ | --------- |
| Reading, with a position | `71%`        | `15 days` |
| Reading, no position yet | —            | `15 days` |
| Set aside, with one      | `46%`        | `15 days` |
| Finished                 | `2026.09.28` | `15 days` |

**And the position is a bare percent, because the page pair was withdrawn next.** The card
read `71% · p.307 / 432` — about 120pt of its 333 — and both page numbers are derived from
the percent and the total, so the widest value on the card was restating its first third
with more precision than a glance wants. `pageCount` left `ReadingPeriodRow` with them, and
the widget now has no way to draw a page at all.

Nothing is lost, because the precision moved to where it is asked for rather than being
deleted. The sheet this card opens draws `ReadingStateLine`, whose page and total are each a
tappable span onto the wheel — so a reader who wants the page number is one tap from
_editing_ it, and a reader glancing at the band gets `71%`. This is also what finally made
the first slot narrow: the two-slot rule fixed the _count_ of values, and this fixed the
width of the one that remained.

**The start date is gone from the card, and the finish date is not.** `15 days` is what the
start date was there to say, in the form a reader wants it; nobody subtracts dates to learn
a book has been open a fortnight. Nothing on the card implies the _finish_ date, so it stays
— when a book landed is a memory anchor. Both dates remain visible and editable in the sheet
this card opens, which is what makes the loss affordable.

A finished book was the state that actually wrapped: `2026.09.13 ~ 2026.09.28` plus
`15 days` does not fit beside a badge at 333pt, so the one book whose reading period is
_complete_ was the one drawing two lines, and spending both on a closed range with its own
duration printed underneath it. Dropping `15 days` there instead would have fixed the wrap
too and costs more — a settled "it took me 15 days" is the satisfying number on a book you
have finished, where two ISO dates are a database row.

This saves **30pt of row — 40pt in the prompt state**, and the two numbers are not the same
measurement: the row is a `SizedBox(height: 30)`, while `BandProgressRow`'s doc measures 40
for the prompt state specifically (the tab strip moves 390.5 → 430.5 on a 390×844 device,
row plus the gap above it). The mockup crops show the 30, since they crop the band rather
than the page. It also retires the "two doors to one book's state" problem.

What it must not lose is the reason
that row was the door rather than the app bar's pencil: **recording a position is worth ~30
repetitions per book against 3 status changes**, and it was 333×30 in the thumb's arc
against 48×48 in the top-right dead zone. The replacement card is larger and lower, so the
frequency argument is satisfied.

On a friend's book the chevron and the tap target drop and the read-out stays — the
existing rule that _"a door nobody can open must not draw a handle."_

### The control is a glassy, drag-only track

A horizontal track spanning the whole book, ends named rather than numbered (_Not started_
→ _Finished_).

**It is a native `UISlider`, and the two things this paragraph used to say instead were both
wrong.** It said the thumb was the app's bookmark ribbon, so that what the reader set here was
what they saw on the shelf afterwards; and it said the glass came from `native_glass.dart`
gating a hand-painted fallback. Built that way, a reader's verdict was _"the bookmark makes an
ugly thumb"_ — it is a tall asymmetric shape with a notch and a shadow hung off a 4pt bar, and
at rest it read as a mark dropped on the track rather than a handle on it. The deeper mistake is
the other half: **the toolchain already ships this control.** `CNSlider` in
`cupertino_native_better` — already a dependency — is a native `UISlider`, which on iOS 26 is
where the real Liquid Glass comes from. Painting a translucent rectangle and calling it glass
got the _fallback's_ look on every platform, including the one platform that has the material.

So: `CNSlider` behind the app's existing `useNativeGlass` gate, `CupertinoSlider` elsewhere, and
the thumb is the platform's own disc.

**Deliberately not `CNSlider`'s own fallback, which is a Material `Slider`.** Material sliders
are _absolute_ — a tap on the track seeks to it — which would reintroduce the behaviour this
whole control was designed around, on Android and in every widget test, i.e. everywhere the rule
is actually checked.

**48pt including its end labels, against 256pt for a wheel and its rider.** That is what
makes the merged sheet _shorter_ than either sheet it replaces — 270pt clean, against an
estimated 342 for today's status sheet and an exact 368 for the wheel (`_sheetHeight`).

**A tap on the bar does nothing. Only a deliberate drag moves the thumb.** This is
load-bearing, not a detail: `docs/mockups/streaks/index.html`'s `band-scrubber` is the same
control and was **rejected because "a stray touch could silently rewrite your
position"** — recorded three times, once as _"rejected for being able to rewrite a position
irrecoverably."_ The house-approved answer there was arming (tap to arm, then drag, with
Cancel). Making the tap inert reaches the same safety one tap cheaper: nothing needs arming
because a tap was never live, and **dismissing the sheet discards**, so the bar owes no
Cancel of its own.

**And the platform gives it for free, because iOS sliders are relative.** Flutter's
`_RenderCupertinoSlider` holds a single `HorizontalDragGestureRecognizer`, sets
`_currentDragValue = _value` on drag start and then _adds_ deltas, so a tap opens and closes a
drag whose delta is zero. Two further gates do the real work: `hitTestSelf` accepts a pointer
only within about 22pt of the thumb, and `_handleChanged` reports only when the value differs
from the built one.

This replaced a hand-rolled slop gate, and **the discovery that forced that gate is still true
and worth keeping**: a lone drag recognizer **wins its gesture arena by default at
pointer-down**, in a microtask before the finger moves. So "use a drag recognizer only" does
_not_ produce an inert tap — built that way, a plain tap rewrote the position and a _vertical_
pan moved the thumb. What makes the tap inert is relative dragging, not the choice of recognizer.

**Relative dragging reaches both ends from anywhere**, which was raised as an objection and does
not hold: the value moves at `1 / (width - 44)` per pixel, so from any value there is exactly
that fraction of the travel to its left and the rest to its right. This matters because the
−/+ steppers were deliberately not drawn.

Rejected: **−/+ steppers** beside the bar. They were drawn to cover what a drag cannot
reach (a ~353pt track over 912 pages) and they make the sheet a form again — the same
complaint that killed the three-control stack in `streaks/index.html` (_"too many ways to
say the same thing"_). The exact path is the numerals instead.

Rejected: **the bare draggable track**, i.e. live on first touch. Kept in the mockups as
`rej-bare` so the rejection stays browsable rather than asserted.

### Three tappable numerals, and only two of them underlined

The read-out is **one line**: status word, percent, and the page inside the total.

- `46%` → `showSelectPercentBottomSheet`, unchanged.
- `213` → the same sheet opened in Page mode. Writes `progress_page`, so the read-out can
  print the page the reader gave rather than the one the arithmetic derives.
- `462` → a new total-pages sheet. **Keypad first, wheel second**, and no Percent/Page
  segment, because a total has one unit.

**Only the page numerals carry underlines.** They are small and sit inside a phrase. The
percent is the largest thing on the line and obviously the value; underlining it too made
three competing affordances out of one read-out.

**Editing the total is a new capability and the largest single win here.** `page_count` is
written once by `addBook` and never again — the wheel's own doc says _"Never written"_ —
and **~65% of the corpus has no count** (Kakao supplies none at all), which is precisely why
the wheel hides Page mode and stores a fraction. Filling the total in lights up Page mode,
the derived page, and the widget's page read-out for a book that never had them.

Constraints on that write: a floor (a book cannot have 0 pages, mirroring
`kProgressPageFloor`'s reasoning), a plausibility ceiling, and it **must not move
`progress`** — the fraction is the position, so changing the total re-derives the _page_ and
leaves the position alone.

### Set aside is status 3, not `status 2` + `progress < 1`

`const int bookStatusSetAside = 3;` in `library_provider.dart`, beside `bookStatusReading`
and `bookStatusFinished`. (There is no `bookStatusInterested` today — 0 is spelled literally
wherever it appears — so this adds the third of four names, not the fourth.)

Given a second bit is required either way, the only question is whether it is `status 2`
overloaded or a new value. A new value wins on two counts.

**Blast radius.** `finishedBooksProvider` is `.eq('status', bookStatusFinished)`, and
`home_page.dart` hands that one list to `FinishedBooksSheet`, `ReadPile` **and**
`LibraryCardSheet`. So under the overload, an abandoned book silently joins the Library Card
hero, `libraryCardStats` (pace, most-read author), the card's cover row, and — via
`groupFriendReading` — a friend's read count. Six figures needing a predicate they do not
need today, each one a number a reader could notice being wrong. With status 3 every one of
them keeps its exact current meaning with **zero edits**.

**The column would say "Read" about a book nobody read**, which every future reader of
`status` then has to remember not to believe.

**Every earlier objection to a fourth status was an objection to a fourth _segment_** —
width (the control is already full at three labels), a native platform view with no
auto-shrink, a terminal outcome placed on a progress axis, and
`selectedIndex: status.clamp(0, labels.length - 1)` silently showing **Read** for a status-3
book. This design deletes the segmented control from this sheet, so none of them survive.

Cost, and it is small — three items, not the two an earlier draft of this spec listed.
`status >= 1` (has a start date) and
`status == 2` (has a finish date) must admit 3, and `withoutFinishedBooks` /
`shelvedBookCount` must exclude it or the cover double-lists on its plank _and_ in the read
sheet. Both are pure functions with existing tests.

**And `BookStatusBadge` needs a fourth arm, or a set-aside book wears a chip reading
"Other".** Its `switch` ends `_ => (l10n.statusOther, …)`, which is the same silent-wrong-label
trap as the segmented control's `clamp` — it fails soft, so no test catches it. Four of the
five call sites are in `reading_period_row.dart`, which this design rebuilds anyway; the fifth
is `_OwnedBookRow` in the add-book sheet (the "you already own this" search result), which it
does **not** touch. Two constraints on the new arm: it must not be green, because
_green-means-reading is load-bearing across the app_ and the class doc says a test pins it;
and it must not be status 0's treatment (transparent fill, `primaryText` outline at
`unfilledBorderAlpha`), which is also what the fallback draws today — so _Not started_ and
_Set aside_ would be one chip.

`finish_date` on a status-3 row is **the day it was closed**. That is what keeps
`ReadMonthGrid.group` and `readFilterYears` working untouched, since both read `finishDate`
and neither cares why the book ended.

The overload is kept browsable as the `derived` version in the mockups.

### One secondary action, grey, and which one is the status

"Stop reading this" — the only text action on the sheet, **centred and full width**, in
`secondaryText` grey rather than `flame`, because giving up on a book is ordinary rather than
destructive. Left-aligned it sat under the start-date row's own left inset and read as a third
field in the form rather than an action on the book; the tap target is the whole width, because
a short grey label is exactly what a text-sized hit box makes hard to land on.
It writes `status = 3` and `finish_date = today`, and **leaves the position exactly where
it is**, which is the whole point: the row keeps saying 46%. Its label is a **new ARB key in
both files** — nothing in the app says this today — so the Korean is written, not translated,
like the rest of the sweep below.

**It is drawn in the Reading state only**, and `Start reading again` takes the same slot once
the book is set aside. Not started and Finished offer neither: nothing has been started at the
origin, and a finished book can be neither given up on nor resumed.

**The set-aside half reverses this section, which said a resume link would be a second
affordance for a gesture the sheet already has** — a set-aside book resumes by moving the
thumb. The premise was wrong rather than the conclusion. The thumb resumes only by _changing
the position_, so a reader who set a book aside at 46% and wants to carry on from 46% had no
move available at all, short of dragging away and back to land on the same percent. Set aside
is the one status a position cannot imply, which makes it the one status that needs a control
of its own. The related rejection of **"Start reading"** still stands, and is a different
thing: that named a transition the thumb does perform, from the origin.

**`Stop reading this` opens a confirmation sheet; `Start reading again` does not.** The
asymmetry is not about which act is weightier — setting a book aside is reversible in one tap
now, and every string here is written to keep judgement out of it. It is about what the control
physically is: a full-width opaque band of grey text directly under a tappable date row, with
no fill and no border, deliberately wide because a text-sized target for the least important
label on the sheet is hard to land on. The cost of that width is that it is easy to hit without
meaning to, and an accidental _resume_ costs a reader nothing.

**The confirmation does not write**, which is what lets it exist here at all. Like
`showSelectDateBottomSheet` and `showSelectPercentBottomSheet` it hands an answer back and the
sheet holds it until Save. Committing straight from it was the obvious alternative — a
confirmation that returns you to a form with a Save button looks like being asked twice — and
was rejected on two grounds: `Save` is the only writer anywhere in this sheet, and that
invariant is the entire answer to the objection that killed the drag control the first time it
was drawn (_"a stray touch could silently rewrite your position"_); and the symmetry that
matters is with the sheet's other sub-sheets rather than with the app's delete sheet, since
answering the date sheet does not save a date either.

Rejected: **"Put back on the shelf"**.

"Put back on the shelf" is not drawn either, and the thumb covers it after all: **a drag
back to the origin writes `null`, not `0`.** So the origin _is_ Not started, and Reading →
Not started is reachable by the same gesture as everything else on this sheet.

**What that spends is the ability to say 0% with the track**, and it is a deliberate trade.
`progress == 0` means "opened it and got nowhere" and `null` means "never asked" — two
different states the model keeps apart on purpose — and the track's leftmost pixel can only
mean one of them. It means `null`, because _that_ is the state a reader needs a gesture for;
0% survives, reachable through the percent sheet's own `0` stop, which is one tap further on
and is the right place for a distinction this fine.

**The read-out is what keeps the two legible**, since the thumb sits at the origin for both:
it says _Not started_ with no numerals in one case and _Reading 0%_ in the other. That is the
read-out earning its keep rather than a collision to design around.

### The day-stamp row goes

`ReadTodayFieldRow` is deleted from this sheet. `book_details_tab_view.dart`'s wheel path
already calls `setRead(…, read: true, bookId: book.id)` immediately after writing a
position, so on the route readers actually use, the row restates the act they just
performed.

**The rule it must not break survives intact.** _"Saving a position does not stamp a
reading day, and stamping a day does not move the position"_ is about the two writes not
triggering each other **by accident**. Moving a position is an assertion that the reader
read today; that is a deliberate reading of intent, already shipped, and unchanged here.

**The cost is real and is not fully resolved.** `setRead(read: false)` has exactly two
callers — this row, and the `kDebugMode`-gated footer in `reading_streak_page.dart`. After
this there is **no shipped way to un-record a reading day** — to delete a `reading_days` row
once it exists. See _Open questions_ #1.

### Save commits, and nothing else writes

**Save is the only writer on this sheet.** The drag does not persist on release, the three
sub-sheets' Confirm buttons do not write, and dismissing discards everything. One sheet, one
write.

This makes the sheet coherent in a way the alternative could not be: "dismissing discards"
was already the answer to the objection that killed `band-scrubber`, and a drag that wrote on
release would have made that claim false for the one control the objection was about. It also
means the reading day is stamped by Save too, alongside the position — one batch, not two
writes racing.

**The plumbing this needs already exists, and an earlier draft of this spec had it
backwards.** It claimed `showSelectPercentBottomSheet` writes, and that making it return
would be the trap in this decision. The wheel does **not** write: it takes `onConfirmed` and
`onProgressSelected` and hands the value out, and its callers decide what to do with it. Two
of the three already do the right thing —

- `book_status_bottom_sheet.dart`'s `ProgressFieldRow` holds the answer in `setState` and
  lets Save write it. **That is exactly the behaviour this decision asks for**, already
  shipped, in the sheet being rebuilt.
- `reading_streak_page.dart:313` captures `confirmed` and `answer`, reads them after the
  await, and writes through `recordReadingPosition` — the narrow two-column writer at
  `library_provider.dart:752`.

— and the third, `book_details_tab_view.dart:1328`'s `_onEditProgressPressed`, writes inside
its callback. That one is the band's second door, **which this design deletes anyway**. So
"Save commits" costs no new mechanism: it is the behaviour that survives once the immediate
writer is removed.

### Save appears only when the sheet is dirty

Clean 270pt, dirty 292pt, animated by the `AnimatedSize` the sheet already has. **Its
arrival is the dirty indicator**, which is the feedback that a drag will persist; it also
appears after a sub-sheet Confirm.

**The heading is `Reading progress`, and it was the book's own title first.** The title was
chosen so the row could never re-centre when Save appeared; that argument holds and now applies
to this heading instead. What it got wrong is what a sheet title is for — the book's name read
as a page header rather than a sheet title, and it told the reader something they already knew,
since they arrived from that book's page and the book is still on screen behind the sheet. The
heading is **always left-aligned**, present or absent Save.

The live objection: "Reading" is also the status word directly below, so the sheet can say it
twice — at different sizes and in different colours, but twice.

### Vocabulary: Not started · Reading · Finished · Set aside

`Read → Finished`, because "read" already carries the _act_ across `readToday`,
`reading_days`, `ReadPile`, `ReadMonthGrid`, `ReadWeekPalette` and the sheet's own title —
as a _state_ it is the most overloaded word in the app — and because the track's right end
already says **Finished**, so leaving the status word as "Read" is the same "one object
looked like two" defect this project keeps correcting.

`Interested → Not started`, because **adding a book to a shelf already states the intent**,
so the status axis does not have to, and the track's left end already says it.

This is a copy sweep, not a code change, and it is smaller than it sounds: **both keys
already exist with the right names** — `statusFinished` currently holds the _value_ "Read" /
"읽음" — so nothing is renamed and no call site moves. Only the four strings change, and the
Korean has to be **written rather than translated**, per the widget copy's precedent.
`finishedBooksTitle` / `noFinishedBooks` / `noFinishedBooksInYear` all change in the same
pass — see _Where a set-aside book lives_, where the title becomes the filter's read-out and
so needs two of it.

The three-segment `BookStatusSelector` **stays in the add-book sheet**, where nothing has
happened yet and there is no position to derive from.

### Where a set-aside book lives: the read sheet, and the title is the filter

`FinishedBooksSheet` gains a two-state completion filter, and **the sheet's own title is its
read-out**. A chevron-down sits to the right of the title; title, count and chevron are one
tap target; tapping opens a glass popover with two checkable rows.

| mode      | title            | count | rows                                     |
| --------- | ---------------- | ----- | ---------------------------------------- |
| default   | `Books finished` | 23    | **Show finished only** ✓ / Show all read |
| inclusive | `Books read`     | 29    | Show finished only / **Show all read** ✓ |

**This removes a label collision instead of renaming around it.** The drawn alternative was
a `Finished` / `All` pair, and its flaw was that `All` would sit two rows above the year
rail's `All time` — one word doing duty for two scopes. A title that says which set it is
showing needs no second label at all.

**And the pair is the vocabulary split, not a coincidence.** `Finished` is the _state_ and
"read" is the _act_ — which is the whole reason the status word is being renamed `Read →
Finished`. A set-aside book was not finished; it was partly read. Note this **reverses** the
earlier note that `All Read` was the label to avoid: that objection was about modifying
`read` as a _status_, where it is still right.

**It also retires a documented disagreement.** The plan was that this sheet would read 29
while the Library Card read 23 a tab away, both correct, with the clash written up in
`AGENTS.md` as deliberate. With the title switching, the default state reads `Books finished
23` and matches the Card exactly, and the only state that reads 29 is the one whose title
says why. The `AGENTS.md` note shrinks to a sentence.

**The mechanism exists twice and the obvious one is wrong.** `read_filter.dart`'s collapsed
popover is `CNPopupMenuButton` with `CNButtonStyle.glass` and `CNPopupMenuItem(checked:)` — an
apparently exact fit, including the check marks. But its `buttonLabel` is rendered **by the
platform**, and that file's own record documents the label arriving at "the system's 17pt in
the theme's tint, wrapped onto two lines inside a platform view Flutter had sized for 13pt".
The title is the largest text on the sheet and `LibrarySheetTitle` draws its count in the
brand colour, so it cannot become a platform-styled button label.

The right precedent is `shelf_picker_popover.dart`'s `showShelfPickerPopover` — an app-drawn
card hung from an anchor's `RenderBox` rect, `LiquidGlassContainer` on iOS 26 and
`BackdropFilter` as the fallback, where _"Flutter draws every pixel of content, the platform
supplies the material behind it."_ Its doc also notes the app-drawn path _"is the only path a
widget test ever takes, because `flutter test` reports Android"_, which is what makes this
testable at all.

**The year rail stays directly under the title row** — `expandedHeader` is `Column[title,
ReadFilter(expanded: true)]` — and that is structure, not preference. It is also why the
filter could not live on the rail's row: drawn to scale, a card hung under the title
**occludes the rail**, so the two would have collided in geometry as well as in wording.

**The filter applies in both sheet states; only the chevron is expanded-only.** An earlier
draft scoped the whole thing to the expanded sheet and left "the spine pile completed-only",
which is inconsistent once the filter is a persisted view mode — the count would jump on
collapse. Collapsed, the header's row already has the year popover competing for it, and
`library_clearance_test.dart` exists because that row overflows at 2× text with a two-digit
count.

**A friend's library shows it too.** `FinishedBooksSheet` also serves friends through
`userFinishedBooksProvider`, which needs a set-aside sibling. The consequence, stated rather
than buried: **a friend can see which books you gave up on.** The default is finished-only, so
it is per-view and opt-in, and `inviteStatusRead`'s `"{count} read"` already counts the act
rather than the achievement.

Set-aside books are fetched by their own provider and merged **inside the sheet**, so nothing
else in the app changes.

New ARB keys for both titles and both menu rows, and **`noFinishedBooks` /
`noFinishedBooksInYear` have to follow the mode**, or the empty state reads "No books read
yet" under a `Books finished` title.

### The mark on a set-aside cover is a dog-ear

A corner fold in the read grid. **Deliberately not the bookmark ribbon**, which means
_actively reading_ on the shelf, the Library Card and the home-screen widget — reusing it
would say the opposite. The fold is what stops "Books read 29" being read as 29
completions.

## Data model

One migration:

```sql
-- status 3 = set aside: closed short of the end.
-- No CHECK is added; `books.status` has none today and adding one here would be a
-- change of a different kind.
comment on column public.books.status is
  '0 not started, 1 reading, 2 finished, 3 set aside';
```

That is the whole schema change: `status` is already a `smallint` with no check
constraint, so value 3 needs no DDL. `progress`, `progress_page` and `page_count` all
exist.

**Verified against production (project `fkynxmfnsgtafrsbzwtu`) before choosing this:**

| fact                                            | count |
| ----------------------------------------------- | ----- |
| books at status 2 with a non-null `progress`    | **0** |
| books at status 0 with a non-null `start_date`  | **0** |
| books at status 1 with a non-null `finish_date` | **0** |
| books with any `progress` at all                | **3** |

So no existing row is retroactively relabelled by any rule here, and `progress == null` on a
closed book can safely mean "finished".

Apply it with the Supabase MCP server's `apply_migration`, not `supabase db push` — this
checkout has pending migrations from parallel work. Then reconcile
`schema_migrations.version` with the local filename's timestamp, per `AGENTS.md`.

## Write paths, and the trap in merging them

**Do not route a position-only edit through `updateBookStatus`.** It recomputes
`reading_shelf_index` from `_readingHeadIndex()` on every call, so a progress nudge would
**bump the book to the head of the Reading shelf** — 30 times a book, silently reordering a
row the reader arranged. Two consequences:

- `recordReadingPosition` (`library_provider.dart:752`) stays the writer for a position-only
  change. It exists and the streak page already uses it.
- In `updateBookStatus` (`library_provider.dart:895`), the re-head must be gated on the status
  actually changing.

`showSelectPercentBottomSheet`'s `_touched` gate must survive: agreeing with a pre-filled
wheel must not rewrite the column. Its own record notes the regression — _"merely opening
the sheet and agreeing with it moves the bookmark back a page."_

## What this deletes

`BookStatusSelector` from the status sheet · `ReadTodayFieldRow` · `BandProgressRow` ·
the band's second door · the nested wheel-over-sheet · the "how much did you read?"
question · the derived-set-aside inference · the −/+ steppers that were drawn for it · and the
`Finished` / `All` segment that was drawn for the read sheet.

## Open questions

Five of the six are decided and have moved into _Decisions_: Save commits the drag, the
filter is the title plus a glass popover, a friend's library shows it, a drag to the origin
writes `null`, and un-recording a reading day is **accepted as lost**. One remains.

1. **This inverts `ss-finished`**, which removed the position row at status 2 because _"a
   finished book is at the end by definition, so asking is worse than not asking."_ The
   defence is that the track asks it as part of the gesture that also _reports_ it. This is a
   judgement on the drawing rather than a fork in the build, so it does not block
   implementation.

### Accepted: a reading day cannot be un-recorded

Deleting `ReadTodayFieldRow` removes the only caller of `setRead(read: false)` a reader can
reach — the other is `kDebugMode`-gated. So a `reading_days` row, once written, cannot be
deleted from the app. **Accepted on instruction, and the footer stays gated.**

What it costs, stated so nobody has to rediscover it from a bug report: correcting a
percentage the reader got wrong last week stamps **today**, which `AGENTS.md` already records
as an accepted cost of the wheel asserting intent — and after this change that stamp is
permanent. The reasoning for accepting is `AGENTS.md`'s own, unchanged by this design:
_"a reader offered an Undo is being invited to treat their own record as provisional"_, and
the streak page's month grid already shows what happened.

If it ever needs reversing, `streakUndoToday` and the footer both exist and
`streakUndoVisible` is one line.
change.

2. **This inverts `ss-finished`**, which removed the position row at status 2 because _"a
   finished book is at the end by definition, so asking is worse than not asking."_ The
   defence is that the track asks it as part of the gesture that also _reports_ it.

## Phasing

The work splits into three, in risk order, and only the first is self-contained enough to
ship alone.

1. **The sheet.** The track, the read-out, the three sub-sheets, Save-as-the-only-writer,
   Save-when-dirty, the vocabulary sweep. No schema change, no new status. Set aside is not
   offered yet.
2. **Set aside.** `bookStatusSetAside`, `BookStatusBadge`'s fourth arm, the plank filters, the
   secondary action, the read sheet's title-popover filter, the friend-library provider and the
   dog-ear.
3. **Editing the total page count.** Its own sheet and its own write path; independent of
   both above and the thing most likely to want its own review, since it is the only new
   column writer.

## Tests

- The track is inert on tap and moves on drag, with real `Slider` semantics —
  **increment/decrement plus the typing path, or it is unusable under VoiceOver.** A
  drag-only scalar is not an accessible control.
- Save is absent when clean, present after a drag, and present after a sub-sheet Confirm.
- **Nothing writes before Save**: a drag then a dismiss leaves `progress`, `progress_page` and
  `reading_days` all untouched, and so does a sub-sheet Confirm followed by a dismiss. This is
  the assertion that makes "dismissing discards" true rather than claimed.
- A drag to the origin writes `null`, not `0`, and the read-out says _Not started_ — while the
  percent sheet's `0` stop still writes `0` and reads _Reading 0%_.
- The read sheet's title is `Books finished` with the default filter and `Books read` with the
  inclusive one, its count follows the visible list, and the month counts sum to it in both.
- The filter is honoured collapsed as well as expanded, so the count does not jump on
  collapse; the chevron is drawn only when expanded.
- A friend's read sheet offers the filter and the set-aside provider returns that friend's
  rows, not the viewer's.
- A status-3 book is off its plank and out of `shelvedBookCount`, and in the read sheet only
  under the inclusive filter.
- **A status-3 book's badge does not read "Other"**, and its chip is neither green nor
  identical to status 0's. This is the one new assertion that guards a _silent_ wrong label
  rather than a crash — `BookStatusBadge`'s `_` arm fails soft.
- The secondary action is present while Reading and absent at Not started, Finished and Set
  aside.
- The Library Card hero, `libraryCardStats` and `groupFriendReading` are **unchanged** by a
  status-3 book — the assertion that earns its keep, since it is what the status value was
  chosen for.
- Editing the total re-derives the page and leaves `progress` byte-identical.
- A position-only write does not touch `reading_shelf_index`.
- The read sheet's title row does not overflow at 2× text with a two-digit count and the
  filter present (`library_clearance_test.dart`). The chevron adds to that row, so this is a
  tightening of an existing guard rather than a new case.
- The sheet fits a 375×667 surface. `flutter_test`'s default 800×600 is shorter than any
  phone the app supports, so the harness must set a real size.

## Measured, and estimated

Exact, from the source: the wheel sheet's **368pt** (`_sheetHeight` sums 64 + 48 + 220 +
36); ~65% of books with no `page_count`; the 30-vs-3 frequency ratio
(`band_progress_row.dart`); and the four production counts above.

Estimated, summed from row heights in the Dart and labelled as such on every mockup crop:
270pt clean, 292pt dirty, 246pt not-started, 282pt terminal, ~342pt for today's status
sheet, ~300pt for the read sheet's crop.

**Measured after building**, at a real 375×667 with the app's own fonts registered (which is
what made them measurable — under the test font every string is one em-square per glyph):

| state                            | measured | estimated |
| -------------------------------- | -------- | --------- |
| Reading, clean                   | **275**  | 270       |
| Reading, dirty                   | 286      | 292       |
| Finished, clean (both date rows) | 276      | 282       |
| Set aside, dirty                 | **287**  | —         |
| Not started, clean               | **170**  | 246       |

Three within 6pt, and the estimates were good. **Not started is 76pt out, and not by an
arithmetic slip:** at the origin the read-out collapses to a single word — no percent, no page
pair — and neither date row is drawn, which the row-sum did not model. The sheet is comfortably
shorter than both it replaces (342 and 368) in every state.

### Save and Reset sit at the foot, and the read-out ends at the right edge

Save was in the title row beside the heading, at 92×32. It was asked for at the foot, and the
move brings two things with it: `Reset` becomes possible — a 92pt slot next to a title has room
for one button, a full-width row has room for a pair — and the sheet stops putting its only
write control in the corner furthest from the thumb, on a sheet whose whole argument for being a
sheet is that the control sits in the thumb's arc. The delete sheet's geometry: two `Expanded`
buttons at 44 with a 12pt gap, recessive on the left.

**Its arrival is still the dirty indicator**, so there is no other unsaved marker and no
disabled Save to explain. Arriving _below_ the track is also what let the title row's pinned
height go — anything appearing down there cannot push the track, which is what the pin was for.

**`Reset` is not `Cancel`, and the difference is that it stays.** Dismissing already discards,
so a button that dismissed would be a second spelling of a gesture the reader has. This one puts
every field back to what the sheet opened with and leaves them on it, which is what someone who
over-dragged the track wants: the old value back, and to carry on. It restores the _arguments_,
which is the same set `dirty` compares against, so a reset sheet is clean by construction and the
row cannot survive its own press.

**The page pair moved to the trailing edge.** `Reading 71%` holds the left, `~ p.307 / 432` ends
flush with the line. Two things about how, both of which a simpler spelling gets wrong:

- **`WrapAlignment.spaceBetween` over two nested groups, not over the flat list of four parts.**
  Flat, it spreads all four evenly and floats the percent into the middle of the line.
- **Nested `Wrap`s, not a `Row` with a `Spacer`.** A `Row`'s children have no run to drop to, so
  its only degradations are overflow and ellipsis — and a clipped status word is the one failure
  that makes the line lie about the book. Nested, each group is handed the outer `Wrap`'s own
  `maxWidth`, so a group too wide for the line soft-wraps inside itself.

When the two groups will not fit the pair drops to a second run and lands **left**, because
`spaceBetween` leaves a lone child in a run at the start. Right for a continuation; right-aligning
it would open a ragged gutter mid-read-out. The same rule is why the origin state needs no special
casing: one child, at the start.

### And then the sheet was given one height, 335 — now 384

**Every figure above is a natural height, and the sheet no longer has one.** It is framed to
its tallest state — set aside with a dirty Save, 287 of content plus `AppSheet`'s 48 — so every
state renders at 335 and the sheet never resizes.

The reason is not tidiness. A bottom sheet is anchored to the bottom of the screen, so growing
moves its _top_ edge up and every child with it — and both date rows sit **below** the track.
Dragging off the origin adds the start-date row and the Save button, about 70pt, which slid the
control out from under the finger that was dragging it. The previous answer to this was an
`AnimatedSize`, and the case that pinned it said why it mattered: _"both happen on the same
gesture, so without the animation the sheet would jump twice under the reader's thumb."_ That
diagnosis was right and the remedy treated the symptom; 220ms of easing still moves the track.

Two details that only a rendered frame and a rectangle-level assertion would find:

- **The title row is pinned to 32 as well**, which is the Save button's height and not the
  title's ~21. Without that the row grew 11pt the instant the sheet went dirty and pushed
  everything below it down — the same defect one level in, and invisible to any assertion about
  the sheet's own height. The case measures `ReadingTrack`'s rectangle for this reason.
- **It is a minimum height, not a fixed one.** A `SizedBox` would trade a moving control for a
  clipped one at large accessibility text sizes; `ConstrainedBox(minHeight:)` lets a state that
  genuinely needs more room grow, and the `AnimatedSize` is kept for that one residual case.

**287 → 336 of content when Save moved to the foot**, so 384 in total. The title row gave back
11 and the commit row costs 60, and the frame follows the tallest state, so every state pays the
60 whether or not it draws the buttons.

**Which makes the sheet taller than both it replaced, and that headline claim is now false.**
342 for the old status sheet, 368 for the percent wheel. Two deliberate decisions spent the
margin, in order: framing the sheet so the track stops moving under a drag (275 → 335), and
moving Save to the foot (335 → 384). Neither is reversible by tightening a gap, and the second is
what crossed the line. The case that used to assert `lessThan(342)` now asserts `greaterThan` both,
so the size is a number someone has to look at rather than a claim that quietly stopped being true.

**And what it costs is a void on Not started: 214pt, over half that state.** Its content is 122 —
a single word in the read-out, no date row, no text action, nothing to commit — and the sheet is
sized for a set-aside book, which that book is three taps away from. It was 165 before the commit
row moved down.

**Both sides of the trade got worse at once**, which is the thing to weigh: the jump the frame
prevents also grew, from 115pt to 165, because the commit row arrives below the track. So the
frame is worth more than it was and costs more than it did.
`book_status_bottom_sheet_test.dart` pins the 214 as a number for exactly this reason.

Three ways out, none taken:

- **Draw the start-date row at the origin.** Fills 60 of the 214 and closes a real gap — a start
  date cannot currently be set without first inventing a position by dragging the thumb. The only
  option that costs the no-jump property nothing.
- **Frame only the states a drag moves between** — Not started → Reading → Finished, 288 — and let
  the two confirmed status transitions resize the sheet by 48. Halves the void; a tap's target
  moving after the tap has completed is a milder defect than a drag's target moving mid-gesture.
- **Give the frame up.** The void goes and the 165pt jump comes back.

**Verified by rendering the mockup:** the popover, hung under the title the way
`showShelfPickerPopover` hangs its card, **occludes the year rail** — which is a second reason
the filter could not have gone on the rail's row, this one geometric. Recorded rather than
designed away; sliding the card below the rail is available if it is judged worse than the
occlusion.

**Still not verified: how the sheet looks on a device.** The mockups are CSS standing in for
Liquid Glass, and a widget test reports Android, so every automated check of the track has
exercised the `BackdropFilter` fallback rather than the real material. The read-out's longest
case is confirmed to wrap rather than clip at 2× text in both locales, but it has been *measured*
rather than looked at.

Two things the build found by rendering that no green suite could see: the track's thumb sat
above its groove (the row had been sized to the bookmark asset's box rather than to the visible
ribbon), and the read-out inherited an underline from `MaterialApp`'s fallback text style — on
the one widget whose whole contract is which parts are underlined.

**One correction worth recording about the mockup itself**, because it is the cost of writing
a page without opening it: the committed version carried a stray `</div>` in its lead
paragraph and a stray `</p>` before the flows sidebar, which closed `#v-screens` early and
left **view switching completely dead** — all three views on screen at once, the sidebar
outside its column. `verify.js` was green throughout, because it checks the script against a
DOM stub and never parses the document.
