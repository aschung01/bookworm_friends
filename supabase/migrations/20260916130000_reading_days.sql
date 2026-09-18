-- `reading_days`: the day-level record a reading streak is derived from. One row
-- per reader per day, and nothing else.
--
-- Design record: `docs/superpowers/specs/2026-09-12-reading-streaks-design.md`.
-- Drawings: `docs/mockups/streaks/index.html`.
--
-- ---------------------------------------------------------------------------
-- The primary key IS the design, not bookkeeping.
--
-- `(user_id, day)` makes this table **set membership**: a day is either in it or it
-- is not, and there is no third state and no magnitude. That buys idempotency for
-- free rather than by discipline -- stamping twice writes one row -- so no writer
-- anywhere has to ask "already stamped today?" before writing. A double tap, a
-- retry after a failed request, and an offline queue that replays its backlog twice
-- are all the same harmless UPSERT.
--
-- Compare the shape this replaces: any `streak_events` append log, or any counter,
-- needs that read-before-write, and a read-before-write is a race the client cannot
-- win offline. Here there is nothing to increment and therefore nothing to get out
-- of step.
--
-- The cost, recorded because it is a real constraint on a later feature: a day can
-- hold only one row, so a reader who reads two books on one night must pick one
-- (see `book_id`). That is a genuine limitation and it is the price of everything
-- above.
--
-- ---------------------------------------------------------------------------
-- Why `book_id` exists, which was settled by drawing the month twice.
--
-- `cal-plain` and `cal-books` in the drawings show the **same twelve days, the same
-- run, the same streak**. The only difference is that one colours each day by
-- `books.cover_color` and the other does not, and the difference in what the screen
-- *means* is total: the plain grid is a tally, and the coloured one is a history --
-- five days of one book, three of the next, three of a third. It can say *what* was
-- read, not merely that something was. It is the frame that would make someone
-- scroll back through their year, and it costs one nullable column and colour the
-- app already stores.
--
-- Nullable, and `ON DELETE SET NULL` rather than `CASCADE`: deleting a book must
-- not delete the reader's record of having read that night. The night happened. A
-- cascade here would make tidying the library quietly erase streak history, which
-- is the same class of silent damage that writing progress into `books.position`
-- would have caused.
--
-- ---------------------------------------------------------------------------
-- Why `kind` exists and why nothing reads it.
--
-- Freezes -- a forgiven missed day, as in Duolingo -- are **deferred, at the
-- product owner's decision**, not rejected. The column is provisioned with default
-- `'read'` because provisioning it now costs nothing and means adding forgiveness
-- later is a feature rather than a migration. Nothing reads or writes anything but
-- the default in this cut, and no drawing refers to forgiveness: the frames that
-- did were removed rather than left implying a feature exists.
--
-- The deferral has a drawn cost that is worth naming here, since this column is
-- where it would have been paid: with no forgiveness, one missed Thursday severs a
-- run instead of bridging it, so a reader who misses a single night loses a
-- fortnight. Defensible for a first cut with nothing to sell -- but the column is
-- here so that reconsidering it is cheap.
--
-- A named CHECK constrains it to `('read', 'freeze')`, following
-- `cover_read_events.outcome` and **not** `books.reader_app`. The tempting analogy
-- to `reader_app` does not transfer: that column's values are store keys from an
-- external, growing list, so an old database rejecting a new build's row is a real
-- hazard there. `kind` is written only by this app and has a two-value semantic
-- domain, both of which are permitted from the very first migration -- so shipping
-- freezes later needs no migration and the constraint costs nothing it protects.
-- Named, so that a third state (if forgiveness ever grows one) is a `DROP
-- CONSTRAINT` naming a thing rather than an archaeology exercise.
--
-- ---------------------------------------------------------------------------
-- No `streak` column, and no `longest_streak` column.
--
-- The run is derived on read, client-side, as gaps-and-islands over the trailing
-- rows -- even a perfect four-year streak is under 1,500 rows, so fetching 400 of
-- them is free. A stored counter and a set of days **can disagree**, and once they
-- can, the counter is a second truth that has to be detected, reconciled and
-- repaired, and every writer has to keep two things consistent instead of one.
--
-- There is a second, harder reason the server does not compute it: `profiles` has
-- no timezone column, so the day boundary is the *device's* local date on a 4am
-- rollover -- a reader finishing a chapter at 00:30 means "tonight", and a design
-- that records that as tomorrow punishes the exact behaviour the feature exists to
-- encourage. The client computes the date and sends it, because the rollover and
-- the local date are both facts about the phone in the reader's hand. A Postgres
-- function would have to be authoritative about something it cannot observe.
--
-- Which is also why `day` is `date` and not `timestamptz`. Storing an instant would
-- invite the server to re-derive the day from it and get a different answer.
--
-- ---------------------------------------------------------------------------
-- Why RLS is owner-only, and why that is narrower than `books`.
--
-- A reading day is nobody else's business, and friends' streaks are out of scope
-- for this cut -- nothing in the drawn moments needs another reader's rows. So
-- there is deliberately **no `is_profile_visible()` clause here**, which makes this
-- table stricter than `books`, `shelves` and `book_memos`, all of which a friend
-- can read.
--
-- That asymmetry is intentional and is stated so that widening it later is a
-- considered change rather than a consistency fix someone applies for symmetry. The
-- ratchet only turns comfortably one way: a policy that starts owner-only can be
-- widened once the product decides friends should see a streak, whereas one that
-- ships friend-visible has already published a habit record nobody agreed to
-- share.
--
-- ---------------------------------------------------------------------------
-- What the corpus says, recorded honestly because it argues against this table.
--
-- **168 of 293 finished books (57%) have `start_date == finish_date`** -- measured
-- in the Phase 3 audit (`docs/superpowers/plans/2026-08-16-phase-3-library-card-plan.md`,
-- 2026-08-16) and *not* re-measured for this migration, so treat the ratio as the
-- shape and not as today's count. More than half the finished library was entered in
-- a single act, which is the signature of *cataloguing* rather than *tracking*:
-- people are recording that they read a book, not the days on which they read it.
--
-- The mechanism is still in the code, which is why the ratio is not stale legacy
-- noise: `book_info_bottom_sheet.dart` sets both dates to `now()` when a book is
-- flipped straight to finished, so every such book is born degenerate. Phase 3 hit
-- the same wall and drew the same conclusion for its Pace tile -- a same-day pair
-- means "logged as read", never "read in zero days".
--
-- This table is the bet that a daily signal changes that behaviour, and it is the
-- part of the design **least supported by the existing data**. It is written down
-- here rather than in a retrospective so that if the ledger fills up with one row
-- per finished book, that is a confirmed prior and not a mystery.
-- ---------------------------------------------------------------------------

