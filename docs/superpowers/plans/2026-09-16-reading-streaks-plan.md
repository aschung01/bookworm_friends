# Reading Streaks Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-12-reading-streaks-design.md`

**Drawings:** `docs/mockups/streaks/index.html` (95 frames, `verify.py` 532 checks)

**Goal:** Give the app a reading position it can store, a reachable way to set it, and
a day-level record from which a streak can be derived.

**Order of work, and why.** Two independent halves, deliberately sequenced so the safe
one ships first:

- **Tasks 1–8 are the position.** They ship alone, are useful alone, and involve no
  streak at all. `books.progress` does not exist yet, so today the ribbon on the cover,
  the `p.147` in the band and the whole percent wheel write to a column that isn't
  there. This half is the one the corpus unambiguously supports.
- **Tasks 9–13 are the streak.** This is the half the corpus argues _against_ — 168 of
  293 finished books (57%) have `start_date == finish_date`, i.e. people catalogue rather
  than track. That figure is the Phase 3 audit's
  (`docs/superpowers/plans/2026-08-16-phase-3-library-card-plan.md`, 2026-08-16) and has
  **not** been re-measured here, so trust the ratio and not the counts; the mechanism
  behind it is still live in `book_info_bottom_sheet.dart`, which sets both dates to
  `now()` on a straight-to-finished flip. Do not start this half until the position half
  is in a reader's hands.

Deferred and explicitly not in this plan: the month grid (has no destination yet), the
celebration/milestone/warning moments, freezes, and the cheap nightly path.

---

## Build log — 2026-09-17

**Tasks 1–13 are built, both migrations are applied, and `flutter test` is green at
1518 cases.**

### The migrations, and how they were applied

Applied through the **Supabase MCP `apply_migration`** rather than `supabase db push`,
which is the tool Task 1's Step 3 warns against. Two things made that the right call
here rather than a shortcut, and the warning still stands in general:

- **The ownership hazard had already cleared.** `20260915130000_book_reader_app.sql` —
  the store-links migration `db push` would have carried along — **is applied remotely
  now.** Remote held 24 migrations against 26 local, so exactly these two were pending.
  The reason to avoid `db push` was gone.
- **No database password is available in this session**, so `db push` was not actually
  reachable. MCP was the only route.

**The version drift `AGENTS.md` documents happened exactly as described, and was
repaired in the same session.** `apply_migration` stamped
`supabase_migrations.schema_migrations.version` from the wall clock — `20260917220627`
and `20260917220659` — not from the local filenames. Left alone, the CLI would treat
both files as still-pending and a later `db push` would re-run the DDL and fail on
`already exists`. Both rows were `UPDATE`d to `20260916120000` and `20260916130000`,
after which `supabase migration list --linked` shows Local and Remote matching on every
row and `db push --dry-run` reports **"Remote database is up to date."**

### What was verified against production, not assumed

- `books.progress` is `real`, **nullable**, no default; `books.position` is untouched
  (`integer NOT NULL DEFAULT 0`).
- `books_progress_range` **rejects `1.5` and `-0.1`** and accepts `0`, `1` and `NULL`.
- `reading_days` has `PRIMARY KEY (user_id, day)`, `reading_days_kind_check
CHECK (kind IN ('read','freeze'))`, `book_id` FK **ON DELETE SET NULL** and `user_id`
  FK **ON DELETE CASCADE**.
- RLS is enabled with **four policies, one per verb**, all scoped to
  `user_id = auth.uid()`, and UPDATE carries both USING **and** WITH CHECK.
- **The primary key's idempotency claim holds:** stamping the same `(user_id, day)`
  twice leaves **one** row, `kind` defaults to `'read'`, and an unknown kind is refused.
- `get_advisors(security)` reports **nothing against `reading_days`**. The warnings it
  does return (mutable `search_path`, `SECURITY DEFINER` exposure on the invite/poke
  RPCs, leaked-password protection) all predate this work.

