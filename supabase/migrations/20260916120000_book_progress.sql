-- `books.progress`: how far through a book the reader is, as a fraction 0..1.
--
-- Design record: `docs/superpowers/specs/2026-09-12-reading-streaks-design.md`.
-- Drawings: `docs/mockups/streaks/index.html`.
--
-- ---------------------------------------------------------------------------
-- The column does not exist today, and that is the finding that shapes this one.
--
-- A search of every column in the schema matching
-- `progress|percent|pct|page|frac|bookmark|current|pos` returns exactly three:
-- `books.page_count`, `books.position`, `shelves.position`. None of them is a
-- reading position. So the `p.147 / 320`, the `46%` in the band, the ribbon on the
-- cover and the entire percent wheel currently write to a field that has nowhere
-- to live -- the drawings are all drawing a value the database cannot hold.
--
-- ---------------------------------------------------------------------------
-- Why not reuse `books.position`.
--
-- Because it is the **shelf ordering index**, and it looks like a reading position
-- only from a distance. Across all 473 books in production `max(position) = 25`,
-- values run dense from 0 *per shelf*, and they duplicate freely within one -- a
-- 49-book shelf holds its books across 26 distinct positions, six of them at `22`.
-- Writing progress there would not fail loudly; it would silently reorder the
-- reader's shelves, which is the worst available failure because nothing reports
-- it and the covers just move.
--
-- Note also that `books.reading_shelf_index` (`20260915120000`) already exists and
-- is **also not this**: it is the reader's chosen order for the Reading shelf. The
-- app therefore ends up with three integers that all sound like "where I am" and
-- are three different facts. That is the whole reason this column is not called
-- `reading_position`, a name `20260915120000` already rejected for the same trap.
--
-- ---------------------------------------------------------------------------
-- Nullable, and `null` is not `0`.
--
-- NULL means "nothing recorded", not "page one". The distinction is visible rather
-- than academic: a reading book with no progress draws **no bar at all**, where a
-- stored `0` would draw an empty one. An empty track is a claim -- it says the
-- reader started and got nowhere -- and every book in the existing corpus would
-- make that claim on the day this shipped. `NOT NULL DEFAULT 0` was rejected on
-- exactly the grounds `reader_app` and `page_count` use, and not the grounds
-- `authors` uses: here something downstream *does* tell the two states apart.
--
-- ---------------------------------------------------------------------------
-- Why a fraction rather than a page number.
--
-- `page_count` is null for **65% of the books a reader could set a position on**
-- (covered on only 34.9% of reading books), and it cannot be improved -- the
-- catalogue source has no page field. A `current_page integer` would therefore be
-- unusable for two books in three, and every surface that read it would need a
-- second design for the majority case. A fraction works for every book ever
-- printed, so the majority case stops being an exception.
--
-- The page is then a *derived display label*, `round(progress * page_count)`, and
-- simply absent when there is no count. That is the right direction of dependency:
-- the stored value never depends on a number the catalogue usually lacks.
--
-- ---------------------------------------------------------------------------
-- Always a whole percent in practice, and the cost of that is stated rather than
-- discovered.
--
-- The only writer is a 101-stop percent wheel, so stored values are whole
-- percents. The consequence: at 320 pages one stop is 3.2 pages, so "I am on page
-- 148" is **not expressible**. The reader gets 46%, which renders back as
-- `≈ p.147`, and their page number went down by one while nothing moved.
--
-- This is a deliberate cost of the storage decision and not an oversight. It is
-- also what buys the property that matters more: because only whole percents are
-- ever written, `round(progress * page_count)` is *stable*, so the band and the
-- wheel always print the same page. Storing the reader's exact page instead would
-- make the derived label change depending on which surface you looked at it from,
-- which reads as a bug rather than as arithmetic.
--
-- ---------------------------------------------------------------------------
-- `real` rather than `numeric`.
--
-- A fraction that is always a whole percent needs no exact decimal arithmetic, and
-- nothing in the database sums, averages or compares it for equality -- the streak
-- derivation does not read this column at all. Four bytes is ample and the
-- precision conversation is moot.
--
-- The CHECK is a separate statement with a name, unlike the inline checks in
-- `cover_read_events`, so that a later widening (if progress ever exceeds a
-- fraction) is a `DROP CONSTRAINT` naming a thing rather than an archaeology
-- exercise. It permits NULL explicitly rather than relying on a CHECK's
-- three-valued pass, so the intent survives being read out of context.
-- ---------------------------------------------------------------------------

ALTER TABLE public.books
  ADD COLUMN progress real;

ALTER TABLE public.books
  ADD CONSTRAINT books_progress_range
  CHECK (progress IS NULL OR (progress >= 0 AND progress <= 1));

COMMENT ON COLUMN public.books.progress IS
  'How far through the book the owner is, as a fraction 0..1, or NULL when nothing '
  'has been recorded. NULL is not 0: no progress draws no bar, where 0 would draw '
  'an empty one. A fraction rather than a page because page_count is null for 65% '
  'of reading books, so the page is a derived label -- round(progress * page_count) '
  '-- and simply absent without a count. Written only in whole percent, since a '
  '101-stop wheel is the only writer; that is what keeps the derived page stable, '
  'at the accepted cost that an exact page (p.148 of 320) is not expressible. '
  'Unrelated to `position` (shelf order) and to `reading_shelf_index` (Reading '
  'shelf order), both of which only sound like this one.';
