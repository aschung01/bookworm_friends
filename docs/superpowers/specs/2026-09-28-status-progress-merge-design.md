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

The book-details band becomes a single card carrying status, dates **and** position, and it
opens one sheet. `BandProgressRow` is deleted; `showSelectPercentBottomSheet` survives but
is only reached from inside the new sheet.

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
→ _Finished_), thumb drawn as the app's bookmark ribbon so what the reader sets here is
what they see on the shelf afterwards. Glass via `native_glass.dart`, which gates real
Liquid Glass on iOS 26 and paints a fallback elsewhere.

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

### One secondary action, grey, and only while Reading

"Stop reading this" — the only text action on the sheet, in `secondaryText` grey rather
than `flame`, because it is an ordinary thing to do to a book and not a destructive one.
It writes `status = 3` and `finish_date = today`, and **leaves the position exactly where
it is**, which is the whole point: the row keeps saying 46%. Its label is a **new ARB key in
both files** — nothing in the app says this today — so the Korean is written, not translated,
like the rest of the sweep below.

**It is drawn in the Reading state only**, which is what the mockups encode — `one-rest`,
`one-armed` and `one-nopages` carry it; `one-finished`, `one-setaside` and `one-null` do
not. The reasoning per state: nothing has been started at Not started; a finished book
cannot be given up on; and a set-aside book **resumes by moving the thumb**, so a resume
link would be a second affordance for a gesture the sheet already has.

Rejected: **"Put back on the shelf"** and **"Start reading"**. "Start reading" names a
transition the thumb already performs — drag off the origin — and the sheet's whole argument
is that status is a read-out of position, so a button that sets a status is the old model
smuggled back in.

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

**The book title is always left-aligned in the title row**, present or absent Save, so the
row does not re-centre when the button appears.

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

**Verified by rendering the mockup:** the popover, hung under the title the way
`showShelfPickerPopover` hangs its card, **occludes the year rail** — which is a second reason
the filter could not have gone on the rail's row, this one geometric. Recorded rather than
designed away; sliding the card below the rail is available if it is judged worse than the
occlusion.

**Still not verified: how the sheet itself looks.** The mockups are CSS standing in for Liquid
Glass and for a Flutter layout. The glass treatment and the one-line read-out at
`Set aside 46% p.213 of 462` — longer in Korean — need eyes before implementation.

**One correction worth recording about the mockup itself**, because it is the cost of writing
a page without opening it: the committed version carried a stray `</div>` in its lead
paragraph and a stray `</p>` before the flows sidebar, which closed `#v-screens` early and
left **view switching completely dead** — all three views on screen at once, the sidebar
outside its column. `verify.js` was green throughout, because it checks the script against a
DOM stub and never parses the document.