Both behavioural probes ran inside `DO` blocks ending in a deliberate `RAISE`, so each
aborted its own transaction — production data was read, never written. Confirmed after
the fact: `count(*) from books where progress is not null` is `0`, and
`count(*) from reading_days` is `0`.

### Corrections to this plan, made while building

Each of these is a place the plan was wrong or silent, recorded here rather than left
as a difference between the document and the tree.

- **Task 2 — `progressPageLabel` became `bookProgressPage` + `Book.progressPage`.**
  Forced, not cosmetic: the wheel's rider labels the percent under the reader's thumb,
  which is not stored on any book, so a getter over `this.progress` could not serve it
  and the wheel would have grown a second copy of the rounding. See Task 2, Step 2.
- **Task 6 — the fill is `brandText`, not `brandFill`.** A no-op in light mode, where
  both are `#067657`, so it draws exactly what the mockup drew. They differ in dark
  mode, where `brandFill` stays dark and would leave a 4pt bar all but invisible on a
  dark band. `test/goldens/band_progress_edge_dark.png` is the image that shows it.
- **Task 7 — the progress row is its own widget**, `lib/ui/widgets/band_progress_row.dart`,
  rather than inline in `book_details_tab_view.dart` as the file list implied. It is
  testable that way, and `band_progress_edge.dart` had already set the precedent.
- **Task 7/8 — a door only where it can be opened.** The plan is silent on a friend's
  book, where the band renders too. Both rows still _read_ and neither draws a handle:
  no chevron, no tap target, no press state. A chevron on a row that does nothing is a
  lie about what the row does. `test/band_doors_test.dart` pins it.
- **Task 8 — the ribbon moves horizontally, and the design record was stale.**
  `2026-09-12-reading-streaks-design.md` said `0.0` puts "the ribbon at the top",
  which is prose left over from an abandoned _vertical_ length encoding. The mockup's
  chosen anatomy is `top-edge-slide` — "across the cover's top edge, spine to
  fore-edge" — so the plan's "horizontal offset only" is right and the spec has been
  corrected to match.
- **Task 12 — the chip went into `home_page.dart`, not `library_view.dart`.** The bar
  the plan describes is `_LibraryBar`, and it lives in `home_page.dart`;
  `library_view.dart` only mentions it in a comment.
- **Task 13 — tiles now flow at most two per row.** Three tiles became reachable for
  the first time, and thirds of a ~310pt card give each about 97pt, which wraps
  "Most-read author" three ways. One and two tiles lay out exactly as before.
- **Task 7 — the progress row draws a prompt before there is a position.** Corrected
  after the fact, on the product owner's call, and worth reading as a whole because the
  first version was defensible and still wrong.

  It shipped gated on `progress != null`, reasoning from the migration's rule that null
  draws **no bar** — an empty track is a _claim_, that the reader started and got
  nowhere. That rule is airtight, and it is about the **bar**. Extending it to the whole
  **row** was an inference the design record never makes: a row reading `How far in? ›`
  claims nothing.

  The consequence was not cosmetic. The band had **no door for the first set**, which is
  the one moment every book passes through — so the ergonomic argument that won the
  row-as-door (333×30 in the thumb's arc against a 48×48 pencil in the top-right dead
  zone) applied least where the row existed and most where it did not. And because the
  streak chip hides at 0 as well, **a fresh install showed no trace of this feature
  anywhere** until the reader happened to open the status sheet.

  So with no position the row is `How far in? ›` — in `secondaryText`, the app's own
  no-value-yet tone, at the same token and size as the numbers that replace it, and
  **still no bar**. On a _friend's_ book the prompt is withheld: nothing to read, and
  not a door for anyone but the owner, so it would be a bare chevron on an empty line.

  **The cost is 40pt, measured rather than estimated** — the tab strip moves 390.5 to
  430.5 on a 390×844 device. Real, on the screen whose last redesign was about lifting
  the reading books higher, but paid _only_ while there is no position and gone the
  moment the reader answers.

