-- Switch visibility from `follows` to `friendships`, and delete `follows`.
--
-- **This is one transaction and it cannot be split.** Every migration is already
-- atomic; what matters here is that the *steps* cannot be spread across separate
-- migrations, and the reason is that the visibility rule exists twice:
--
--   1. `public.is_profile_visible()`                      -- the function
--   2. the `profiles` SELECT policy                       -- a hand-inlined COPY
--
-- Rewriting the function reaches five of the six call sites for free (shelves, books,
-- memos, compliments via `is_book_visible()`, and the avatars bucket). It does not
-- reach the copy. Ship the function alone and the two disagree: a stranger's *profile*
-- stays readable under the old rule while their *shelves* are already hidden under the
-- new one, which is a coherent-looking database in an incoherent state. Step 3 below
-- ends that permanently by making the policy call the function.
--
-- Order is load-bearing: the backfill reads `follows`, so the table is dropped last.
--
-- Design record: `docs/superpowers/specs/2026-08-28-friends-invites-design.md`.
-- Rehearse with `sh supabase/tests/run_local.sh` before pointing this at anything real.

-- ---------------------------------------------------------------------------
-- 1. Backfill: every mutual pair becomes a friendship
-- ---------------------------------------------------------------------------

-- Self-join for reciprocity, `least`/`greatest` for the canonical order, `distinct`
-- because each mutual pair matches this join twice -- once from each side.
--
-- **One-way follows are dropped, silently and by decision.** There is no `status`
-- column to park them in, and adding one to preserve them would reintroduce the entire
-- request queue that invite-only exists to delete. Two further facts make this
-- defensible rather than merely convenient:
--
--   * Against the import dump: 37 edges, 25 distinct pairs, 12 mutual, 13 one-way, and
--     **0** of the 13 aim at a private profile -- so nobody loses access to a shelf
--     they can currently see.
--   * `follows.created_at` exists but is useless. The import inserted only the two ids
--     (`migration_data/07_follows.sql`), so every row carries the import timestamp and
--     "who asked first" is unknowable. Even a design that wanted to preserve them as
--     directed requests could not tell which direction to preserve.
--
-- Those counts are from the dump, not production. This statement does not depend on
-- them: it backfills whatever is mutual and drops whatever is not.
INSERT INTO public.friendships (user_a, user_b)
SELECT DISTINCT
  least(f.follower_id, f.following_id),
  greatest(f.follower_id, f.following_id)
FROM public.follows f
JOIN public.follows r
  ON r.follower_id = f.following_id
 AND r.following_id = f.follower_id
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Redefine the rule
-- ---------------------------------------------------------------------------

-- Three changes from the version this replaces:
--
--   * **`friendships` instead of `follows`.** A row means both parties agreed, so the
--     grant is symmetric and there is no direction to get wrong.
--   * **`is_private` is gone from the predicate.** It was the first clause and it was
--     the bug: `is_private = false` was evaluated *before* any relationship check, so
--     with `auth.uid()` null an anonymous caller matched it and could read every
--     non-private library in the database. Under friends-only there is nothing left
--     for the column to gate -- visibility is friendship, and with no handle search
--     there is no directory to be absent from. It is dropped in step 4.
--   * **`SET search_path = ''`** with everything qualified. This is SECURITY DEFINER
--     and the original left the path unset, so it resolved through whatever schema the
--     caller had in front of it. Same fix, same reasoning as
--     `supabase/migrations/20260821100303_add_profile_handle.sql:57`.
--
-- Still `STABLE`, and still SECURITY DEFINER: it has to see `friendships` rows the
-- caller's own RLS would hide, which is the same reason it always bypassed `profiles`.
CREATE OR REPLACE FUNCTION public.is_profile_visible(target_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT
    target_user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.friendships fr
      WHERE (fr.user_a = (SELECT auth.uid()) AND fr.user_b = target_user_id)
         OR (fr.user_b = (SELECT auth.uid()) AND fr.user_a = target_user_id)
    );
$$;

COMMENT ON FUNCTION public.is_profile_visible(uuid) IS
  'Single source of truth for "may the caller see this user''s library?". Six call sites: '
  'the profiles SELECT policy, shelves, books, book_memos, is_book_visible() for '
  'compliments, and the avatars storage policy. Yourself, or a friend. Nothing else -- '
  'and notably not "public", which is what the is_private clause used to mean and what '
  'made every non-private library readable by an anonymous caller.';

-- ---------------------------------------------------------------------------
-- 3. Delete the duplicate
-- ---------------------------------------------------------------------------

-- The step this migration exists for. The old policy spelled the predicate out instead
-- of calling the function, so the rule had two homes and changing one did not reach the
-- other. After this there is exactly one definition, and the next person to change the
-- visibility rule cannot half-change it.
DROP POLICY IF EXISTS "Users can read visible profiles" ON public.profiles;

CREATE POLICY "Users can read visible profiles" ON public.profiles
  FOR SELECT USING (public.is_profile_visible(id));

-- ---------------------------------------------------------------------------
-- 4. Drop `is_private`
-- ---------------------------------------------------------------------------

-- Vestigial under friends-only, and actively misleading while it remains: a column
-- named `is_private` that no longer affects visibility is a trap for the next reader.
-- The Settings switch that wrote it ("Allow profile search") goes in the same change --
-- it gates a search that no longer exists.
--
-- CASCADE is deliberately NOT used. If anything still depends on this column, the
-- migration should fail loudly here rather than quietly dropping a policy nobody
-- remembered.
ALTER TABLE public.profiles DROP COLUMN is_private;

-- ---------------------------------------------------------------------------
-- 5. Drop `follows`
-- ---------------------------------------------------------------------------

-- Last, because step 1 reads it.
--
-- Worth recording what goes with it: `follows` SELECT was `USING (true)`, so the entire
-- social graph -- who follows whom, for every user -- was readable by anyone, including
-- an unauthenticated caller. `friendships` replaces that with participants-only.
DROP TABLE public.follows;
