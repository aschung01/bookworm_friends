-- `books.reading_shelf_index`: a book's place on the Reading shelf.
--
-- The Reading shelf (`reading_shelf_row.dart`) draws every book at status 1, taken off
-- whichever queue shelf it belongs to. Its order has until now been a *consequence* of
-- where the books came from: `readingBooksOf` walks the shelves in order and collects,
-- so the row is sorted by (shelf position, book position) and the reader has no say in
-- it. That function's own comment names the gap -- "this makes the Reading shelf's order
-- a consequence of where the books came from, which is the one thing a reader cannot
-- change about it". This column is what closes it, and drag-to-reorder is what writes it.
-- See `docs/superpowers/specs/2026-09-15-reading-shelf-reorder-design.md`.
--
-- ---------------------------------------------------------------------------
-- Why a new column instead of reusing `books.position`.
--
-- `position` means "place within my own shelf". The Reading shelf is a view over books
-- drawn from *several* shelves, so two books lifted from different planks can hold the
-- same `position`, and there is no single row for that column to order.
--
-- Worse, writing it would spend a promise. `withoutReadingBooks` takes an in-progress
-- book off its shelf while keeping its `shelf_id`, and its doc undertakes that "clearing
-- the status puts the cover back on that plank in the position it was authored in". That
-- promise is the stated benefit of retiring `withReadingFirst`, whose documented wart was
-- exactly this: it wrote positions from a promoted row, so the first drag persisted the
-- promotion and clearing a book's reading status left it where the promotion put it rather
-- than where the reader filed it. A Reading-shelf drag that rewrote `position` would bring
-- that wart back in a new costume. Nothing here touches `position`.
--
-- ---------------------------------------------------------------------------
-- Why `reading_shelf_index` and not `reading_position`.
--
-- `reading_position` was the first candidate and is a trap in a *reading* app: it reads as
-- progress through the text -- the ebook sense of "where I am" -- rather than as an
-- ordinal among covers. Naming the column after the shelf it indexes removes the reading.
--
-- The obvious follow-on, renaming `books.position` to `shelf_index` for symmetry, is
-- deliberately NOT done here. `Book.fromJson` reads `position: json['position'] as int? ?? 0`,
-- and that defensive default exists for *forward* compatibility -- rows written before a
-- column existed. Rename the column and any already-distributed build reads `position` as
-- absent, so every book collapses to 0, the client-side sort degenerates into arbitrary
-- order, and `update({'position': i})` starts returning 400. Adding a column is backward
-- compatible; renaming one is a hard break. An old build simply ignores this column and
-- orders the Reading shelf the way it does today, which is the failure mode worth having.
--
-- ---------------------------------------------------------------------------
-- Nullable, no default.
--
-- NULL means "has no place on the Reading shelf", which is the truth for every book that
-- is not at status 1. `NOT NULL DEFAULT 0` would instead assert that every finished and
-- unstarted book in the library sits first on a shelf it is not standing on, and the
-- Reading shelf would have to filter that assertion back out on every read.
--
-- The client sorts NULLs last with shelf order as the tiebreak, so a row this migration
-- misses -- or one written by a build that predates the column -- still draws in exactly
-- the place it draws today rather than jumping to the head of the row.
--
-- ---------------------------------------------------------------------------
-- Backfilled, unlike `cover_color`.
--
-- `20260822120000_book_cover_color.sql` refused a server-side backfill on the grounds that
-- no server-side average could equal Flutter's own 1x1 GPU downsample, so every book would
-- visibly change tone on the day it ran. The opposite is true here: the value being
-- written *is* the order the reader is already looking at, so backfilling is precisely what
-- makes deploy day invisible. Skipping it would leave every existing reader's Reading shelf
-- ordered by the NULL fallback -- which happens to be the same order -- right up until
-- their first drag, at which point the books that were never written would sort last and
-- the row would rearrange itself around the one book that moved.
--
-- Partitioned by `user_id`, because the Reading shelf belongs to one reader: indices only
-- have to be unique and dense within a single library. `created_at` is the final tiebreak
-- so the numbering is deterministic even if two books somehow share a shelf position.
--
-- ---------------------------------------------------------------------------
-- No index, and no uniqueness constraint.
--
-- No index: the library fetches every shelf and book for the signed-in user in one query
-- (`shelves` with `books(*)`) and orders the Reading shelf client-side. There is no query
-- that filters or sorts on this column server-side.
--
-- No UNIQUE (user_id, reading_shelf_index): a reorder rewrites the whole set one row at a
-- time, so any such constraint would be violated midway through a perfectly good reorder
-- unless every write became one deferred transaction. Duplicates are harmless -- the
-- client's sort has a deterministic tiebreak -- and the next reorder renumbers to 0..n-1.
-- The same reasoning `cover_color` used to refuse a CHECK applies: a constraint here would
-- lose a reorder over a cosmetic column.
--
-- Values may also go negative, by design. Opening a book writes `min - 1` so it lands at
-- the head of the shelf in a single UPDATE rather than shifting every other row; the next
-- reorder normalises the set back to 0..n-1.
-- ---------------------------------------------------------------------------

ALTER TABLE public.books
  ADD COLUMN reading_shelf_index integer;

COMMENT ON COLUMN public.books.reading_shelf_index IS
  'A book''s place on the Reading shelf, ascending from 0, or NULL when it has none '
  '(any book not at status 1). Independent of `position`, which is the book''s place '
  'within its own shelf and is never written by a Reading-shelf reorder. Not unique and '
  'may be negative: opening a book writes min-1 to put it at the head, and a reorder '
  'renumbers the set. NULLs sort last, falling back to shelf order.';

-- Backfill: the order readers can currently see, so nothing moves on deploy.
WITH ordered AS (
  SELECT b.id,
         ROW_NUMBER() OVER (
           PARTITION BY b.user_id
           ORDER BY s.position, b.position, b.created_at
         ) - 1 AS rn
    FROM public.books b
    JOIN public.shelves s ON s.id = b.shelf_id
   WHERE b.status = 1
)
UPDATE public.books b
   SET reading_shelf_index = ordered.rn
  FROM ordered
 WHERE ordered.id = b.id;