CREATE TABLE public.reading_days (
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  day date NOT NULL,
  kind text NOT NULL DEFAULT 'read',
  book_id uuid REFERENCES public.books(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day),
  CONSTRAINT reading_days_kind_check CHECK (kind IN ('read', 'freeze'))
);

COMMENT ON TABLE public.reading_days IS
  'One row per reader per day they read. The (user_id, day) primary key is the '
  'design: it makes the table set membership, so stamping twice writes one row and '
  'no writer has to check whether today is already recorded -- a replayed offline '
  'queue entry is harmless. Deliberately no streak or longest_streak column: the '
  'run is derived client-side over the trailing rows, because a stored counter and '
  'a set of days can disagree and the counter then becomes a second truth to '
  'repair. The day is the device''s local date on a 4am rollover, computed by the '
  'client, since profiles has no timezone column and the server cannot observe the '
  'phone the reader is holding. Its one row per day also means a night with two '
  'books must pick one.';

COMMENT ON COLUMN public.reading_days.kind IS
  'Provisioned for freezes -- a forgiven missed day -- which are deferred, not '
  'rejected. Defaults to ''read'' and nothing reads or writes anything else in this '
  'cut, so that adding forgiveness later is a feature rather than a migration -- '
  'both values are already permitted by the CHECK, so that later change is code '
  'only. Constrained rather than free text (unlike books.reader_app) because this '
  'column is written only by our own client and its domain is two words, not a '
  'store list that grows without us.';

COMMENT ON COLUMN public.reading_days.book_id IS
  'What was read that day, or NULL when unknown. Exists because the month grid was '
  'drawn twice -- `cal-plain` against `cal-books` -- and colouring each day by the '
  'book''s cover_color turns a tally into a history. ON DELETE SET NULL rather than '
  'CASCADE: deleting a book must not delete the day you read it.';

ALTER TABLE public.reading_days ENABLE ROW LEVEL SECURITY;

-- Four policies, one per verb, rather than the single `FOR ALL USING (...)` that
-- `books` and `shelves` use and that the design record sketched.
--
-- Two reasons, and neither is a change in what is permitted. First, a `FOR ALL`
-- policy with only a USING clause leans on Postgres substituting that expression
-- for the missing WITH CHECK, so the rule that matters most here -- **a row may
-- never be written or re-parented to another user_id** -- is implied by a default
-- rather than written down. `friendships` makes the same argument for splitting its
-- UPDATE into USING plus WITH CHECK: USING says which rows you may attempt, WITH
-- CHECK says what they may become. Second, one policy per verb makes each grant a
-- decision with a place to record it, which is what let the DELETE grant below be
-- argued for instead of inherited from a blanket.

-- Own rows only. **No `is_profile_visible()` clause**, unlike the books, shelves
-- and memos policies -- see the RLS reasoning above. A friend cannot read this.
CREATE POLICY "Users can read their own reading days" ON public.reading_days
  FOR SELECT USING (user_id = auth.uid());

-- The client is the only writer, so unlike `poke_events` and `cover_read_events`
-- there is an INSERT policy at all. That is safe here in a way it is not there:
-- nothing about a reading day is unforgeable or costs money, and the primary key
-- already caps what a client can create at one row per day. A reader lying to their
-- own streak is not a threat model.
CREATE POLICY "Users can insert their own reading days" ON public.reading_days
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- Needed for the UPSERT the stamp performs, and for attaching or clearing a
-- `book_id` on a day already recorded. The WITH CHECK is the load-bearing half: it
-- is what stops an UPDATE handing one of my days to another user_id, which the
-- USING clause alone would allow.
CREATE POLICY "Users can update their own reading days" ON public.reading_days
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Granted deliberately, not by default. A reading day is a claim the reader made
-- about themselves, so they must be able to withdraw it -- a mis-stamped day is
-- otherwise permanent, and a habit ledger you cannot correct is one you stop
-- trusting. This is the opposite of the call `cover_read_events` makes, and for a
-- clear reason: deleting a metering row resets a spend limit, while deleting a
-- reading day only shortens the reader's own streak.
CREATE POLICY "Users can delete their own reading days" ON public.reading_days
  FOR DELETE USING (user_id = auth.uid());