- **Task 7 — the row's leading text is indented 10pt, which answers an open question.**
  The drawings raised this and declined to settle it: "Bringing them into column means
  giving the progress row 10pt of horizontal padding, **which is a change to the row
  that was already settled** — so it is raised as a question rather than taken." It has
  now been taken, on the product owner's call.

  Measured rather than guessed, on a 390×844 device: the period card's box sits at
  **x30** (the band's content edge), its status chip at **x40** (the card's own 10pt
  content inset), the chip's _label_ at **x51**, and the row's text was at **x30**. So
  10pt lines the row's text up with the **chip's edge** — the object above it — rather
  than with the letters inside the chip, which would read as over-indented against the
  card.

  Two constraints came with it, both now pinned by `test/band_doors_test.dart`'s
  `the row's left edge` group:
  - **Both states are indented, not just the prompt.** Otherwise the text slides 10pt
    left at the instant the reader answers, which is the one moment they are looking
    straight at it.
  - **The trailing half does not move.** The chevron column at x362 was settled by
    pulling the _card's_ glyph out to meet this row, so an indent on the left must not
    push the percent or the chevron anywhere. Asserted as a relationship rather than a
    coordinate, since the numbers move with device width and the relationship does not.

### Deferred, with the reason

- **Task 10's durable offline queue.** The write is optimistic and reverts with an
  error on failure; it does not survive a restart. The app has no queue
  infrastructure, and building one for a checkbox would be the tail wagging the dog.
  The table is already shaped for it — `(user_id, day)` means a queue can replay its
  whole backlog twice with no reconciliation — so this is a later feature and not a
  later migration.
- **Task 12's third chip state ("amber when late").** Two open questions sit behind one
  pixel and neither is ours to answer: **which hour counts as late** is undecided
  anywhere in the spec or the drawings, and the mockup draws that state as a **dashed
  border rather than amber**, so the plan and the drawing disagree about what it even
  looks like. The two states that are drawn and unambiguous are built — grey while
  today is open, brand once it is stamped — plus absent when there is no run.

---

## Task 1: Migration A — `books.progress`

**Files:**

- Create: `supabase/migrations/20260916120000_book_progress.sql`

- [ ] **Step 1: Write the migration in house style** — reasoning comment, DDL,
      `COMMENT ON COLUMN` — following `20260915120000_book_reading_shelf_index.sql`. The
      reasoning must carry four things, because each has already cost a review round: - **The column does not exist today.** A schema search for
      `progress|percent|pct|page|frac|bookmark|current|pos` returns only
      `books.page_count`, `books.position`, `shelves.position`. - **Why not `position`.** `books.position` is the _shelf ordering_ index — max 25
      across all 473 books, duplicated within a shelf. Writing progress there would
      silently reorder shelves. Name it `progress` and say so on `position`'s own
      comment too, or the next reader "fixes" the inconsistency. - **`null ≠ 0`.** Nullable, and null means "nothing recorded", not "page one". A
      reading book with no progress draws no bar rather than an empty one. - **Why a fraction and not a page.** `page_count` is null for 65% of reading books,
      so a page column is unusable for two books in three. The fraction works for every
      book and the page is a derived label.
- [ ] **Step 2: Constrain it.**
      `check (progress is null or (progress >= 0 and progress <= 1))`.
- [ ] **Step 3: `supabase db push --dry-run` before anything else, and read what it
      says it would push.** The history is **not** drifted — checked 2026-09-16 with
      `supabase migration list`. The problem the reading-shelf-reorder plan describes
      (local `20260908120000` unapplied, remote `20260908230250` with no local file) has
      since been repaired: `20260908120000` is now applied on both sides and the
      wall-clock entry is gone. - **What is true instead:** `20260915130000_book_reader_app.sql` exists locally and
      is **not applied remotely**, and it belongs to the in-flight store-links work
      (`docs/superpowers/specs/2026-09-15-store-links-design.md`), not to this plan.
      `db push --dry-run` today reports it would push exactly that one file. - **So the hazard is ownership, not corruption.** `db push` pushes _every_ pending
      migration, so pushing this task's file would carry someone else's with it. Either
      let that thread land theirs first and then push this alone, or push both
      deliberately having read it — it is an additive nullable column, so the risk is
      low, but it should be a decision rather than a side effect. - **Do not reach for the MCP `apply_migration` tool to sidestep this.** That is the
      most likely cause of the drift that was just repaired: it stamps a version from
      the wall clock and leaves no local file, so the history gains a remote-only entry.
      Always write the local file and use `db push`.
