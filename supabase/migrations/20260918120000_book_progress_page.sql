-- `books.progress_page`: the page the reader actually typed, or NULL if they
-- answered in percent.
--
-- Design record: `docs/mockups/page-progress/index.html` (screen `row-progress`).
-- Supersedes part of `20260916120000_book_progress.sql` -- see below.
--
-- ---------------------------------------------------------------------------
-- This column stores *provenance*, not position. `progress` is still the position.
--
-- The position needs no new column: a page stored as `page / page_count` in the
-- existing `real` round-trips exactly (verified for every page of 320, 432, 912 and
-- 1000 -- zero failures). So this column exists for one reason only: the display
-- rule that `ProgressFieldRow` prints `p.200` when the reader *said* p.200, and
-- `46%` when they said 46%. The row shows a reader their own answer in their own
-- unit, which is also why it is allowed to differ from the band's read-out, which
-- always prefers a page when it has a count.
--
-- ---------------------------------------------------------------------------
-- Why it cannot be inferred, which is the finding that forced the column.
--
-- The obvious alternative is to derive provenance from the stored double: percent
-- mode writes `stop / 100`, so `progress * 100` lands on a whole number, and a page
-- entry generally does not. That collapses precisely where books are commonest.
-- Counted over every page of a book, a page entry is indistinguishable from a
-- percent for:
--
--     432pp -> 0.9%      320pp -> 6.25%
--     200pp -> 50%       100pp or 50pp -> 100%
--
-- A 100-page book is the degenerate case: `page / 100` is *always* a whole percent,
-- so inference is wrong for every page of it. Anything shorter than 101 pages is
-- similarly hopeless. So provenance is stored.
--
-- ---------------------------------------------------------------------------
-- Why the page and not a boolean.
--
-- `progress_is_page boolean` would answer the display rule in one bit and be
-- smaller. This stores the integer instead, for three reasons:
--
--   1. It records what the reader typed. The boolean would send every read back
--      through `round(progress * page_count)` -- the same float round-trip the
--      feature exists to escape -- to recover a number we already had.
--   2. It survives a later correction to `page_count`. A stored fraction silently
--      re-points at a different page when the count changes; a stored page does
--      not. The reader said p.200 of a book, and that stays true.
--   3. `progress_page IS NOT NULL` is then the entire display rule, with no second
--      column to consult and no derived value to compare against.
--
-- The cost is two columns that must not disagree, so the write path sets both or
-- neither -- see `updateBookStatus`, where `progress_page` is only ever sent in the
-- same UPDATE as `progress`, and NULL there is a real instruction meaning "the
-- reader answered in percent".
--
-- ---------------------------------------------------------------------------
-- `>= 1`, and that is a product decision rather than hygiene.
--
-- p.0 does not exist. 0% does, and `progress` allows it -- "opened it and got
-- nowhere" is a real position, and NULL is not 0. So the page wheel and its keypad
-- refuse 0 rather than mapping it to null or to 0%: a reader who means the very
-- start says so in percent, and page mode never has to express a page no book has.
-- The CHECK is where that decision is written down so it cannot be lost in a UI
-- refactor.
--
-- Deliberately **not** also constrained against `page_count`. Requiring
-- `progress_page <= page_count` reads well and would make lowering a book's
-- `page_count` fail on any row already past the new end -- turning a legitimate
-- metadata correction into an error the reader cannot act on. The keypad clamps to
-- the count at entry, which is where a bound belongs; the database keeps only the
-- part that can never be a matter of taste.
--
-- The CHECK is named, like `books_progress_range` and unlike the inline checks in
-- `cover_read_events`, so a later widening is a DROP CONSTRAINT naming a thing.
--
-- ---------------------------------------------------------------------------
-- What this supersedes.
--
-- `20260916120000_book_progress.sql` states, in its header and in its COLUMN
-- comment, that `progress` is "written only in whole percent, since a 101-stop
-- wheel is the only writer", and rests a stability argument on it. That is no
-- longer true: page mode writes `page / page_count`, which is not a whole percent.
-- The comment on `progress` is rewritten below rather than left to rot, because the
-- old text would actively mislead anyone reasoning about rounding.
--
-- The property it was protecting is preserved differently. The worry was that the
-- band and the wheel could round the same value to different pages; the answer is
-- still that both read `bookProgressPage`, one function, and now that an exact page
-- is stored the band prints the reader's own number rather than a derived one.
-- ---------------------------------------------------------------------------

ALTER TABLE public.books
  ADD COLUMN progress_page integer;

ALTER TABLE public.books
  ADD CONSTRAINT books_progress_page_positive
  CHECK (progress_page IS NULL OR progress_page >= 1);

COMMENT ON COLUMN public.books.progress_page IS
  'The page the reader typed, or NULL if they answered in percent. Provenance, not '
  'position -- `progress` is the position, and a page stored as page/page_count '
  'round-trips exactly, so this column exists only so ProgressFieldRow can print '
  'the reader''s own unit back to them. Cannot be inferred from `progress`: a page '
  'entry is indistinguishable from a whole percent for 50% of a 200-page book and '
  '100% of a 100-page one. Stored as the integer rather than a boolean so a later '
  'correction to page_count cannot silently re-point it. Only ever written in the '
  'same UPDATE as `progress`, where NULL means "answered in percent". >= 1 because '
  'p.0 does not exist, though 0% does.';

COMMENT ON COLUMN public.books.progress IS
  'How far through the book the owner is, as a fraction 0..1, or NULL when nothing '
  'has been recorded. NULL is not 0: no progress draws no bar, where 0 would draw '
  'an empty one. A fraction rather than a page because page_count is null for 65% '
  'of reading books, so every book ever printed can hold a position here. Written '
  'either as a whole percent (the 101-stop wheel) or as page/page_count (page mode, '
  'which round-trips exactly); `progress_page` records which, because it cannot be '
  'inferred from the value. Unrelated to `position` (shelf order) and to '
  '`reading_shelf_index` (Reading shelf order), both of which only sound like this '
  'one.';
