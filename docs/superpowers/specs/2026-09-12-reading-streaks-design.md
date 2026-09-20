# Reading streaks: a counter with one home, and a wheel that spins percent

Status: **designed, not built.** Nothing below describes code that exists.
Drawing: `docs/mockups/streaks/index.html` — **one version, collapsed from
fourteen**, with `verify.py` asserting 304 checks over it. The superseded
versions are gone from the page (the chain is still applied to build the frames,
so every figure stays derived); the reasoning behind each is in git. Every figure in this document is derived from a
constant in that page or from a live query against the database, and the ones
that matter are asserted by the verifier so they cannot drift.

**Two corrections have been folded in since the first draft, and they matter more
than anything else here.** First, **freezes are deferred** — the column is
provisioned, the feature is not built. Second, and larger: versions 1–13 designed
a nightly control, a bespoke position picker and a two-figure Library Card
**next to** the shipped UI rather than out of it. There is already a sheet that
means "update this book's state", already a picker pattern for choosing a value,
and already a Library Card with a settled structure. This design now uses all
three. See "The state sheet is the home".

This design covers **two** things:

1. the **streak counter** — where the reader's own number lives, and the six
   moments it has to survive;
2. the **position control** — how a reader says how far into a book they are.

They are one document because they share a screen and are constantly confused
for each other, and the single most important rule here is that **they are not
connected**: setting a page does not stamp a day, and stamping a day does not
move a bookmark. Nine of the twelve versions in the drawing died of failing to
keep those two apart.

## Context

### The corpus, which argues against this feature

Queried live (project `fkynxmfnsgtafrsbzwtu`, Postgres 17):

| fact                                            | value           |
| ----------------------------------------------- | --------------- |
| profiles                                        | 137             |
| …that never added a book                        | 63              |
| active in the last 30 / 90 days                 | **1** / 2       |
| books at `status = 1` (reading)                 | 109             |
| …started more than a year ago                   | 107             |
| …started in the last 30 days                    | **0**           |
| median age of a reading book's start date       | **1205 days**   |
| friendships                                     | 11              |
| `book_memos`, `book_compliments`, `poke_events` | **0 rows each** |

A streak counter is a retention mechanic, and there is presently no retention to
act on. The honest reading of that table is "build the ledger, skip the
counter." **That recommendation was made and overridden**; the counter is in
scope by decision. It is recorded here so that if the counter ships and moves
nothing, this is the reason and not a mystery.

The table does have one direct design consequence: those 1205-day-old reading
books are why the drawing's fixture shows `D+1468` / `D+964` / `D+1096`, and why
"day 1 of a new streak" is the _normal_ first-run state for every existing user.
No frame assumes an inherited streak.

### The schema does not have the column this feature writes to

This is the finding that most changes the shape of the work, and it contradicts
an assumption carried through the whole drawing.

**`books.position` is not a reading position. It is the shelf ordering index.**

```
books.position  integer NOT NULL
```

Across all 473 books, `max(position) = 25`, values run dense from 0 per shelf,
and they **duplicate freely within a shelf** — the 49-book shelf
`240a7ab9…` holds 49 books across only 26 distinct positions, with six books at
`22` and five at `19`. No row anywhere has `position > page_count`. It is an
ordering column with collisions, exactly like `shelves.position`.

A search of every column in the schema matching
`progress|percent|pct|page|frac|bookmark|current|pos` returns exactly three:
`books.page_count`, `books.position`, `shelves.position`.

So: **there is today no reading-progress column at all.** The `p.148` in the
drawing, the ribbon on the cover, the `72%` in the band and the entire percent
wheel write to a field that does not exist. This needs a migration (below), and
the new column **must not be called `position`** — reusing that name would
silently reorder shelves.

### The other coverage number, which the wheel depends on

`page_count` is null for most books, and that is worse on the shelf that matters:

| status           | books   | with `page_count` | covered   |
| ---------------- | ------- | ----------------- | --------- |
| 0 (want to read) | 132     | 46                | 34.8%     |
| **1 (reading)**  | **109** | **38**            | **34.9%** |
| 2 (read)         | 232     | 96                | 41.4%     |

So **65% of the books a reader could set a position on have no page count**, and
this cannot be improved: the catalogue source (Kakao) has no page field. Any
design in which the page number is the thing the reader aims at is a design that
does not work for two books in three. That is the whole argument for percent, and
it is a data fact rather than a preference.

## The record

### One table

```sql
create table reading_days (
  user_id    uuid not null references profiles (id) on delete cascade,
  day        date not null,
  kind       text not null default 'read' check (kind in ('read', 'freeze')),
  book_id    uuid references books (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);
```

The composite primary key is the design, not bookkeeping. It makes the write
**set membership rather than an append**, which buys three properties for free:
a double tap cannot count a day twice, a retry after a failed request is safe,
and an offline queue that replays twice is safe. There is no counter to
increment and therefore nothing to get out of step.

`on delete set null` on `book_id`, not `cascade`: deleting a book must not
delete the reader's history of having read that night.

### A freeze is a row, not a policy — but not yet

**Freezes are deferred. The column ships; the feature does not.** `kind` is
included in the DDL above with a default of `'read'` because provisioning it now
costs nothing and avoids a migration later, and because the derivation is written
once either way. Nothing reads or writes `'freeze'` in the first cut, and no UI
refers to forgiveness — the drawing removes every freeze frame in `state-sheet`
rather than leaving one that implies the feature exists.

When it does arrive, the design is that a forgiven day is **a row like any
other**, so the streak derivation never learns what forgiveness is — it still
just asks which days are present. The consequences, recorded now because they are
why the column is shaped this way:

- the run-length query below is unchanged by the freeze feature existing;
- the primary key makes it impossible to freeze a day that was read, which is
  correct;
- the card can draw a freeze **differently** from a read day (a dashed cell
  against a filled one), so the record stays truthful: the day was not read, it
  was forgiven, and those must never look the same;
- the allowance can change without a migration.

**What deferring costs, drawn rather than asserted.** `state-sheet` redraws the
month with the forgiven day dropped, derived from the same fixture. Eleven days
read either way — but the run ending today falls from **12 to 3**, because one
missed Thursday severs the thread instead of being bridged. That is the whole
mechanic in one figure, and it is the failure mode people quit over: a single
missed night is a total reset. Defensible for a first cut, since there is nothing
to sell and the policy is unsettled, but it should ship knowing this.

One consequence for the UI while freezes are absent: the month's "freezes used"
chip is **omitted, not zero-filled** — the rule `LibraryCardStats` already
enforces for its pace and author tiles. A `0` would advertise a feature that
does not exist.

### The day is a local date on a 4am rollover

Not a UTC date, and not local midnight:

```
readingDate(now) = localDate(now - 4 hours)
```

A tap at 00:30 therefore records **yesterday**, because reading at 00:30 is the
behaviour this entire feature exists to encourage and a design that punishes it
is broken. 4am is also the deadline the evening warning quotes, so the number in
the copy and the number in the arithmetic are the same one.

**`profiles` has no timezone column** (confirmed: `id`, `username`, `emoji`,
`fcm_token`, `created_at`, `updated_at`, `avatar_path`, `handle`). Rather than
add one, **the client computes the date and sends it.** This is the right call
and not just the cheap one: the rollover and the local date are both facts about
the phone in the reader's hand, and a server recomputing them from a stored
zone would be authoritative about something it cannot observe. The accepted cost
is that a reader who crosses timezones gets whatever their phone said, which is
also what they would answer if asked.

### The streak is derived on read, never stored

Gaps-and-islands over the rows:

```sql
with d as (
  select day from reading_days where user_id = $1
),
g as (
  select day, (day - (row_number() over (order by day))::int) as grp from d
)
select count(*) as len, max(day) as last_day
from g
group by grp
order by max(day) desc
limit 1;
```

The current streak is `len` **if** `last_day >= readingDate(now) - 1`, and `0`
otherwise. Yesterday counts because a reader who has not yet read today has not
yet lost anything — that is what the chip's grey state means.

The longest run is the same query without the `limit`, taking `max(len)`.

**Derive it on the client.** A reader's entire history is one row per day; even a
perfect four-year streak is under 1,500 rows, and fetching the trailing 400 is
free. Doing it client-side means the chip needs no round trip, and — the real
reason — the derivation depends on `readingDate`, which only the client can
compute. A Postgres function would need the timezone the schema does not have.

### What the stamp does not do

The important half, and the one the drawing kept getting wrong:

- it does **not** touch the reading position;
- it does **not** write `start_date` or `finish_date`;
- it does **not** move the book off the reading shelf;
- it posts **nothing** to the friends feed unless a note was attached.

The reading lamp, the chip's tick and the week row on the card are all reads of
one fact: _is there a row for today_. Three surfaces, one query, no
reconciliation.

### RLS

Follows the shipped `friendships` pattern. Reader owns their rows:

```sql
alter table reading_days enable row level security;

create policy reading_days_own on reading_days
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
```

Friend visibility is deliberately **not** specified here — see Open questions.
Nothing in the six moments needs it, and 126 of 137 profiles have no friend to
show a streak to.

## The state sheet is the home

**This section replaces the one that used to be here.** Versions 6–8 of the
drawing spent themselves choosing where a nightly "Read today" control should
live on the book details page, measured five candidate placements to the point,
and settled on a one-word chip trailing the reading-period card at a cost of
2pt. All of that is now **superseded**, because it was solving a problem the app
had already solved.

### What already ships

`showBookStatusBottomSheet` (`lib/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart`)
is reached from the **`edit_outlined` action in the details page app bar** — the
second of two actions, after `delete_outline`, and only when `isSelf`. It is
already "update this book's state":

- `Padding` 24 on all sides, bottom plus `viewInsets`;
- title `changeReadingStatus`, `AppTextStyles.subtitle` (17/w600);
- `BookStatusSelector` — a `CNSegmentedControl` on iOS 26+, deliberately
  untinted, labelled `statusInterested` / `statusReading` / `statusFinished`;
- a `DateFieldRow` for the **start date when `status >= 1`**;
- a `DateFieldRow` for the **finish date when `status == 2`**;
- one full-width `ElevatedActionButton`, height 44, `save`;
- all wrapped in an `AnimatedSize` (220ms, `easeOutCubic`) precisely because
  **picking a status shows and hides rows**.

That last point is the whole argument. The sheet's existing design is
"conditionally reveal the fields this status has meaning for."

### So the position and the day are two more fields

Both are added to that sheet, revealed at `status == 1`:

| row              | when          | widget                                       |
| ---------------- | ------------- | -------------------------------------------- |
| Start date       | `status >= 1` | `DateFieldRow` (ships)                       |
| **How far in?**  | `status == 1` | `DateFieldRow`'s twin, value is a percentage |
| Finish date      | `status == 2` | `DateFieldRow` (ships)                       |
| **I read today** | `status == 1` | checkbox                                     |

**"How far in?" is a `DateFieldRow` in everything but the value it carries** —
same `surfaceVariant` ground, radius 10, padding 14/10, label left in
`AppTextStyles.body`, value right, `secondaryText` reading `select` when unset,
and the same tap-opens-a-picker behaviour. The page number rides after the
percentage in the smaller weight so it cannot be mistaken for the thing being
set.