- [ ] **Step 4: Apply, then verify** the column exists, is nullable, and that the check
      rejects `1.5` and `-0.1`.

## Task 2: `Book.progress`

**Files:**

- Modify: `lib/models/book.dart`
- Modify: `test/book_model_test.dart` (or nearest existing model test)

- [ ] **Step 1: Add `progress` as `double?`** — constructor, `fromJson`, `copyWith`.
      `fromJson` must treat an absent key and an explicit null identically, exactly as
      `pageCount` and `coverColor` do, so rows written by older builds parse as "nothing
      recorded".
- [ ] **Step 2: Add the derived page in exactly one place.** Shipped as a top-level
      `int? bookProgressPage(double? progress, int? pageCount)` plus a thin
      `Book.progressPage` getter that delegates to it — **not** the single
      `progressPageLabel` getter this step originally specified. The rename is forced
      rather than cosmetic: the wheel's rider has to label the percent currently under
      the reader's thumb, which is not yet stored on any book, so a getter over
      `this.progress` could not serve it and the wheel would have grown a second copy of
      the arithmetic — the exact defect the step exists to prevent. Returns `null` when
      either input is null, and `round(progress * pageCount)` otherwise. One place,
      because the band, the wheel's rider and any future shelf tooltip must not each
      round differently — the mockup printed `p.148` beside `p.147` for exactly that
      reason.
- [ ] **Step 3: Document the quantisation on the getter.** The wheel is the only writer
      and it spins whole percent, so `progress` is always a whole percent and the derived
      page is stable. Without this note someone will "improve" the wheel to finer steps
      and reintroduce a page number that changes when you look at it.

## Task 3: `readingDate` — the 4am rollover

**Files:**

- Create: `lib/models/reading_date.dart`
- Create: `test/reading_date_test.dart`

- [ ] **Step 1: Write it as a pure function** — `localDate(now - 4h)`. No I/O, no
      provider, no clock singleton; take `DateTime now` as a parameter so it is testable
      without mocking time. `lib/models/` is the right home: `lib/core/` holds only
      `supabase_config.dart`, and the comparable pure helper `bookReadingSpanDays` lives
      in `lib/models/library_card_stats.dart`.
- [ ] **Step 2: Document why 4am and not midnight.** A reader finishing a chapter at
      00:30 means "tonight", and a streak that breaks at midnight punishes the exact
      behaviour the feature exists to encourage.
- [ ] **Step 3: Document why there is no timezone column.** `profiles` has none, so the
      day is the _device's_ local date. State the consequence plainly: a reader who flies
      across the date line can gain or lose a day, and that is accepted rather than
      solved, because the alternative is a server-side timezone the app has never
      collected.
- [ ] **Step 4: Test the boundaries** — 23:59, 00:00, 00:30, 03:59, 04:00; a DST
      boundary; and a timezone change between two consecutive calls.

## Task 4: The percent wheel

**Files:**

- Create: `lib/ui/widgets/bottom_sheets/select_percent_bottom_sheet.dart`

- [ ] **Step 1: Copy `select_date_bottom_sheet.dart`'s structure exactly** —
      `CNBottomSheet.show` wrapping `SizedBox(height: 320)`, header at
      `symmetric(horizontal: 20, vertical: 16)` with the title in
      `AppTextStyles.subtitle` beside `ElevatedActionButton(width: 92, height: 32)`
      labelled `confirm`, then `Expanded(child: CupertinoPicker(...))`. **The only new
      code is the item list.** This is not a new control and must not become one.
