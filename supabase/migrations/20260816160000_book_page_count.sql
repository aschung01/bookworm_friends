-- `books.page_count`: the column the previous migration deliberately left out.
--
-- `20260816120000_book_authors.sql` rejected this, and the reasoning deserves to
-- be answered rather than quietly overridden. It said page count is not cheap the
-- way authors are, and measured why:
--
--   * Kakao -- the primary provider for Korean titles, which is what this library
--     is -- has no page field at all.
--   * Google Books has `pageCount`, but sampling 40 finished books from the
--     migrated corpus gave 35% coverage, and a volume can return `pageCount: 0`
--     instead of omitting the key.
--   * Open Library reports only a median across editions.
--
-- All of that is still true. What changed is the consumer. That migration was
-- weighing page count as a *stat on the Library Card* -- a drawn "4,180 pages"
-- summed from a third of a shelf, understating a real reader threefold in a figure
-- they could check by hand. That remains a bad idea and this column does not
-- revive it.
--
-- The consumer here is a book's rendered thickness, and the calculus inverts. That
-- value is fabricated today: `BookJitter` hashes the ISBN, so a 1,200-page novel has
-- even odds of being drawn thinner than a novella. A reader cannot tell a hashed
-- thickness from a measured one -- there is no marker, and both are simply a
-- thickness -- so partial coverage introduces no visible inconsistency. It makes a
-- third of the shelf correct and leaves the rest exactly as plausible as it already
-- was. Nothing gets worse, which is not something the page-count *stat* could claim.
--
-- The distinction worth holding onto: this column is legitimate for a value that is
-- already invented and merely becomes truer, and illegitimate for a figure presented
-- as fact.
--
-- ---------------------------------------------------------------------------
-- Nullable, unlike `authors`.
--
-- That column is `NOT NULL DEFAULT '{}'` on the grounds that nothing downstream
-- would do anything different with null versus empty, so a third state was pure
-- cost. Here the opposite holds and the argument inverts: null means "no credible
-- count" and routes the book to the ISBN hash, while any value sets thickness
-- directly. The two states drive different code, so the type has to distinguish
-- them. `0` is not usable as the sentinel -- Google Books emits it as a real value
-- for volumes it has no count for, which is exactly the confusion NULL avoids.
--
-- No CHECK constraint. A nonsense count -- 4 pages, or 20,000 -- is clamped at the
-- point of use (`bookThicknessPositionFromPages` treats anything under 20 as absent
-- and compresses the tail above 900), because the display is what has an opinion
-- about plausibility. A constraint here would instead reject the row and lose the
-- book over a bad page count, which is a far worse trade.
--
-- No index. The only reader is a per-book widget rendering rows the app has already
-- fetched in full.
-- ---------------------------------------------------------------------------

ALTER TABLE public.books
  ADD COLUMN page_count integer;

COMMENT ON COLUMN public.books.page_count IS
  'Pages as the catalogue reported them, or NULL when no credible count exists. '
  'Sets the book''s drawn thickness; NULL falls back to a hash of the ISBN. '
  'Never presented to the reader as a figure.';