**"I read today" is a checkbox, not a button.** _Save_ is already the verb on
this sheet; a second verb would compete with it. This is the one place the day is
a _field_ rather than an action, and that is the correct framing here because the
sheet's job is to describe the book's state.

**The position row is absent at `status == 2`.** A finished book is at the end by
definition, so asking is worse than not asking.

### What this deletes

- The "Today" chip and the entire placement argument (`stamp-a`), including the
  +58 / +32 / +2 measurements. No new control is added to the band.
- The separate position sheet. There is one sheet.
- **The coupling question.** "Should saving a position also stamp the day?" cannot
  arise once they are two fields on one form under one Save. This was open
  question 2 in the first draft and it is now closed by construction.
- The app-bar glyph candidate, twice over: the bar has two actions and no room,
  and the sheet those actions open is where this belongs.

### The cost, which is real and not yet solved

The nightly act is now: tap the book, tap `edit_outlined`, tick a box, tap Save.
**Four taps and a form**, for something a reader should do in one — and the
button they must find is labelled with a pencil, which does not say "I read
tonight". `y-night` draws this deliberately so it cannot be waved past.

The sheet is the right home for the **truth**; it is the wrong home for a
**habit**. So the sheet stays the complete form, and a cheap path is still needed
— see Open questions. The property worth protecting is that the cheap path
writes the same row, and never becomes a second place to edit position.

## The counter

### Exactly one permanent home for the number

The rule that resolved `streak-home`: a number displayed in two places is a
number that will eventually disagree with itself. So:

- the **Library Card** is the numeric home;
- the **library bar chip** (`▣ 12`) is the everyday glance, and **tapping it
  opens the Card**. It is a pointer, not a second home.

The chip costs no vertical space, which matters on the one screen whose recent
redesign was specifically about lifting the reading books up.

### What the Library Card actually is

**Also a correction.** The first draft described the Card as "a big figure plus
the month's stamp grid", and drew it with two hero figures. The shipped card
(`library_card_body.dart`, `stat_tile.dart`) is not that:

- **one hero `StatTile`** — `booksRead` at 46pt on the `brandFill` gradient,
  radius 18, padding `LTRB(16,16,16,18)`, an 11pt uppercase `caption` label
  reading "All-time library card" or the year, a 13pt sub-line
  (`"books · 86 days reading"`), and a `CardCoverRow` footer 12pt below it;
- **then whatever tiles have something true to say** — currently _Pace_ and _Top
  author_ — in `Expanded` slots, each `StatTile` at padding `LTRB(16,14,16,14)`
  with a 30pt figure;
- **omitted, never zero-filled.** `LibraryCardStats` exposes `hasPace` and
  `hasTopAuthor` for exactly this, and the class comment explains why: at the
  median this reader has finished **two** books, 57% of finished books are
  same-day so contribute no span, and 40 of 53 readers have a "top author" who
  wrote one book.

So the streak is **a third tile, a peer of Pace** — not a second hero. Which
settles what was open question 7: **books read stays the hero**, and the answer
came from reading the widget rather than from taste.

And it is **absent when there is no run**, not showing `0`. Given 1 active user
in 30 days and 0 books started in 30, the tile is missing for almost everybody on
day one, so the card has to look right that way first — which it does, because
omission is already how it behaves.

### The month grid has no home yet — answered: its own page

The finding that falls out of the above, and it was a genuine gap. **The Card is
scoped by year** — `year == 0` is all time, and the hero says so in its own label.
A month pager cannot sit inside it without putting two conflicting time scopes on
one surface. So either:

- the grid becomes **its own destination**, which the library-bar chip opens
  (chosen — it keeps the Card's structure intact and gives the chip somewhere to
  point; drawn as `cp-d-page`, and see open question 8); or
- the Card grows a **year-scoped** view of the same data — a 365-cell strip
  rather than a month — which is a drawing nobody has made, and is now not needed.

The Card is also the preview for a share artifact (`shareable_library_card.dart`),
so anything added to it has to survive being printed there too. A month grid
almost certainly should not be.

### Four states, each a different fact

Not four tints of one fact:

| state           | means                                 |
| --------------- | ------------------------------------- |
| green           | today is recorded                     |
| grey            | today is open                         |
| amber           | today is open and the evening is late |
| blue, snowflake | a freeze is covering a gap            |

### No flame — overturned, and the reversal is the record

The original rule, which is still the better argument about metaphors: the app
already owns four working ones for "a day was recorded" — the ink stamp on the
due-date card, the reading lamp, the wax seal, the library card itself. A flame
would be a fifth, borrowed, competing with four that fit. So the counter's glyph
was the stamp, the celebration a stamp pressing into the card, and a milestone a
**wax seal** in the vocabulary `card-seal` established.

**The counter now draws a flame, and the mockup set draws it everywhere the run
is named.** What changed the answer is a different question. The stamp is the
right metaphor for _the act_ — a day being recorded — and the wrong one for _the
kind of number_. A reader glancing at `▣ 11` in the library bar cannot tell
whether 11 is books, days, or unread somethings; `🔥 11` is legible at a glance
in a way no invented mark is, because it is the category's one piece of shared
vocabulary. The stamp keeps everything it was good at — the day cell in the
month grid, the celebration's ink, the card — and the flame does one job: it says
_this number is a streak_.