- [ ] **Step 2: 101 items, 0–100.** Document why percent rather than pages: a page wheel
      is fine at 320 stops and absurd at 912 (~91 flicks), and it cannot represent the
      two books in three with no `page_count`. Percent is 101 stops for every book ever
      printed.
- [ ] **Step 3: The derived page rider** under the picker, from
      `bookProgressPage` — never recomputed locally. Absent, with no apology, when
      `pageCount` is null.
- [ ] **Step 4: State the granularity where a reader can see it.** At 320 pages a stop is
      3.2 pages, so "I am on page 148" is not expressible; the rider will read `≈ p.147`.
      This is a real cost of the storage decision and the rider is where it surfaces.

## Task 5: `ProgressFieldRow`, and the sheet that already exists

**Files:**

- Create: `lib/ui/widgets/progress_field_row.dart`
- Modify: `lib/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart`
- Modify: `lib/providers/library_provider.dart`

- [ ] **Step 1: Build `ProgressFieldRow` beside `DateFieldRow`** — same
      `surfaceVariant` ground, radius 10, `symmetric(h14, v10)`, body 15 left, value
      right. It is the sibling of an existing widget, not a new idiom.
- [ ] **Step 2: Add it to `showBookStatusBottomSheet` at `status == bookStatusReading`**,
      inside the existing `AnimatedSize` that already reveals the date rows. Position is
      one more field of exactly the kind that sheet already holds.
- [ ] **Step 3: Extend `updateBookStatus` with `double? progress`** and write it in the
      same `books` update as status and the dates. One call, one Save.
- [ ] **Step 4: Assert isolation in a test** — setting `progress` must leave `status`,
      `start_date`, `finish_date` and `reading_shelf_index` untouched, and must write no
      row anywhere else. This is the property the whole design rests on.

## Task 6: The band's closed state — the linear edge

**Files:**

- Create: `lib/ui/widgets/band_progress_edge.dart`
- Modify: `lib/ui/views/book_details_tab_view.dart`

- [ ] **Step 1: Write the painter.** A 4pt linear fill along the bottom of the
      `surfaceVariant` container at `book_details_tab_view.dart:399`, full width, its ends
      **clipped by the container's own 30pt bottom radius** so they disappear into the
      corners. Track at `rgba(6,118,87,0.16)`, fill at `brandFill`.
- [ ] **Step 2: Share the 30 with the container.** `BorderRadius.only(bottomLeft: 30,
bottomRight: 30)` is declared in the same widget; take the radius from **one
      constant** used by both. Two 30s in two places is how the bar and the band drift
      apart.
- [ ] **Step 3: Document the low-end blind spot, because it is a deliberate trade.**
      Below roughly 8% the fill is entirely inside the corner radius and shows nothing.
      That is accepted: the numbers sit directly above the bar, so an empty-looking bar
      beside a legible `4%` degrades rather than lies. `cl-early-straight` in the mockup
      is that state drawn, and `ln-flat` is the rejected alternative that spans only the
      flat bottom — visible at 1%, but no longer an edge. **Do not "fix" this by tracing
      the border**; that was drawn (`cl-edge2`) and rejected as a different look.
- [ ] **Step 4: Golden-test it** at 1%, 4%, 46% and 100%, so the clipping behaviour is
      pinned rather than rediscovered.

## Task 7: The band's two doors

**Files:**

- Modify: `lib/ui/views/book_details_tab_view.dart`

- [ ] **Step 1: The progress row becomes a door.** `p.147 / 320` left, `46%` right,
      chevron last, opening `showSelectPercentBottomSheet` directly. It stays a plain row
      **directly on the grey band** — not wrapped in a card or a grouped section. Both
      alternatives are drawn in the mockup and neither was chosen.
