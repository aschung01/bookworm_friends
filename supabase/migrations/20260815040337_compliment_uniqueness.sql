-- Praise: one per person per book, readable by anyone who can see the book.
--
-- `book_compliments.book_id` references `books.id`, and `books` rows are
-- per-user, so a praise was already scoped to one person's copy of a title --
-- jisoo's Pachinko and minho's Pachinko are different rows and keep separate
-- praise. What was missing is uniqueness: nothing stopped the same person
-- inserting unlimited rows for the same book, and the details view rendered a
-- chip per row, so a double tap showed the same emoji twice.
--
-- Reads were also narrower than intended. The old policy allowed the book's
-- owner and the sender only, so a third visitor saw nothing but their own
-- praise -- which makes any aggregate count ("clap 3") different for every
-- viewer. Praise now follows the same visibility rule as the book it sits on.

-- 1. Collapse existing duplicates, keeping each person's most recent choice:
--    with toggle-and-replace semantics the newest row is their current one.
DELETE FROM public.book_compliments AS c
USING public.book_compliments AS newer
WHERE c.book_id = newer.book_id
  AND c.from_user_id = newer.from_user_id
  AND (c.created_at, c.id) < (newer.created_at, newer.id);

-- 2. One praise per person per book. Also indexes (book_id, from_user_id),
--    which is exactly the lookup the toggle does before writing.
ALTER TABLE public.book_compliments
  ADD CONSTRAINT book_compliments_book_id_from_user_id_key
  UNIQUE (book_id, from_user_id);

-- 3. Resolve a book's owner without tripping over the RLS on `books`, the same
--    way `is_profile_visible` sidesteps it for profiles.
CREATE OR REPLACE FUNCTION public.is_book_visible(target_book_id uuid)
RETURNS boolean AS $$
  SELECT public.is_profile_visible(b.user_id)
  FROM public.books b
  WHERE b.id = target_book_id;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 4. Widen reads to match the book's own visibility. The `from_user_id` clause
--    is kept so you never lose sight of praise you sent, even if the owner
--    later goes private or drops the follow.
DROP POLICY IF EXISTS "Book owner can read compliments" ON public.book_compliments;

CREATE POLICY "Others can read visible compliments" ON public.book_compliments
  FOR SELECT USING (
    public.is_book_visible(book_id)
    OR from_user_id = auth.uid()
  );

-- 5. Replacing an emoji is an UPDATE, and there was never an UPDATE policy --
--    only insert, select and delete. `INSERT ... ON CONFLICT DO UPDATE` takes
--    the update path through RLS, so without this the toggle's swap would fail
--    with a policy violation rather than a duplicate-key error.
CREATE POLICY "Sender can update own compliments" ON public.book_compliments
  FOR UPDATE USING (from_user_id = auth.uid())
  WITH CHECK (from_user_id = auth.uid());