So the division is: **the flame names the run, never a day.** A day is a stamp; a
run is a flame. `verify.py` asserts that boundary directly (no flame inside a
`.cday` and none in the card's stamp row) rather than trusting the prose.

The glyph is **Phosphor Fill's `fire`, U+E242** — not a lookalike. Two findings
worth keeping:

- **`phosphor_flutter` cannot be imported on this SDK.** The package declares
  `class PhosphorIconData extends IconData`, and `IconData` is `final` as of
  Flutter 3.44, so any file that imports it fails to compile. That is why the
  dependency sat in `pubspec.yaml` unused. The way through is to skip the
  package's Dart entirely and name the font directly:
  `IconData(0xe242, fontFamily: 'PhosphorFill', fontPackage: 'phosphor_flutter')`.
  The font assets ship from the package's own `pubspec`, so nothing has to be
  declared or vendored. **Do not re-add the import.**
- The mockup's flame is the font's own outline, extracted from
  `Phosphor-Fill.ttf` with fontTools, so the drawing and the app cannot show
  different shapes. `verify.py` pins the codepoint in both directions.

`share_card_page.dart`'s `Icons.local_fire_department` is left alone: it is the
candlelight toggle, a different job with a different subject.

### Six moments, because a number is one sixth of the feature

Duolingo's streak is not a number, it is a set of moments. All six are drawn over
the library _in situ_, because a celebration you cannot see the context of is a
screen nobody can judge.

1. **`sc-increment` — it went up.** Big figure, and the week row underneath doing
   the real work: today's cell has just inked in, tilted and scaled, so the eye
   lands on _what changed_ rather than on the total. Deliberately absent:
   confetti, sound, a share prompt, and any second call to action.
2. **`sc-milestone` — the seal.** Day 30 presses a wax seal onto the library
   card. It is worth more than a bigger number because it **persists**:
   tomorrow the streak is 31 and the seal is still there, so the reward is not
   spent the instant it is shown.
3. **`sc-risk` — the evening warning, amber and never red.** Nothing has been
   lost yet, and red at 21:00 punishes something that has not happened. It
   states the deadline rather than the threat ("today counts until 4am"), and
   its one button **opens the book** — it offers the act, not the anxiety.
4. **`sc-freeze` — a forgiven day.** The single most important mechanic in the
   feature, because people do not break streaks gradually; they break one and
   stop caring. Drawn as a dashed cell so forgiven never reads as read. Earned,
   never bought — there is nothing to sell here and no gems.
5. **`sc-broken` — it ended, and the record survives.** The figure shown is
   **the record (31), not a zero**. No red, no broken-flame illustration, no
   guilt copy. The repair offer is honest — "I read Tuesday — fix it" writes a
   real row for a real day — and is never a purchase.
6. **`sh-bar` — the chip**, the only one of the six a reader sees every day.

### The month is a ligature, not thirty stamps

The detail the exploration missed for twelve versions, and the one that changed
the `book_id` answer. On the reference's streak screen **consecutive days are
joined into a single continuous capsule**; they are not drawn as separate marks.
Thirty isolated stamps read as confetti. A ligature reads as a thread, and a gap
in it reads as a cut — which is exactly the feeling a streak is supposed to
trade on, achieved by drawing rather than by copy.

Consequences, all drawn in `streak-flows`:

- **A freeze does not sever the run.** It sits inside the capsule as a hollow,
  dashed overlay, so the thread continues while the record still refuses to claim
  the day was read. This is the visual form of the `kind = 'freeze'` decision.
- **Two figures, both true, both printed.** The run is 12; the days actually read
  are 11. The month prints "11 days read" and the header prints "12 days in a
  row", and a reader who notices the difference has understood the freeze.
- **Today is a rule down the leading edge**, never a fill — today is not an
  achievement yet and must not be drawn as one.
- **Runs break at week boundaries.** A run crossing Sunday into Monday is two
  capsules; a run crossing September into October is two screens. The reference
  lives with the first and so must this. The second is listed as open, because a
  card that pages by month can never draw the 400-day streak it celebrates.

And then the colour of the capsule is the whole `book_id` argument. Same days,
same run, same streak:

| variant     | what the month is                                   |
| ----------- | --------------------------------------------------- |
| `cal-plain` | a tally. Handsome, and mute.                        |
| `cal-books` | a history: five days on one book, three on the next |

The second costs one nullable column, no new table, no new interaction and no new
screen — `books.cover_color` is already stored. Its honest costs are a legend
(which the plain variant does not need) and a darkening pass for near-white
jackets. Geometry is derived from the card's own interior: seven cells and six
5pt gaps fill 325pt exactly, asserted.

## The position control

### The wheel spins percent, always

One native wheel. No chips, no rail, no unit segment, no page/percent toggle.

The arithmetic that decides it — a Cupertino wheel moves roughly **10 stops per
flick**:

| book                  | stops on a page wheel | flicks end to end |
| --------------------- | --------------------- | ----------------- |
| 320 pages             | 320                   | ~32               |
| 912 pages             | 912                   | **~91**           |
| **any book, percent** | **101**               | **~10**           |

A control that is comfortable at 320 and absurd at 912 is not one control; it is
a control with an undrawn limit, and long books are not rare. Percent is
**101 stops for every book ever printed**, and the page appears underneath as a
derived label:

```
label = "≈ p." + round(progress × page_count) + " of " + page_count
```

At 47% of 912 that reads **p.429**. (The drawing once typed `p.431` in the prose
beside a control drawing `429`; the verifier now asserts the two agree.)

Three problems dissolve at once, which is the sign it is the right answer: no
unit segment, because percent _is_ the unit; **no fallback for the 65% of
reading books with no `page_count`**, because the control never needed one; and
no resolution cliff, because the range is constant. The majority case stopped
being an exception and became the plain case.

The cost, stated: 1% of a 912-page book is 9 pages, so a reader who knows they
are on page 431 exactly cannot say so. They get 47%. That is a cost of the
storage decision, not of the wheel — the fraction is what is stored, and the
page was always a display layer.

**And the cost is visible, not merely theoretical.** Because the band and the
wheel are on screen together, a page that does not sit on a stop prints itself
twice, differently. `p.148` of 320 is 46.25%, which the band rounds to `46%`;
open the wheel at `46%` and its rider derives `≈ p.147`. Nothing moved, and the
reader's page number went down by one. The mockup drew exactly that for a while —
`p.148` in the band above `p.147` in the sheet — and it reads as a bug rather
than as arithmetic.

Two consequences worth holding onto. First, the drawings should use positions
that survive the round-trip (the bar group now uses `p.147` throughout) so a
frame never shows two page numbers for one position. Second, and for the build:
**`progress` should be written only in whole percent**, since a 101-stop wheel is
the only writer. Then `round(progress × page_count)` is stable, the band and the
wheel always agree, and the granularity is confined to one honest statement —
at 320 pages a stop is 3.2 pages — instead of leaking out as a number that
changes when you look at it.

**Rejected: a two-column hundreds/units wheel.** It brings 912 stops down to 10
and 100 and it is the wrong answer: it turns one gesture into two aimed gestures
with an arithmetic step between them (the reader must decompose 431 into 4 and 31
before spinning anything), page 507 invites landing on 5 and 7, and it cannot
represent a book with no page count — two in three of them. Drawn as
`sc-wheel-split` so the rejection is on the record rather than asserted.

**Deleted: the `+10 / +25 / +50` delta chips**, at the user's request. The frames
remain browsable.

### The migration

```sql
alter table books
  add column progress real
  check (progress is null or (progress >= 0 and progress <= 1));
```

- **`progress`, not `position`.** `books.position` is the shelf ordering index
  (see Context). Reusing the name would reorder shelves.
- **`real`**, not `numeric`: the wheel has 101 stops, so four bytes is ample and
  the precision conversation is moot.
- **Nullable, and null ≠ 0.** Null means "never set", so the ribbon stays at the
  pin it has always been drawn at; `0.0` means "at the very start", so the ribbon
  sits **at the gutter**. Collapsing those would put a bookmark at page one on all
  109 reading books on day one.

  **The same rule governs the bar and _not_ the row, which is a distinction worth
  stating because it was got wrong once.** Null draws **no bar**: an empty track is a
  _claim_, that the reader began and got nowhere, and every book in the library would
  make it the day this shipped. The band's progress **row** still renders, as
  `How far in? ›` — a prompt claims nothing, and it is the only door to the wheel the
  band has. Gating the row on the same condition as the bar left the first set with no
  door at all and, since the streak chip hides at 0 too, made the whole feature
  invisible on a fresh install. See the plan's build log for the 40pt that costs.

  > **Corrected 2026-09-17.** This bullet used to read "the ribbon sits at the
  > top", which is prose left over from an abandoned encoding — an earlier draft
  > made the mark's _length_ carry the position, hanging it further down the page
  > the deeper in you were. The chosen anatomy is `top-edge-slide`: the mark keeps
  > its size and slides **across the cover's top edge, spine to fore-edge**, which
  > is what a bookmark in a closed book does and is the only encoding that cannot
  > reach the shelf label or the band. Null returning the _far_ end of that track
  > rather than the near one is deliberate: every book in the library has a null
  > position the day this ships, and a mark that jumped to the gutter would redraw
  > every reading shelf to announce that the app knows nothing.

- No backfill. There is no data to backfill from.

### Where the control is reachable from

**From the state sheet's "How far in?" row, and the wheel is not a new control.**
`showSelectDateBottomSheet` already establishes the pattern this uses verbatim:

- `CNBottomSheet.show` wrapping a `SizedBox(height: 320)`;
- a header row at padding `20/16` — the title in `AppTextStyles.subtitle`, beside
  an `ElevatedActionButton` of **width 92, height 32**, labelled `confirm`
  (92 because 60 clipped the label to "Co…", per its own comment);
- `Expanded(child: CupertinoDatePicker(...))`.

This design substitutes `CupertinoPicker` for `CupertinoDatePicker` and supplies
101 items. **Nothing else changes.** So a reader picks their position exactly the
way they already pick every date in the app, and the only new code is the item
list and the derived-page rider under it.

That also disposes of the "bespoke drum" every earlier version drew, and of the
question of where the wheel is reachable from: it is reachable from its field
row, like a date.

The one accepted cost remains that the position is only editable from the state
sheet, so a reader looking at the shelf must go through the book. Given the
nightly-path problem in "The cost, which is real and not yet solved", that may be
revisited together with it — they are the same question asked twice.

### And the second door: the progress row itself

The sheet is not the only reachable place, because **the position is already
printed in the band** — `p.147 / 320 ▬▬▬ 46%` — and that read-out was being
offered as if it were a door. Four treatments are drawn as
`bar-now / bar-a-naive / bar-a / bar-hint / bar-c-open / bar-d-sheet`.

The ergonomic case for using it, as arithmetic: the progress row is **333×30pt at
y392–422**, the pencil is **48×48 at x341–389** in the app bar. That is
**9990pt² against 2304 — over four times the area**, in the thumb's arc rather
than the top-right dead zone, for an act done ~30× per book against status
changes ~3×.

Three treatments, each drawn at rest **and** tapped, with costs derived rather
than asserted:

|                                 | at rest             | while editing   | what the tap does         |
| ------------------------------- | ------------------- | --------------- | ------------------------- |
| **A** field ground, 44pt row    | **+27pt** permanent | —               | opens the 320pt wheel     |
| **C** tap arms the row in place | **0**               | +40pt transient | nothing leaves the screen |
| **D** tap opens the wheel       | **0**               | 0               | opens the 320pt wheel     |

**A and D open the same sheet**, and that is forced rather than chosen:
`DateFieldRow` — the widget A copies — opens `showSelectDateBottomSheet`, and a
progress field's sibling of that is the percent wheel. So `bar-a-open` is
`bar-d-sheet` with 27pt of white ground behind it, most of which the sheet then
covers. **A is not a third option; it is D plus a permanent 27pt tax.**

(This was the group's own blind spot: A was drawn only at rest for as long as the
group existed, while C and D each had a rest frame and an opened one — so the one
thing A proposed, a door, was the one thing never shown. `verify.py` now asserts
every treatment draws its tapped state.)

Five things the drawings settled that the prose had wrong:

- **A costs 27pt, not 14.** `PROG_H` 30 is the _slot_ — a 17pt row plus the 13pt
  gap above it — so `44 − 30` double-counts a gap that does not disappear when the
  row becomes a field. The honest figure is `44 + 13 − 30`, and the tab strip goes
  422 → 449.
- **A only reaches 44pt if it also adopts `DateFieldRow`'s 15pt body.** v12 around
  the row's own 13pt type lands at 41 — still under the floor.
- **`DateFieldRow`'s ground is `surfaceVariant`, and so is the band**, so copying
  the idiom verbatim renders an _invisible_ field (`bar-a-naive` keeps that trap on
  the record; `bar-a` inverts to `surface`).
- **A's ground is already spoken for.** The read-only period card 4pt above has
  the _same_ white ground and the _same_ radius 10. So in this band
  white-rounded-on-grey does not mean "tappable" — the chevron is doing that work
  in all three treatments. A does not win by default if the chevron fails; **A
  fails with them.**

Drawing A's tapped state removed a whole branch: A is D with a 27pt surcharge, and
the surcharge buys a ground that means "read-only" 4pt higher up. A's last real
advantage over C and D is target size — 44pt against 30 — and that is available to
both for nothing by extending the hit area into the band's 16pt bottom padding.
**So A is out**, and the choice was C or D.

**Decided: D — the tap opens the wheel.** The reader chose the bottom sheet. The
argument for C (nothing leaves the screen; 40pt spent only while working) is real
but was outweighed by the sheet already existing, already being how every date in
the app is picked, and already being the pattern the state sheet uses. C's frames
stay browsable as the rejected inline path, and the objection it answered — that a
stray touch could rewrite a position — is answered differently by D, which cannot
change anything without a Confirm.

That settles the behaviour, and leaves exactly one question: **what the row looks
like at rest.** See below.

If a chevron on a 30pt row is _not_ a sufficient affordance, none of the three is
discoverable and the answer is something with more presence — which is the one
question here that a drawing cannot settle.

Whatever is chosen, **every treatment that makes the row a target must evict the
streak chip `▣ 12`** from it: a tappable row cannot contain a second, smaller
tappable object. The chip already has its permanent home in the library bar.

This does not reopen "one place to edit position". Whatever the closed state is, it
writes the same `progress` field the sheet's row writes; it is a second _door_, not
a second truth.

### The closed state, which is the whole remaining question

Once the tap opens the wheel, the only thing left to design is the row at rest. The
bar is the reason `bar-a` failed, and the reason is worth restating because
everything here is built on it: **the white radius-10 ground `bar-a` borrowed is the
ground the read-only period card already has 4pt above it**, so on this band "white
card on grey" cannot mean "tappable". A treatment either has to remove that
adjacency or stop relying on the ground.

Eight treatments are drawn as `cl-*`. Costs are the tab strip's movement, measured
in a browser (each restructures the band, so none is derivable from the tokens):

|                                             | cost     | target | verdict                                   |
| ------------------------------------------- | -------- | ------ | ----------------------------------------- |
| **4c `cl-edge-sec`** inked border + section | **22pt** | 44     | **recommended**                           |
| 4b `cl-edge2` inked border alone            | **0**    | 30     | free; target unsolved                     |
| 4 `cl-edge` straight hairline               | **0**    | 30     | superseded — invisible below ~8%          |
| 8 `cl-best` section + bookmark              | 22pt     | 44     | the no-`CustomPainter` alternative        |
| 1 `cl-section` grouped section              | 22pt     | 44     | the mechanism                             |
| 2 `cl-inline` same, no separator            | 21pt     | 44     | separator is worth its 1pt                |
| 3 `cl-cardfoot` card's edge is the bar      | 25pt     | 44     | handsome, dearest                         |
| 5 `cl-nub` bookmark on the fill             | **0**    | —      | the free fallback                         |
| 6 `cl-chip` value becomes a button          | 10pt     | **27** | wrong direction — pays for a small target |
| 7 `cl-wide` full-bleed row                  | **0**    | —      | 20pt misalignment; reads as a mistake     |
| — `bar-a` for comparison                    | 27pt     | 44     | ground already spoken for                 |

**Decided: the bar is LINEAR, at the band's bottom edge, and the progress row stays on
the grey band.** `ln-full` is the treatment as chosen: a straight 4pt fill running the
full 393, its ends clipped by the band's 30pt bottom radius.

I got this wrong once and it is worth recording. Having found that a linear bar below
~8% is entirely inside the corner radius (`cl-early-straight`, p.13 of 320, shows
nothing at all), I redrew it as a **stroke tracing the border**, arcs included
(`cl-edge2`), and carried that forward as the recommendation. That is a **different
look**, not a fix to the chosen one, and substituting it was not mine to do. The traced
frames stay browsable; they are not the decision.

**The low-end trade, stated rather than settled by fiat.** Two linear options:

|                                   | low end         | the look                              |
| --------------------------------- | --------------- | ------------------------------------- |
| **`ln-full`** full-bleed, clipped | blind below ~8% | runs edge to edge, into the corners   |
| **`ln-flat`** spans x30–x363      | visible at 1%   | 30pt of grey at each end; not an edge |

There is nothing in between, because _the clipping is the edge-to-edge look_. And
`ln-full`'s blindness is arguably fine: the numbers sit directly above the bar, so an
empty-looking bar beside a legible `4%` degrades gracefully rather than lying. The bar
is an ambient second reading, not the source of truth.

**DECIDED — the closed state is `pd-align`.** Four parts, and each was chosen
separately:

1. **Bar:** linear, 4pt, at the band's bottom edge, running the full 393 with its ends
   clipped by the 30pt corner radius. Not traced around the corners.
2. **Progress row:** unchanged from what ships in structure — `p.147 / 320` left, `46%`
   right — directly on the grey band, plus a chevron. Not wrapped in anything.
3. **Period card:** stays a standalone white card, and becomes a door. Its value is
   pushed right (`margin-left: auto`), chevron last, 44pt minimum. This is
   `DateFieldRow`'s shape verbatim.
4. **App bar:** `edit_outlined` removed. It opened `showBookStatusBottomSheet`, which
   edits status + start + finish — exactly what the period card displays — so the card
   replaces it. Only `delete_outline` remains.

`cl-edge-sec` and the `bd-*` group also exist and are **not** the chosen direction.
They wrap the progress row in a white grouped section, which changes a row that was
already settled — they were drawn while answering a question about the _period_ row,
which is not licence to redesign the other one. Kept browsable because the
grouped-list reasoning in them is sound and may be wanted later; labelled in the
mockup so they cannot be mistaken for the answer.

### If the traced border is ever revisited: its geometry

Not the decision — the bar is linear. Kept because the arithmetic was worked
out and verified, and because it is the only version with no low-end blind spot.

`book_details_tab_view.dart` gives that container
`BorderRadius.only(bottomLeft: 30, bottomRight: 30)` and
`padding: fromLTRB(30, 8, 30, 16)`. The path is built from exactly those numbers:

```
centreline radius = 30 − strokeWidth/2 = 28      (4pt stroke, sits inside the band)
path = quarter arc (44pt) + straight (333pt) + quarter arc (44pt) = 421pt
fill = extractPath(0, progress × 421)
```

**Flutter has no partial-stroke primitive**, so this is a `CustomPainter`: build the
path with `arcTo`/`lineTo`, then `PathMetric.extractPath(0, fraction * length)` for
the fill. Caps must be `butt` — round caps on a 4pt stroke read as a pill floating on
the border rather than as the border being inked in.

**Two cautions for the build.** The 30 must be a constant shared with the container,
not two 30s in two files: **21% of the path is corner**, so changing the radius
changes the progress geometry and reintroduces the low-end problem in miniature. And
derive the path length rather than fitting it — the arithmetic (421) disagreeing with
the browser's `getTotalLength` (392) is what caught a malformed arc, where the corner
y had been set to the radius instead of `height − radius`.

### The low end, which is the reason to trace rather than cross

Two states cannot occur, and being precise about them matters:

- **0% never happens.** `progress` is nullable and `null ≠ 0`, so a reading book with
  nothing recorded shows no bar, not an empty one.
- **p.1 never happens either.** Drawn there first, the row read `p.1 / 320` beside
  **0%** — 1/320 is 0.3% and rounds away. Since the wheel is the only writer and it
  spins whole percent, the smallest expressible position is **1%, i.e. p.3**, which is
  4pt of stroke rather than 1pt. This is the third instance of the quantisation
  artefact, and here the storage decision makes the display _more_ legible.

At 1% the stroke holds — and only because of the corner. The same length on a straight
bar would be indistinguishable from an aliasing error; in the curve it reads as the
very beginning of something. **The corner is not decoration; it is what makes the low
end legible at all.**

Three further findings from drawing the group:

- **Merging the two rows is cheaper than `bar-a`, not dearer** — 22pt against 27,
  because the 10pt gap between the two cards is reclaimed and spent on a 1pt
  separator. A better affordance for 5pt less.
- **The bookmark only works white.** Drawn as solid `brandText` its left half merged
  into the fill it sat on and it read as a blob. The cover mark is white with a dark
  edge; matching it (same notch polygon, outline as a layer behind since `clip-path`
  cuts a `border` off the notch) is what makes the shape legible.
- **Two treatments pitched as free were not.** `cl-chip` costs 10pt and its target
  is 27pt — under the floor, so it trades the discoverability problem for the Fitts
  problem, which is the wrong direction when the complaint that started this was a
  small target in an awkward corner. `cl-wide` cost 7pt until the full-bleed padding
  stopped being added on top of `.prog`'s existing margin.

### Decided: two chevrons, in one column

Both rows are doors, so both carry a chevron — dropping one from a row that _is_
tappable would misdescribe it. `ch-cardonly` draws that alternative and it fails plainly:
the progress row goes back to a read-out with no affordance, which is `bar-now` with
extra steps, and it hands the affordance to the act done ~3× a book while withholding it
from the one done ~30×.

**The question was never the count, it was the column.** The card is inset 10pt inside
the band, so its chevron lands at **x352** while the row's lands at **x362**:

- **`ch-stagger`** — both, 10pt apart. Reads as a misalignment. The same 10pt stagger
  exists on the left (`Reading` at x41, `p.147` at x31) and is invisible there, because
  those are different shapes at different sizes. **Two copies of one glyph is the single
  case where 10pt is obvious.**
- **`ch-column`** — both at x362. Aligned, they stop being two icons and become the
  right-hand edge of a list, which is the convention being borrowed and exactly why two
  chevrons are unremarkable in Settings. **Recommended.** Done by moving the _card's_
  glyph (`margin-right: -10px`), never the settled row.
- **`ch-quiet`** — both, column-aligned, at 14pt and half opacity. Differs from
  `ch-column` by weight alone. Only worth taking if the aligned version reads as
  cluttered on a device: the chevron is the _only_ thing saying either row is tappable
  (`pd-naive` proves arrangement alone does not), so quieting it weakens the single
  signal the design rests on.

Two open questions on `cl-edge-sec`:

1. **Does ink on the band's rim read as chrome?** It sits against the tab strip's
   white at 4pt, which is divider territory. Drawing the low end mostly answers it,
   and a truly empty track cannot occur. What no drawing settles is whether a reader
   who never reads the numbers notices the rim means anything — a real-device
   question.
2. **The merged section changes what the period row is.** Resolved — see below.

If the `CustomPainter` is unwanted, `cl-best` (grouped section plus the cover's
bookmark on the fill) is the fallback at the same 22pt, and everything in it is a box
and a `clip-path`.

### Decided: the period card is a door too, and the pencil retires

The mapping is exact: `showBookStatusBottomSheet` edits **status, start date, finish
date** and nothing else, which is precisely what the period card displays. So the card
opens the sheet it is the read-out of, exactly as the progress row does.

**The consequence is that `edit_outlined` has no job left.** Both things it edited are
now reachable from the band, so the app bar keeps only `delete_outline`. That is the
complaint this whole thread started from — a 48×48 target in the top-right dead zone —
solved twice over rather than once.

**And a chevron alone does not make the card look tappable.** Three treatments,
`pd-naive / pd-align / pd-press`, all on the settled layout — the progress row is
untouched in every one of them:

- **`pd-naive`** appends a chevron and changes nothing else. It still does not read as
  a door, and the reason is **grammatical**: the card's three pieces are packed at the
  left, so the chevron floats alone at the right with a void between — an ornament at
  the end of a sentence rather than the terminus of a label/value pair. The progress row
  below already has the right shape, which is why it reads as a door and the card
  doesn't.
- **`pd-align`** is the fix, and it is **one rule**: `margin-left: auto` on the value.
  Pill left, dates right, chevron last — which is `DateFieldRow`'s shape verbatim
  (white ground, radius 10, body left, value right), the app's own tap-to-edit row
  rather than a new pattern.
- **`pd-press`** darkens the card on press — the half no resting frame can show, and
  what teaches a reader the _card_ is the target rather than the chevron inside it. It
  must **not** darken to `surfaceVariant`, or the card vanishes into the band; `#f1f3f5`
  is distinguishable from both.

**The recommendation is `pd-align` + `pd-press`** — arrangement plus feedback, no new
words and no new chrome.

Note what stops applying here. `bar-a` failed because a white card on this band already
meant "read-only" — and that read-only card _was_ the period card. Once it is itself
the door, **there is no read-only white card left in the band** for it to be confused
with. The two doors are told apart by what they say, not by their grounds, and both
carry a chevron.

Two things measured rather than assumed:

- **It costs 2pt, not nothing.** The card draws **42pt**, so reaching the 44 floor
  costs 2. (I first claimed free, off a remembered 46 — that was the grouped-section
  variant, a different row.)
- **The two chevrons are 10pt out of column** — the card's at x352, the row's at x362,
  because the card is inset 10pt inside the band. The same stagger already exists on the
  left (`Reading` at x41, `p.147` at x31) and predates this work. Bringing them into
  column means giving the progress row 10pt of horizontal padding, **which is a change
  to the settled row**, so it is raised as a question rather than taken.

## Decomposition

Reordered by the state-sheet merge: the sheet is now the spine of the work, and
almost everything hangs off it. Each step is independently shippable.

1. **Migration A** — `reading_days` plus its RLS policy. `kind` is provisioned
   and unused. No UI.
2. **Migration B** — `books.progress`. No UI.
3. **`readingDate`** — the 4am-rollover local date, and its tests. Pure function,
   no I/O, and everything else depends on it.
4. **The position row + wheel.** A `ProgressFieldRow` beside `DateFieldRow`, and
   `showSelectPercentBottomSheet` beside `showSelectDateBottomSheet`. Added to
   `showBookStatusBottomSheet` at `status == 1`, written by the existing Save
   through `updateBookStatus`. **Ships alone and is useful alone — no streak
   involved**, and it is the whole of the risk-free half of this design.
5. **The ribbon reads `progress`** on the detail cover, `shelf_row` and
   `card_cover_row`. Display only.
6. **The day checkbox** in the same sheet, writing one `reading_days` row on Save.
   Idempotent by primary key; optimistic local write with an offline queue.
7. **The derivation** — current run and longest run, client-side over the
   trailing rows. Read-only over step 6.
8. **The chip** in the library bar, four states, tapping through.
9. **The streak `StatTile`** on the Library Card, omitted when there is no run.
10. **The month grid**, once it has a destination — see "The month grid has no
    home yet". Blocked on that decision, not on code.
11. **The moments** — `sc-increment` first, then `sc-risk`, then `sc-broken`.
    `sc-milestone` needs the ladder decided.
12. **Later: freezes.** `kind = 'freeze'`, the allowance, and the forgiven-day
    drawing. Explicitly out of the first cut.

Steps 1–5 are safe and self-contained. Step 6 onward is the part the corpus says
may not pay. **The cheap nightly path is not in this list** because it is not yet
decided; it slots in beside step 6 and must write through the same call.

## What is built, and what is still only drawn

**Steps 1–9 shipped earlier. Steps 10 and 11 are now built, and the two comparisons
that were blocking them are decided: the month's tone is `patch`, the picker is
44×66.** What exists in Dart, with the deviations from the drawings stated rather
than quietly absorbed:

- **`lib/ui/pages/reading_streak_page.dart`** — the destination. A full-screen cover
  on `AppRoutes.readingStreak`, generated in `onGenerateRoute` beside the scanner and
  the share card because it wants their transition and their ✕. The chip's `onTap`
  pushes it, which **retired the stopgap** that switched the library's tab to the
  Library Card; `reading_streak_chip_test.dart` carries the reversal.
- **`lib/ui/widgets/streak/read_calendar_month.dart`** — the month, at the `patch`
  tone. `readCalendarPatchTilt` is the _only_ definition of the rake, so a Library
  Card month must call it rather than restate the arithmetic. Geometry is derived from
  the width it is given; the only typed number is the 5pt gap.
- **`lib/ui/widgets/streak/read_week_row.dart`** — the week, drawn once for two
  surfaces. The page and the celebration both needed the same seven days, in two
  palettes, and two copies is how the week behind a celebration and the week inside it
  come to disagree about which days are in. It therefore takes its palette from the
  caller rather than reading the theme — the celebration paints its own cream
  ground, where `context.colors` would hand back white type in dark mode. The rake is
  keyed off the **date**, not the cell's index: off the index, every cell would be
  re-raked at midnight as the days shuffled left. Tilt is off in the celebration, where
  exactly one cell is allowed to arrive crooked.

### The fidelity pass, and five things the first cut got wrong

**Both drawings were built and then compared with the frames side by side, and the week
row did not survive the comparison.** This is the section that exists because “looks a
bit different” is a judgement no widget-test expectation settles, and because every one
of the five was invisible to a green suite.

1. **The week row drew a box on all seven days.** `.lweek` draws an outline only where
   something happened or is about to: a stamped day is a wash inside a 1.5px edge, **today
   before you read is that edge dashed** — the affordance, since the tap is what stamps it
   — and a missed day gets **no box whatsoever**, only the 1px baseline the row shares.
   Seven boxes reads as seven empty checkboxes and throws away the one signal that says
   _this one is waiting for you_. The dashed state could not even be expressed: the widget
   took a `(mark, ink)` pair, which spells “stamped in some colour” and “not, in some
   ink”, so an unrecorded tonight and a missed Monday were the same cell. It now takes a
   nine-role `ReadWeekPalette`.
2. **Its cells were 30pt squares, spaced apart.** `.lweek s` is `flex: 1` at `height:
34px`, so a cell is **wider than it is tall** and the seven share the content width.
   Squares left a third of the row as gap.
3. **The month's patch was inset a point on all four sides.** `.cal.tone-patch .cmk` is
   `left/right: 1px` against `top/bottom: 6px` with a **7pt** corner — on a 42pt cell a
   40×30 block. A uniform inset with a 2pt corner is a near-square tile, and a run of
   tiles is a chart rather than tape pressed on by hand. This is the one the reader asked
   about, and the shape was most of the answer.
4. **The month was missing three of its own states.** The weekend columns take a 5% wash
   — one box per column _behind_ the grid, because painted per cell it sits over the
   patches and a run appears to change colour on a Saturday. A past day with nothing on it
   now carries a hollow 4pt dot, where before it was drawn identically to next Tuesday, so
   the one thing the grid exists to show — where the thread broke — could only be found by
   counting. And the card carries the record's second stat tile, `N days read this month`.
5. **The celebration's closing cell was a brighter stamp.** `.lweek s.fresh` _inverts_ —
   solid fill, reversed-out letter, lifted by its own shadow. Against six neighbours
   already in the accent colour, a seventh in the same wash is not somewhere for the eye to
   land, which is the entire point of that beat.

**Three reversals, recorded rather than deleted.**

- **Today's rule in the month is `flame`, not `brandFill`.** It shipped green on the
  reasoning that green is how the app marks its own things. The record draws it amber, and
  the record is right twice: `flame` exists for exactly one purpose — to be the one warm
  hue in an all-green palette — the run above this grid is already drawn in it, and a green
  rule competes with a green patch on any day whose book has a green jacket.
- **The legend is spines, not swatches.** A 12pt swatch in the patch's own 22%/50%
  grammar was the obvious choice — make the key look like the thing it explains — and it is
  wrong twice: at that size a fifth-strength wash is barely a colour, and the app's entire
  vocabulary for _a book_ is a cover seen edge-on. Each entry is now a 5×15 spine at full
  strength and the row wraps, so four books is a line and a half rather than four rows of
  mostly empty space.
- **The celebration's fresh cell arrives at −4°, not 14°, and its letter is the candle's
  brown rather than its cream.** The steeper angle was argued as “this one is being pressed
  on in front of them” and next to six square neighbours it read as a layout bug; the
  record's own `fresh` is `rotate(-4deg) scale(1.12)`. The cream letter was a straight
  mistake — the record inverts to white on `brandText`, a _dark_ green, and
  [`kCandleFlame`] is a mid amber, so cream on it was barely a letter.

**And three places the record was not followed, on the app's own authority.**
`test/text_style_test.dart` forbids a call site stating its own `fontSize` or
`fontWeight`, on the grounds that needing a size the scale lacks means the scale is wrong
rather than that the call site needs an exception. So: the record's `font-weight: 800` on a
stamped numeral is dropped (`label` is the only token with tabular figures, and the patch
plus the ink already say which days are in); `.lweek`'s bold-vs-normal split between a
stamped and a missed letter is dropped for the same reason, with the colour gap carrying
it; and the month card's heading is `subtitle` — 17pt **sans** — where `.cnav b` is 15pt
Georgia, because the scale's serif runs `spine` 12 then `titleVisit` 20, and 12 would put
the card's heading below its own 13pt stat figures while 20 beside them is a shout. Worth
revisiting if the scale ever grows a small serif head.

**One thing in the record's month is deliberately absent: the ‹ › pagers.** They imply
`readingDaysProvider` can be asked for an arbitrary month, and it cannot — it holds one
window. Drawing the control before the query exists is an affordance for something that
does nothing, which is the same mistake a grab handle on this page's cover would be.

- **`lib/ui/widgets/bottom_sheets/pick_reading_book_sheet.dart`** — step one of the
  pair. **One deviation, and the app's own rule forced it:** the drawing puts the
  library's real cover on the row, and `BookWidget`'s coverless fallback prints the
  title on the jacket. At 44pt wide that title sets at 5.9pt — under
  `kGeneratedCoverMinWidth`, which exists to document exactly this smudge. So the row
  draws the colour block alone, the way `CardCoverRow` and the add-book sheet's owned
  rows do. That is also what the drawing asked for on its own grounds ("the jacket
  stays untitled"), so the two agree; it is written down because the reason is the
  constant and not the drawing.
- **`lib/ui/widgets/streak/streak_celebration.dart`** — the moment. **Deviation:** the
  spec says implicit animation only, and this uses one `AnimationController` with nine
  `Interval`s. Implicit animations have no delay, so a nine-beat stagger means nine
  `Future.delayed` calls, each of which has to be cancelled on dispose; one controller
  is core Flutter, is a single thing to dispose, and puts the timings in one readable
  place. The `MediaQuery.disableAnimationsOf` gate is honoured as specified, and by
  jumping to `value = 1` rather than running faster.

### The increment choreography, and why there is no Rive in it

**The reference is Duolingo's streak increment, decomposed beat by beat.** Its published
structure is an ignition from a dormant grey flame to a vibrant one with spark particles, a
number that rolls with a spring overshoot, a diagonal shimmer sweep across the icon, then a
staggered reveal of the week and the button. Every one of those is a transform, a colour
tween or a gradient. **None of it is character animation** — which is the one thing a vector
runtime would be needed for, and the one thing that only appears in Duolingo's _milestone_
takeovers, where a mascot fractures out of an egg.

So the increment is built in Flutter, inside the controller that already existed:

| Beat                    | ms       | What it is                                                                                                                                                                      |
| ----------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ignition                | 0–520    | scale 0.4→1 on `easeOutBack` — already the overshoot, so one tween rather than a `TweenSequence` — with the colour flooding from dormant to [`kCandleFlame`] over the first 55% |
| Bloom                   | 60–760   | a [`kCandleFlame`] radial halo that flares to a third strength and settles at a sixth                                                                                           |
| Sparks                  | 120–720  | 14 embers on a `CustomPainter`, thrown in a 250° fan, gravity-pulled, faded to nothing                                                                                          |
| Counter                 | 300–860  | rolls `streak - 1` → `streak`                                                                                                                                                   |
| Gleam                   | 620–1000 | one diagonal `ShaderMask` pass, `srcATop`                                                                                                                                       |
| Label, week, bar, stamp | 700–1500 | unchanged                                                                                                                                                                       |

Total went 1360 → 1500ms.

**Three decisions inside that are worth the words.**

- **The ignition is the streak page's own rule, animated.** `_Hero` already tints the flame
  `secondaryText` while the day is open and `flame` once it is in; the celebration's first
  beat is that same transition happening rather than a new idea. The dormant tone is the
  copy's brown at a third strength, **not a grey** — Duolingo desaturates against white, and
  a true grey on this cream ground reads as a hole rather than an unlit wick.
- **The counter's spring is positional, never numerical.** Two animations share one window:
  the value rides a monotonic `easeOut` and the figure's offset rides `easeOutBack`. A back
  curve on the value would print `13` and take it back, which is a lie in the only place on
  the screen that states a fact. It also _drops_ from above where the label, week and bar all
  rise from below — which is what marks it as the subject rather than another row.
- **The sparks are seeded from the run**, for the reason `readCalendarPatchTilt` is derived
  from the day: a re-roll on every paint cannot be told from a regression. The first cut
  spaced them evenly over a full turn and drew a mechanical starburst — and its comment
  claimed a fan while the code drew a ring, which is the failure mode this record exists to
  catch. Found by rendering a filmstrip and looking at it.

**Why no `.riv`.** Beyond having no mascot — and `docs/mockups/empty-states/PROMPTS.md`
records what producing art for this app costs — a vector blob is un-greppable and
un-diffable in a codebase whose whole discipline is that a claim can be read, and its timing
would live in an external editor where no `Interval` can. It also breaks two things this
screen honours on purpose: `disableAnimationsOf` would need the artboard seeked to its last
frame by hand, and _nothing moves once the last beat lands_ — which is why the flicker here
is part of the arrival and there is no idle loop. And the flame is
`kReadingStreakIcon`, a font glyph chosen because the chip needs it in two tints; a second,
vector flame is exactly the drift `reading_streak_chip.dart` already warns about for the
share card's.

### Reversal: Rive ships after all, for the flame only

**The judgement above was overruled, and it deserved to be.** The hand-built version was
reviewed side by side with Duolingo's and it is not close. The diagnosis is worth keeping
because only half of it was about the runtime:

- **uniform scale only.** Ignition was `Tween(0.4, 1)` on the whole glyph. Fire animation is
  squash-and-stretch — `scaleY` leading `scaleX` — and a uniformly growing silhouette is a
  sticker, not a flame catching;
- **a flat single-colour fill.** `kCandleFlame` is one mid-amber. Fire is a gradient. The
  `ShaderMask`/`srcATop` technique needed for it was _already proven in this file_ by the
  gleam and simply not used for the fill;
- **`easeOut` over 300–700ms windows**, which is the grammar of fading in. No impact frame
  anywhere;
- **timid values.** A glow peaking at 0.30 alpha and 1–3px embers read as dust.

The first three are fixable without Rive. What is **not** fixable is that
`kReadingStreakIcon` is one path in one colour: it can be scaled non-uniformly, gradient-
filled and stacked, but the path cannot **deform**, and a flame tip that licks and curls is
where the life is. That is an _asset_ limit, not a runtime one — which is the distinction the
first judgement missed.

So Rive ships, on four conditions that answer every objection above rather than ignoring it:

1. **Rive draws the flame and nothing else.** The counter, week row, milestone bar and every
   line of copy stay in Flutter. Localised strings and themed colours do not go in a binary.
2. **Flutter keeps the clock.** The artboard does not autoplay; it exposes one bound Number,
   `progress` in 0–100, scrubbed from the existing controller. The nine beats stay in Dart,
   `disableAnimationsOf` needs no special case, and frame 100 is a _resting_ frame — no idle
   loop on a screen a reader opens nightly.
3. **The absence of the artboard costs nothing.** `StreakFlame` resolves the file itself and
   renders the hand-built ignition when there is none, so the hand-built version is not thrown
   away — it becomes the fallback.
4. **The increment only.** A milestone takeover with a character would get its own artboard
   and its own file.

**And a bug found doing it, worth writing down:** `RiveWidgetBuilder` documents a `RiveFailed`
state, and **a missing asset does not reach it** — `FileLoader.file` throws
`RiveFileLoaderException` out of `initState`, which takes the subtree down. Handing it the
asset name broke fifteen cases the moment it was wired in. `StreakFlame` therefore calls
`File.asset` itself and treats every failure as an ordinary `null`.

The build sheet — artboard size, the palette taken from shipped tokens, layer order, and the
timeline keyed against `progress` — is `docs/streak-flame-rive.md`. The drawing is a book laid
with its spine along Z, seen from the tail edge, its covers splaying and a flame rising out of
the gutter along +Y.

`rive 0.14.11` pulls `rive_native`, which integrates through **SPM** rather than CocoaPods —
the same route Firebase takes here, so `ios/Podfile.lock` never mentions it and the
`RiveNative_ios.xcframework` lands in `build/ios/SourcePackages/artifacts/`.

### Reversal: a `.riv` _is_ authorable from a terminal, and this one is

**The paragraph above used to say the file could not exist yet, "because a `.riv` cannot be
authored from a terminal: it is a binary the Rive Editor produces, with no CLI and no public
serializer". That was simply wrong**, and it was wrong in the expensive direction — it turned
a solvable problem into a hand-off, and it justified writing a build sheet addressed to a human
with an editor. There is a first-party CLI, `rive`, already installed at
`/opt/homebrew/bin/rive`; it compiles a directory of plain text into a `.riv`.

So the asset's source is **committed markup**, `rive/streak_flame/scene.rml`, and
`assets/rive/streak_flame.riv` is a build artifact of it produced by
`rive/streak_flame/build.sh`. That voids the original objection to Rive rather than tolerating
it: the complaint was that a binary blob is un-greppable and un-reviewable, and a text scene
with a one-command build makes a geometry change a diff.

Three tools, and none of them is a superset of another:

|                              | catches                                                  |
| ---------------------------- | -------------------------------------------------------- |
| `rive . --verify`            | Luau and shader compilation; exits 1 on error            |
| `rive inspect . --summary`   | bind paths, state machines, and the only `problems` list |
| `rive/streak_flame/sheet.py` | **whether the drawing looks like anything**              |

The third is the one that mattered. The scene passed `--verify` and `inspect` with zero
problems on the first attempt and still drew: the pages **behind** the covers, so the book read
as a dark mountain with a cream sliver; an **egg** instead of a flame, four mirrored vertices
having no tip; and a **black peg** where the gutter poked out below the flame's base. None of
those is a structural error. `--advance=1` is mandatory on a screenshot — without it every
frame is the authored rest pose, and six identical renders look convincingly like a working
filmstrip.

Four things the drawing taught, in the order they were found:

- **Opening is `scaleX`, not rotation.** A 2D rotation pivots about a point, and a half's inner
  edge is not a point but the gutter _line_, which recedes. Rotating the halves swung their
  far-inner corners across the centre line and the book crossed into a bow tie. Anchored at
  the gutter, `scaleX` 0.54 → 1.0 is also the physical truth: a shut book seen down its spine
  is one board wide and an open one is nearly two.
- **The crease is the darkest part of an open book, not the brightest.** Lighting the pages
  outward from the gutter — on the reasoning that the flame is the light source and the gutter
  is nearest it — put each half's brightest pixel against `x=0` and drew a pale needle down
  the middle of the book. Two pages meeting in a valley shade each other.
- **A flame is widest a third of the way up.** Correcting the egg overshot into a tulip,
  because the widest point sat too low and the base was as wide as the shoulders, so the
  silhouette flared, pinched to a waist and flared again.
- **Embers may not wear the flame's own colour.** Half the fan sits in front of the flame
  body, and sparks painted `flame` #B54708 over a body that runs to #B54708 were invisible —
  the burst looked left-weighted for weeks of nothing but that.

### Two runtime defects the artboard exposed, both worse than the bug they replaced

Neither of these is about the drawing, and both were found only by putting the file in place.

**`Factory.rive` aborts the process.** The Rive Renderer wants a GPU context, and a headless
`flutter test` shell has none, so `File.asset` trips a native assertion — `Assertion failed:
(factory)`, `file.cpp:206` — and the shell dies with SIGABRT. That is not catchable: the
`catch` in `StreakFlame._resolve` never runs, the whole test file reports `did not complete`,
and every case in `streak_celebration_test.dart` goes with it. `Factory.flutter` draws through
Flutter's own canvas and needs no context; for a dozen paths with no meshes, images or scripts
the Rive Renderer was buying nothing that would pay for a crash on a screen presented over the
streak page.

**A 1D blend state never stops advancing.** `RiveWidgetController.advance` returns
`didAdvance && active`, and a blend state reports itself as always advancing, so with `active`
left at its default the ticker runs forever — a 60fps repaint on a screen a reader opens
nightly and then leaves sitting there, which is precisely the idle-loop cost condition 2 was
written to forbid. It surfaced as `pumpAndSettle timed out` the hour the `.riv` landed.
Clearing `active` does not stop the drawing being drawn: `active` gates the ticker, the hit
test and the pointer handlers, not `paint`. And the state machine registers `scheduleRepaint`
as an advance-request listener, so writing `progress` asks for a frame by itself — one frame
per change, stillness in between, which is the contract the poses were already written to.

### Which flame a test sees is a property of the machine, so tests may not leave it to chance

`rive_native`'s dynamic library is downloaded by `dart run rive_native:setup` into `build/`,
and **`build/` is gitignored, so it does not travel between worktrees** any more than `env.json`
does. A fresh checkout therefore has the `.riv` and no library to read it with: `File.asset`
fails, the fallback draws, and that is correct behaviour rather than a broken test. Without
the library the failure is _printed_ rather than thrown, so the graceful path really is
graceful — but it means the three cases in `streak_celebration_test.dart` that assert the
hand-built choreography (the glyph's colour as it catches, the spark painter, the gleam's
`ShaderMask`) pass on a machine that has not run the setup and fail on one that has.
`debugStreakFlameAssetOverride` settles it by pointing the widget at a name that cannot
resolve. `streak_flame_test.dart` covers the other side, and its one case that needs the
library skips itself with a reason where there is none.

Verified: 1766 tests pass, `flutter analyze` clean of errors and warnings, iOS builds and
launches.

- **`reading_days` carries its book.** `ReadingDaysNotifier`'s state went from
  `Set<DateTime>` to `Map<DateTime, String?>`, because the month colours each night by
  its book and a second provider reading the same table is two answers that can
  disagree about a day just written. `currentReadingRun`/`longestReadingRun` now take
  an `Iterable`, which cost nothing — they already rebuilt a normalised set internally.
  `setRead` also stopped early-returning on membership alone: re-recording a day with a
  _different_ book is a correction a reader has to be able to make, and it now sends
  `book_id` even when null so that correction can clear it.
- **`LibraryActions.recordReadingPosition`** — a second, narrow way to write the
  bookmark. `updateBookStatus` could not be reused: it _derives_ `start_date` and
  `finish_date` from the status, so calling it to record a position would throw away
  the date the reader started the book.
- **`onConfirmed` on `showSelectPercentBottomSheet`** — new, optional, and the pair
  needs it. `onProgressSelected` is gated on `_touched` so that agreeing with a
  pre-filled wheel rewrites nothing; but from outside, "confirmed without moving the
  wheel" and "swiped the sheet away" then look identical, and treating the first as a
  dismissal would refuse to record a night the reader just confirmed.

**Two things in the drawing are deliberately absent from the build.** The page's bar
draws a **Share** action beside the ✕, and there is nothing behind it: `cp-d-page`'s own
note puts a share row in the page's slack "if either ships", so the bar's affordance is
the drawing getting ahead of itself. A button that shares nothing is worse than no
button. And the footer's done state is **not** the primary button read back: the first
cut put "Undo today" in the green CTA slot, which advertises taking the night back as
the thing to do next. What ships is the drawing's own `sgo2 done` — a confirmation that
today is recorded, with the undo as a quiet secondary inside it.

**Deliberately not built: the cover's long-hold menu** — the second, shorter door.
The page is the door that shipped. The menu is still _open_ in the record rather than
decided: `cp-b-drag` names three unresolved implementation questions (what slop
commits the drag, where the menu lives given that `onDragEnd` fires while it must stay
up, and what becomes of `BookWidget`'s existing turn-and-unwind), and answering them
means moving the edit-mode commit inside `shelf_row.dart`'s `LongPressDraggable` — the
most delicately documented gesture in the app, and the one that owns cross-shelf
reorder. Deciding those three by implementing them is not a thing to do in passing.

## Testing

- **`readingDate`** — 23:59, 00:00, 00:30, 03:59, 04:00; a DST boundary; a
  timezone change between two consecutive calls.
- **Idempotency** — stamp twice, assert one row. Replay a queued offline write
  twice, assert one row.
- **Undo** — stamp, unstamp, assert zero rows and that the derived streak fell
  from 12 to 11 in the same frame.
- **Derivation** — an empty history (0); today only (1); a run ending yesterday
  (counts); a run ending two days ago (0, and the record survives); a run
  spanning a freeze; two runs, asserting the longest is the max and not the
  latest.
- **Isolation, the point of the whole design** — stamping asserts `progress`,
  `start_date`, `finish_date` and `status` are all untouched; setting `progress`
  asserts no row appears in `reading_days`.
- **The label** — `round(progress × page_count)` agrees with the wheel's
  percentage; the label is absent when `page_count` is null.
- **Layout** — the band with the "Today" chip measures 160 and the tab strip
  sits at 424; the chip's label does not wrap at the largest supported text
  scale, since the wrap is what costs 32pt.
- **`verify.py`** stays green (385 checks) for as long as the drawing is the
  reference.
- **The fidelity pass has its own cases**, because every one of the five defects it
  found sat happily under a green suite. `read_week_row_test.dart` pins that a missed day
  has _no_ box (only the shared baseline), that exactly one cell is dashed and only when
  today is unrecorded, that `freshLast` inverts the closing cell, and that the seven cells
  share the width rather than leaving a third of it as gap. `read_calendar_month_test.dart`
  pins the patch's 40×30-at-42pt aspect and its 7pt corner, the hollow dot on a past
  unrecorded day _and its absence_ on today and tomorrow, the weekend wash running the
  height of the grid rather than of one cell, and today's rule being `flame`.
  Its palette fixture is deliberately nine implausible colours: when the roles were two,
  “stamped in the caller's colour” was all a case could say and the box-on-every-day bug
  satisfied it perfectly.

One non-automatable rule that caught every real defect in the drawing that the
checks missed: **one value, printed once.** `72% … 72%` in the band and `12`
above "12 days in a row" both shipped into the mockup and were found by eye.

And a second one, which the fidelity pass above is the whole argument for: **build it,
then put the frame and the build side by side and look at them.** Five defects, a green
suite, and `verify.py` clean — because every check was written against what the code does
rather than against what the drawing shows. The cheapest way to do the looking is a
throwaway golden that renders the widgets at real size with the real fonts loaded off disk
(`FontLoader`, reading bytes **synchronously** — a widget test's clock does not run the
real event loop, so an awaited `readAsBytes` never completes and `load()` hangs until the
harness times out). It is worth recreating and deleting each time rather than keeping:
these goldens are font- and platform-sensitive, and the app's committed ones deliberately
use the default test font.

## Open questions

Ordered by how much they block the decomposition.

1. **Does `reading_days` carry `book_id`? — Yes.** Settled by `streak-flows`,
   which draws the month twice (`cal-plain` vs `cal-books`) with exactly one
   variable between them. It is one nullable column, it needs no new table, and
   it needs no new interaction: the cover colour is already in
   `books.cover_color` and the fraction is already stored for the wheel. Without
   it the month is a tally, and tapping a day can only answer "yes" — which
   means the grid should not be tappable, which makes the Card a wall poster
   rather than a place to go. It is also the likeliest reason the three social
   tables are dead: `book_memos`, `book_compliments` and `poke_events` have **0
   rows each** and not one of them has a subject. "서연 read 클린 아키텍처 last
   night" is a feed item; "서연 had a day" is not. Three narrower questions
   remain:
   - **A day with two books.** First stamped, last stamped, or a second row
     keyed by book — the last would break the `(user, day)` primary key that
     buys idempotency. Recommendation: keep the key, store the first book
     stamped, and treat the column as "what this day was mostly about".
   - **Pale covers.** Several jackets in this corpus are near-white, and white
     numerals on them are unreadable, so the band needs darkening for light
     covers. A drawing problem, but a real one.
   - **Repaired days**, which the drawing exposed and nobody had stated: a
     repaired day comes back _coloured_, so an honest repair has to ask which
     day **and which book**. A one-tap "I read Tuesday" cannot fill in a
     `book_id`. Either the repair grows a book picker, or repaired days are the
     one kind of day with no book — and then the month needs a third cell
     treatment, which is one more than the design can carry.
2. **The cheap nightly path — drawn, and the hold is available after all.** The
   state sheet is the right home for the truth and the wrong home for a habit:
   four taps and a form, behind a pencil icon. `cheap-path` in
   `docs/mockups/streaks` draws five candidates against the code as shipped.
   - **(a) accept it.** Weakest — the reader opens their book in a reading app,
     not in this one, so "they're already here" is not true.
   - **(b) a long-press on the shelf cover** offering _Read today_. **Available,
     and it does not trade against reorder.** iOS splits one press into two
     commitments: a hold that does not move scales the held icon, dims the rest
     and raises a menu; the jiggle and the remove badges arrive only when the
     finger starts to _drag_ from that state. Reorder lives in the second half, so
     a per-book menu in the first half costs it nothing. **An earlier draft of this
     entry called it a collision and that was wrong** — it compared the proposal
     against where the code happens to commit rather than against the gesture.
   - **What (b) costs to build, precisely.** Today
     `LongPressDraggable(delay: kBookStageTwoDelay)` fires `onDragStarted` at the
     timer and `_onLift` enters edit mode there. (b) needs stage one at the timer
     (scale, dim, menu) and stage two at the first `onDragUpdate` past slop. The
     pointer is still claimed at pointer-down by the same recognizer, so the
     codebase's own constraint is untouched, and `dragAnchorStrategy:
_anchorToPointer` already draws the "cover stays where it stood" half. Three
     things to settle while doing it: the slop threshold; the
     release-without-movement case, where `onDragEnd` fires while the menu must
     stay up, so the menu cannot be owned by the drag's lifetime; and
     `BookWidget`'s existing turn-out at `kBookHoldDelay`, whose unwind at stage
     two should become the scale-up rather than a third animation.
   - **(c) the reading shelf's lamp is the target.** **The lamp cannot be tapped
     at all.** `ReadingLampLayer` pins an `IgnorePointer` wash to `top: 0` of the
     library, outside the scroll view, under a `Positioned.fill(child)` — the
     Dart's own words are "Not a thing a finger can touch, and never over the
     shelves." Its box is `readingLampHeight` = 16 + 134.2 × 0.82 = **126pt**, and
     every point in it has a cover or a plank on top except
     `kReadingLampSourcePadding`, the **16pt** strip under the bar — 28pt short of
     the 44pt floor. `lit` is also already spoken for: it means _a book is open_.
     A **pull cord** makes the fixture touchable and costs invented chrome plus a
     control that stays put after `readingLampFadeDistance`, 150pt, while its
     shelf leaves. The **row pill** it degrades into works and is **withdrawn**:
     it is the only candidate that can never name a book, and it rents 26pt of the
     library permanently to save one tap over (d).
   - **(d) the streak chip opens a streak page. Recommended, first.** The chip
     ships, its 44pt footprint ships, and `reading_streak_chip.dart` already calls
     its current destination "a stopgap, and known to be one", naming the wanted
     thing outright: "a month calendar as its own destination that this chip
     opens". The page holds the run, the week, the month, the record and one
     button; every figure in it is already computable from
     `currentStreakProvider`, `longestStreakProvider`, `readTodayProvider` and
     `readingDaysProvider`. **No new chrome anywhere**, and it asks _which book_,
     so the day keeps its `book_id`.
   - **A page, not a sheet, and `app_routes.dart` already made the argument.**
     `CupertinoPageRoute(fullscreenDialog: true)` — the scanner's and share card's
     route — rises from the bottom without bringing
     `UIModalPresentationPageSheet`'s personality with it: a sheet route stops
     short of the top, takes rounded corners and **scales the presenting page down
     behind it**, so the content reads as a panel belonging to a shrunken app. The
     consequence to build: the page carries an **✕ and no grab handle**, because a
     cover is not drag-dismissible, while the two sheets that open _on_ it do carry
     one. That pair is the only thing telling a reader which surface can be flicked
     away.
   - **(e) a 21:00 notification with the act on the notification.** Zero taps
     inside the app, `profiles.fcm_token` already exists, and it names the book it
     was sent about. Also the most common reason people uninstall streak apps (see
     open question 6). Opt-in, later, and never the only path — and note that the
     mandatory position below costs (e) its whole advantage: an action that has to
     collect a position is a notification that opens the app.
   - **Recommendation: (d) plus (b).** (d) because it needs no gesture surgery and
     answers question 8 in the same move; (b) because it is the short door — and
     after the reversal below it is twice as short, since the press has already
     said which book. They write the same row through the same call and neither
     makes the other redundant.
   - **Reversed: a day cannot be recorded without a position.** Marking the day
     now raises two required sheets — a **book picker** (search field, Reading
     shelf as its own group first) and the **shipped percent wheel**
     (`select_percent_bottom_sheet.dart`, opened at the book's last known value).
     The cover's menu skips the first, because the gesture answered it. This
     overturns "ticking the box writes one `reading_days` row and **nothing
     else**", and the argument for it is _not_ that `books.progress` is sparse:
     that column is two days old (`20260916120000_book_progress.sql`) and has
     never been in a build any reader has, so its row count measures the release,
     not the demand. The argument is that **nobody moves a bookmark for fun** —
     recording the night and knowing where you stopped are one event, and this is
     the only moment the reader has the answer in hand. The payoff is that every
     reading cover's ribbon becomes live, since `readingBookmarkInsetFor` already
     draws it from a fraction that mostly does not exist.
     - **Cost:** the chip's door goes from 2 taps to **4**; the cover's door stays
       at a hold and a tap. Mitigations that are in the drawings rather than
       promised: the wheel opens pre-answered (and `_touched` means agreeing writes
       nothing), the picker groups the Reading shelf first.
     - **What it gives up:** a reader who genuinely does not know their page —
       audiobook, bedside skim, read on another device — cannot record a day they
       did read. There is deliberately **no Skip**, because a skip makes the field
       optional and optional is where it started. Open: whether the status sheet's
       checkbox grows the same requirement, or stays the one door that writes less.
     - **The arrow points one way only.** The tempting symmetry — setting the
       position from the band also stamps the day — is **rejected**, and the two
       directions are not alike: a reader who confirms this wheel has just said _I
       read today_, while a reader nudging their bookmark at 2pm has said nothing
       about a day. The first is a statement, the second an inference the app makes
       on their behalf, and a wrongly stamped day has no visible cause. So
       **stamping a day writes a position; setting a position stamps nothing.** If
       revisited, it must ask rather than infer.
   - **Duolingo's moment, once, at the end.** Confirming raises a full-screen
     celebration: one figure, one label, the week, a milestone bar, one way out,
     five staggered beats with today's cell stamping in last. In **`kCandleFlame`
     over `kCandleGlow`** — the library's own candle — and explicitly _not_
     Duolingo's green, which is this app's brand colour and means something else on
     every other screen. Implicit animation only (`TweenAnimationBuilder`,
     `AnimatedScale`/`AnimatedSlide`), gated by `MediaQuery.disableAnimationsOf`
     the way every hold in `book_widget.dart` already is.
   - **How loud the month is — a `tone` axis, now seven weights through one
     renderer, in two families.** The original draws each day in its book's
     `cover_color` at full strength, which is the most information per pixel on the
     page and also the loudest thing on it: three saturated bands on a surface
     otherwise made of paper and hairlines, with white numerals needing a text
     shadow to survive on top of them. Every alternative re-weights the _same_
     colours rather than replacing them (a quieter palette invented for the
     calendar would stop matching the spines in the legend below it).

     The four **band** tones weaken the fill: **tint** draws the per-day gradient
     at 20%, **rule** puts a neutral capsule under a 3pt edge carrying that
     gradient, **ink** drops colour from the grid entirely and leaves it to the
     legend. The three **mark** tones answer the complaint the other way — the band
     stops being the thing that carries the colour at all. The capsule becomes a
     2pt neutral thread and each read day gets its own small object: **dot**, a 6pt
     disc in the book's colour at _full_ strength (6pt of a 20% jacket is nothing,
     so being small is what buys the saturation back) with the month reading as a
     string of beads; **tab**, the reading ribbon hung from the day's top edge,
     clipped with the asset's own notch; **patch**, an ink block filling the cell at
     a fifth strength and _tilted by the day's own number_ — `((d * 7) % 9) - 4`,
     the rule `.lweek s.on` already tilts its stamps by — so a run reads as tape
     pressed on by hand rather than as a bar out of a chart.

     **Patch is chosen, and this reverses both `rule` and `tab`.** The argument is
     not charm, and it is not the ribbon either: the patch borrows the app's
     _gesture_ where the tab borrows its _asset_. `cardHTML` already tilts every
     slot in the Library Card's own stamp grid by `((d * 7) % 9) - 4` — the exact
     expression this tone tilts a patch by — so the patch is the one weight that is
     already in the app's vocabulary, costs nothing to render (a colour, a border
     and a rotation), and cannot turn to mush when the surface it sits on is
     resized or screenshotted. It also keeps the most information of any quiet tone:
     full-cell area means two similar jackets stay apart, and a fifth strength means
     the numeral sits on top in ordinary ink with no shadow. There is no capsule and
     no thread at all — adjacent patches nearly touch, and the small misalignments
     _are_ the continuity, the way a row of stamps in a passport is. What it risks:
     the tilt is a mannerism and mannerisms age; derived rather than random is the
     hedge, since it is stable across renders and can be tuned to zero by one
     number. **`tab` is the runner-up it beat**, on that same risk taken seriously —
     at 30 cells its fringe is the loudest thing the group produced and it is the
     mark most likely to read as a sticker in a year. **`rule` is the best of the
     band tones** — it split the two jobs one fill was doing (the capsule says
     _these days held together_, the rule says _and this is what they were_) at
     about a twelfth of the ink. **`dot` is the fallback** if the tilt grates: the
     colour stays on a per-day object, just a smaller and squarer one. Bold stays
     the control. Drawn as `cp-f-bold`/`tint`/`rule`/`ink`/`dot`/`tab`/`patch` —
     seven pages differing in one key — and set once as `tone` on the shared spec,
     so the page, both sheets over it, the celebration's month and every flow step
     move together and switching it stays one word.

     **Open, and the choice changes the question rather than just its wording:** the
     Library Card's month is still bold, so one renderer still draws two weights —
     but for the first time the two surfaces have a reason to _converge_. Because
     the Card already tilts its own stamps by this expression, putting its month on
     `patch` is not importing the page's taste into a print object; it is drawing
     one gesture once. **So the recommendation is to move the Card too and delete
     the axis.** What keeps it open is the one thing that gets worse: the Card would
     then carry two tilted grids, its stamp row and the month under it, and a
     mannerism used twice on one surface is how a mannerism becomes a tic. Judge it
     on the Card, at the Card's size, before committing; the fallback is the Card on
     `dot` and the page on `patch` — two weights again, but two quiet ones.

   - **The picker, drawn three ways — and the third is not a list.** 26×39 chip
     against **44×66**, the same 2:3 `kDefaultCoverAspect` as every other cover,
     with the **ribbon** placed by `card_cover_row.dart`'s own rule (asset scaled
     `coverHeight / 124`, gutter end at 8.2% of the width, fore-edge end
     `kReadingBookmarkInset` in from the right). The ribbon is not decoration here:
     the next step asks _how far are you now_, so the reader is looking at where the
     app already thinks they are. The cost is the row — 44pt to 78 — which takes the
     month behind the sheet out of view, weakens "this is a step on the streak
     page", and makes a screenful five results instead of nine.

     **The third drops the list entirely for the shelf layout the app already uses
     for _choosing_ a book.** Every figure is `add_book_bottom_sheet.dart`'s
     `_catalogueSlivers` arithmetic rather than a size that looked right:
     `bookHeight = screenHeight * 0.15` = 127.8pt, `bookWidth = bookHeight / 1.6` =
     79.9pt (the sheet's own ratio, deliberately _not_ `kDefaultCoverAspect`), a
     `bookHeight / (5 * 1.6)` = 16.0pt separator, **three to a line** from
     `floor((screenWidth - 50 + bookWidth * 0.2) / (bookWidth * 1.2))`, each line
     sitting on a `ShelfWidget()` (8pt at 95% width) with 26pt between lines. And
     the cover is the library's real cover at that size rather than a coloured
     rectangle — a `surface` card, a colour block taking whatever the title leaves,
     the title in ink at `BookWidget`'s own `6.1% 6.1% 0 14.3%`, and a photo jacket
     that fills the box and carries no title at all — so it is the same object as
     the shelves the sheet is covering. The case for it: a reader who has ever added
     a book has chosen from this exact layout, recognition is by _picture_ (which is
     how you identify the book in your hand), the ribbon means the position they are
     about to be asked for is visible on the thing they are tapping, and Reading-now
     is its own shelf and exactly one line — so on an ordinary night the answer is
     the first shelf and nothing scrolls. The case against: three candidates a line
     against nine rows, the exact % beside each book is gone (the ribbon carries it
     approximately, the wheel exactly one step later), and the sheet is tall enough
     that the page behind it is mostly covered — the 44×66 objection, one step
     further. **Not taken.** `cp-d-pick-shelf` is the right shape for _browsing a
     catalogue_ — which is exactly the add-book sheet's job, and why it is drawn
     that way there — and the wrong shape for a two-item decision on an ordinary
     night, where a titled row is read faster than three covers on a plank. Kept
     drawn because the reasoning transfers: if this picker ever has to answer "which
     of the 300 books in my library", this is the layout it should grow into, and
     the cover structure worked out here (`.lbk`'s real card at shelf scale) is
     reusable as-is.

     **Chosen: 44×66.** The step sits between _which book_ and _how far in_, so the
     reader should be able to see the answer to the next question on the thing they
     are tapping — which is what the ribbon on a shelf-sized cover gives them.
     Losing the month behind the sheet is the price, and it is acceptable because
     the month is a receipt rather than a control: it is still there when the sheet
     closes.

   - Whichever ships must **write through the same call as the sheet's Save**
     (`ReadingDaysNotifier.setRead`). The old second half of that rule — "and must
     never become a second place to edit position" — is what the reversal spends;
     what survives is that the position is written through the _same_ sheet the
     band already opens, so there is one writer reached from more doors.
3. **The freeze allowance — deferred, not decided.** Two a month accruing
   silently is the proposal, and nothing about it is built. Telling the reader
   creates a licence to skip; hiding it creates a pleasant surprise but a mechanic
   they cannot plan around. Not a blocker: the column is provisioned and the
   derivation already ignores it.
4. **How far back may the honest repair reach?** One day is a correction; a week
   is a fiction generator — and this app's readers demonstrably catalogue
   retroactively (median start 1205 days ago), so the temptation is real.
   **Deferring freezes promotes this question.** With forgiveness available, a
   missed night was absorbed and repair was a nicety; without it, repair is the
   _only_ mechanism that rejoins a severed run, so it now carries the whole weight
   the freeze was going to carry. `x-break` draws that: the gap is tapped on the
   card and the twelve days close up. If the answer is "one day only", then a
   reader who misses two nights has no recourse at all — which is worth deciding
   on purpose rather than discovering.
5. **Does the increment deserve a takeover at all?** Duolingo's answer is
   unambiguously yes, but Duolingo interrupts a lesson the reader chose to
   finish, whereas this interrupts a bookshelf they may have opened to do
   something else. The cheaper alternative is already drawn: `sh-commit`'s
   transient pill.
6. **Does `sc-risk` become a push notification?** `profiles.fcm_token` exists,
   so the plumbing is there and the restraint would be a choice. A 21:00 push is
   the most effective retention mechanic in the category and the most common
   reason people uninstall streak apps.
7. **The milestone ladder.** 7 / 30 / 100 is the obvious one. The constraint is
   that seals must stay rare enough to mean something on a card that will
   eventually carry several.
8. **Where does the month grid live? — Answered: the streak page.** See
   "The month grid has no home yet", and question 2's candidate (d). The Card is
   year-scoped, so the grid could not sit inside it without two time scopes on one
   surface; a full-screen page the library-bar chip opens is year-agnostic, is the
   destination `reading_streak_chip.dart` already asks for, and carries the
   nightly act as well. Drawn as `cp-d-page`. **What it forces is a decision
   about the number's home**: "exactly one permanent home" was settled as the
   Library Card, and the proposal is to move it to this page, leaving the chip
   and the Card's streak tile as two pointers to it. One home, two pointers — what
   must not persist is today's state, where three surfaces draw the figure with no
   stated primary. The page itself obeys that rule internally: its month card drops
   the "longest this month" stat for a book count, because the hero above it is
   already the run.
9. **Does marking a book _Read_ also stamp the day?** Almost certainly it should
   — a reader finishing a book today read today — but silently means the sheet
   writes a `reading_days` row with no visible cause, and visibly means a third
   new row on the one status this design just simplified.
10. **Friend visibility of `reading_days`.** Not specified above. Nothing in the
    six moments needs it.
11. **Is `D+n` redefined as days-since-last-log** rather than days-since-start?
    At a median of 1205 days, `D+1205` is not information.

## Out of scope

- **The paused / put-off state and the reading graveyard.** Being designed in
  parallel by someone else; the 107-of-109 stale reading books are that
  problem's evidence, not this one's. Note the interaction for whoever lands
  second: a paused book must not be a streak liability, and pausing must not
  write to `reading_days`.
- **Freezes / forgiveness, in the first cut.** `kind` is provisioned in the table
  and nothing reads or writes `'freeze'`. The consequence is drawn and accepted:
  one missed night is a total reset, and the run in the fixture month falls from
  12 to 3. See "A freeze is a row, not a policy — but not yet".
- Anything that charges money. There is no store, and the freeze and the repair
  are both deliberately unpurchaseable.
- Friend-facing streaks, leaderboards, and any comparison between readers.
- Backfilling `page_count`. The catalogue source has no page field; 65% is the
  ceiling, not a bug.
- Changing `books.position` or `shelves.position`.