- [ ] **Step 2: The period card becomes a door.** Push its value right
      (`margin-left: auto` equivalent — a `Spacer` between the status pill and the date
      range), chevron last, `minHeight: 44`. This is `DateFieldRow`'s shape verbatim and
      it opens `showBookStatusBottomSheet` — the same sheet the pencil opens, editing
      status + start + finish, which is exactly what the card displays. - Reasoning to carry in a comment: **a chevron alone is not enough.** The card's
      three pieces were packed left, so the chevron floated at the right with a void
      between and read as an ornament. `pd-naive` is that version drawn.
- [ ] **Step 3: Column-align the two chevrons at x362.** The card is inset 10pt inside
      the band, so its chevron naturally lands at x352. Pull the **card's** glyph out by
      10pt; never move the progress row to fix the card's alignment. Aligned, two
      chevrons read as the right edge of a list; staggered, they read as a mistake
      (`ch-stagger`).
- [ ] **Step 4: Extend both rows' hit areas to 44pt.** The progress row is 30pt visually;
      take the remaining 14 from the band's 16pt bottom padding rather than growing the
      layout.
- [ ] **Step 5: Evict the streak chip from the progress row** if it is ever added there.
      A tappable row cannot contain a second, smaller tappable object. The chip's home is
      the library bar (Task 12).

## Task 8: Retire `edit_outlined`, and the ribbon reads `progress`

**Files:**

- Modify: `lib/ui/views/book_details_tab_view.dart`
- Modify: `lib/ui/widgets/shelf_row.dart`
- Modify: `lib/ui/widgets/library_card/card_cover_row.dart`

- [ ] **Step 1: Remove the pencil from the app bar.** `edit_outlined` at
      `book_details_tab_view.dart:237` opens `showBookStatusBottomSheet`, which the period
      card now opens. Its last job is gone; leave only `delete_outline`. Document that
      this is the point of Task 7 — a 48×48 target at x341–389 in the top-right dead zone
      replaced by a 333×44 row in the thumb's arc.
- [ ] **Step 2: Do not grep for `edit_outlined` and delete both.** There are two in
      this file and only one is the pencil: `book_details_tab_view.dart:237` is the app-bar
      action to remove, and `book_details_tab_view.dart:959` is the **memo menu's** edit
      icon inside `_showMemoMenu`, which is unrelated and must stay. `book_details_tab_view.dart:749`
      (`_onEditStatusPressed`) has exactly one caller, at `book_details_tab_view.dart:235`.
- [ ] **Step 3: The ribbon reads `progress`** on the detail cover, `shelf_row` and
      `card_cover_row` — horizontal offset only, display only, no new writes. A book with
      null progress keeps today's ribbon position.

**Ship here.** Tasks 1–8 are the position, complete and useful with no streak in sight.

---

## Task 9: Migration B — `reading_days`

**Files:**

- Create: `supabase/migrations/20260916130000_reading_days.sql`

- [ ] **Step 1: Create the table** — `(user_id, day, kind, book_id, created_at)`, primary
      key `(user_id, day)`. Follow `20260828120000_friendships.sql` for comment style. - **The PK is the design.** It makes the table set membership, so a double stamp is
      free idempotency and there is no "already stamped today?" read before write. - **`book_id` is deliberate.** Settled by drawing the month twice: `cal-plain` and
      `cal-books` show the same twelve days, and the one coloured by `books.cover_color`
      turns a tally into a history. Nullable, `ON DELETE SET NULL` — deleting a book
      must not delete the day you read it. - **`kind` is provisioned and unused.** Freezes are deferred; the column exists so
      adding them later is not a migration. Default `'read'`, with a named
      `CHECK (kind IN ('read', 'freeze'))` as the spec's DDL has. Do **not** copy
      `books.reader_app`'s no-CHECK reasoning here: that column takes store keys from an
      external list that grows without us, whereas this one is written only by our own
      client and both of its two values are legal from day one — so the constraint
      cannot make an old database reject a new build's row.
- [ ] **Step 2: RLS** — enable it, and one policy per verb scoped to
      `auth.uid() = user_id`. A reading day is nobody else's business; friends' streaks
      are out of scope for this cut.
- [ ] **Step 3: Note what is NOT here** — no `streak` column, no `longest_streak`. The
      run is derived on read (Task 11), because a stored counter and a set of days can
      disagree and then the counter is a second truth.

## Task 10: The day checkbox

**Files:**

- Modify: `lib/ui/widgets/bottom_sheets/book_status_bottom_sheet.dart`
- Modify: `lib/providers/library_provider.dart`

- [ ] **Step 1: Add "I read today"** to the sheet at `status == bookStatusReading`, under
      the position row, written by the existing Save.
- [ ] **Step 2: Upsert one row** keyed `(user_id, readingDate(now))`, with `book_id` set
      to the book in hand. Optimistic local write with an offline queue; the PK makes a
      replayed queue entry harmless.
- [ ] **Step 3: Unstamp deletes the row.** Test that stamping then unstamping leaves zero
      rows and that the derived run falls in the same frame.
- [ ] **Step 4: Assert isolation both ways** — stamping leaves `progress`, `start_date`,
      `finish_date` and `status` untouched; setting `progress` writes no `reading_days`
      row. Two tests, because the coupling question ("should saving a position stamp the
      day?") is closed by construction and must stay closed.

## Task 11: Derivation

**Files:**

- Create: `lib/models/streak.dart`
- Create: `test/streak_test.dart`

- [ ] **Step 1: Derive current and longest run** client-side over the trailing rows.
      Pure function over a `Set<DateTime>` plus today; no I/O.
- [ ] **Step 2: A run ending yesterday still counts.** Today being unstamped means "open",
      not "broken" — that distinction is the difference between encouragement and a
      threat, and it is what the chip's grey state expresses.
- [ ] **Step 3: Test** an empty history (0); today only (1); a run ending yesterday
      (counts); a run ending two days ago (0, and the record survives); two runs,
      asserting the longest is the max and not the latest.

## Task 12: The chip in the library bar

**Files:**

- Modify: `lib/ui/views/library_view.dart`

- [ ] **Step 1: `▣ 12` in the library bar** — three states, not four: grey when today is
      open, `brandFill` when stamped, amber when late. The fourth (frozen) is deferred
      with freezes.
- [ ] **Step 2: It costs no vertical space** and it is not a second home for the number —
      it points at the Library Card.
- [ ] **Step 3: Do not make the chip itself a 44pt target by growing it.** A 44pt ring
      around a 22pt chip is the failure this design has already rejected twice; extend the
      hit area instead.

## Task 13: The streak `StatTile`

**Files:**

- Modify: `lib/ui/widgets/library_card/stat_tile.dart` (or the card's tile list)

- [ ] **Step 1: A streak tile as a peer of _Pace_** — figure 30, not the hero 46.
      **`booksRead` stays the hero**, settled by looking at the widget rather than
      arguing.
- [ ] **Step 2: Omitted, never zero-filled**, per the card's existing rule. No run means
      no tile.
- [ ] **Step 3: The month grid does not go here.** The card is year-scoped and its label
      reads "All-time library card", so a month pager would put two conflicting time
      scales on one surface. The grid needs its own destination, which is an open
      question, not a task.

---

## Testing beyond the per-task tests

- **The label** — `round(progress × page_count)` agrees with the wheel's rider; the label
  is absent when `page_count` is null.
- **Layout** — the band with the progress row measures 158, and the tab strip sits at
  422 with the linear edge adding nothing.
- **Golden** — the band edge at 1%, 4%, 46%, 100%.
- **`flutter test`** stays fully green. Per `AGENTS.md` there is no expected-failure
  list, so any red is a real regression.
- **`python3 docs/mockups/streaks/verify.py`** stays green for as long as the drawing is
  the reference. It ends in `VERIFY OK` — that line is authoritative, not the harness
  summary above it.

**One non-automatable rule that caught every defect the checks missed: one value,
printed once.** `72% … 72%` in the band, `12` above "12 days in a row", and `p.148`
above `p.147` all reached the mockup and were found by eye, not by assertion.
