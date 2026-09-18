-- profiles.handle: the Latin identity the exported Library Card's strip prints.
--
-- **Not a URL, and the first version of this plan justified it as one.** Nothing about
-- the share is a link any more -- the card carries `@LIBSTACK.APP` printed in its own
-- pixels and the payload is a bare PNG -- so "username cannot be a URL" stopped being a
-- reason. The real and much narrower one is the machine-readable strip along the bottom
-- of the card: like a passport's, it is a fixed-width **Latin-only** grid, and a Korean
-- display name cannot go in one at all.
--
-- Measured against this database on 2026-08-21, over 136 profiles:
--
--     non-ASCII username ......... 126  (92.6%)
--     username containing a space .. 90
--     already `^[a-z0-9_]{3,20}$` ... 2
--
-- Two. So `cardStripToken` in Dart *rejects* rather than converts -- sanitising
-- `독서하는 08269f2d` would print `08269F2D` on the card, which reads as a rendering
-- fault -- and without this column the strip has no identity segment for 134 of 136
-- readers.
--
-- **`username` is not demoted.** It keeps its unique index and stays the key for
-- `poke_user()` and user search; it is printed on the card as `Holder`, in its own
-- script, where the app's own type can set it. Two identities, two jobs, and nothing
-- that already works is migrated.

-- ---------------------------------------------------------------------------
-- The column
-- ---------------------------------------------------------------------------

-- Added nullable, backfilled, then tightened. The alternative -- `NOT NULL DEFAULT` in
-- one statement -- would need the generator to already exist and would put a
-- volatile default on the column, which is not what the trigger below wants.
ALTER TABLE public.profiles ADD COLUMN handle text;

-- ---------------------------------------------------------------------------
-- The generator
-- ---------------------------------------------------------------------------

-- **Pronounceable, and that is a product decision rather than a nicety.** The obvious
-- generator is `reader_` plus hex, and this database already shows what that produces:
-- 72 of the migrated display names are machine-made in exactly that shape, and they read
-- as a fault rather than as a name. At relaunch every reader is a new signup, each gets a
-- handle at creation, and almost none of them will ever open the editor -- so whatever
-- this function returns is what appears on nearly every card that leaves the app.
-- `paper_fox_412` is a name; `reader_4f2c1204` is a database artifact.
--
-- Word lists live in the migration rather than in a table, so the backfill is
-- reproducible from the file and there is no new table to keep in sync with a Dart
-- constant. Both lists are ASCII lowercase and at most six characters, which caps the
-- result at 6+1+6+1+3 = 17 -- inside the 20 the check below enforces and inside the strip
-- column budget the card lays out.
--
-- SECURITY DEFINER because the collision check has to see **every** row: under RLS an
-- `authenticated` caller sees only visible profiles, so an invoker-rights version would
-- happily hand back a handle already taken by a private stranger. Execute is revoked from
-- the API roles immediately below, which is what keeps a definer function out of reach
-- rather than merely out of sight -- and `search_path` is pinned empty with everything
-- qualified, so nothing here resolves through a caller-controlled schema.
CREATE OR REPLACE FUNCTION public.generate_handle()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  adjectives text[] := ARRAY[
    'amber', 'brisk', 'calm', 'dusty', 'eager', 'faded', 'gilded', 'humble',
    'inked', 'jolly', 'keen', 'linen', 'mellow', 'noble', 'olive', 'paper',
    'quiet', 'rusty', 'sunlit', 'tidy', 'umber', 'vivid', 'warm', 'woven'
  ];
  nouns text[] := ARRAY[
    'atlas', 'badger', 'crane', 'draft', 'ember', 'finch', 'folio', 'gutter',
    'heron', 'index', 'jacket', 'kestrel', 'lark', 'margin', 'moth', 'otter',
    'quill', 'ribbon', 'spine', 'tome', 'usher', 'vellum', 'wren', 'yarrow'
  ];
  candidate text;
BEGIN
  -- Forty tries against roughly 24 x 24 x 1000 = 576,000 combinations and a few hundred
  -- rows. A collision is already vanishingly unlikely; forty of them in a row is not a
  -- case worth designing for, which is why the fallback below is allowed to be ugly.
  FOR _attempt IN 1..40 LOOP
    candidate :=
      adjectives[1 + floor(random() * array_length(adjectives, 1))::int]
      || '_'
      || nouns[1 + floor(random() * array_length(nouns, 1))::int]
      || '_'
      || lpad(floor(random() * 1000)::int::text, 3, '0');

    IF NOT EXISTS (
      SELECT 1 FROM public.profiles WHERE handle = candidate
    ) THEN
      RETURN candidate;
    END IF;
  END LOOP;

  -- The last resort, and it is deliberately the shape this function exists to avoid: a
  -- handle nobody would choose, but a unique one, because `NOT NULL` has to be satisfied
  -- and failing a signup over a name is not a trade anyone would take. 'reader_' plus 12
  -- hex characters is 19, inside the limit, and `[a-z0-9_]` throughout.
  RETURN 'reader_'
    || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
END;
$$;

-- Not reachable from the Data API. Postgres grants EXECUTE on new functions to PUBLIC by
-- default, which would expose this as an RPC -- and a definer function exposed as an RPC
-- is the trap the security checklist warns about. The trigger below is SECURITY DEFINER
-- and owned by the migration role, so it can still call it.
REVOKE ALL ON FUNCTION public.generate_handle() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_handle() FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- The backfill
-- ---------------------------------------------------------------------------

-- **Every existing reader gets a generated handle and none of them is asked**, because
-- there is nobody to ask: the app was pulled from the store years ago and these rows are
-- a dormant migrated corpus. The constraint is `NOT NULL`, the corpus has to satisfy it,
-- and a nullable column with a "set your handle" prompt would put a gate in front of the
-- one feature this phase exists to ship.
--
-- Row by row rather than one `UPDATE ... SET handle = public.generate_handle()`: a
-- set-returning update evaluates the function per row but cannot see the handles the same
-- statement is assigning, so two rows in one statement can collide. The loop makes each
-- call see the previous one's result.
DO $$
DECLARE
  profile_id uuid;
BEGIN
  FOR profile_id IN
    SELECT id FROM public.profiles WHERE handle IS NULL
  LOOP
    UPDATE public.profiles
       SET handle = public.generate_handle()
     WHERE id = profile_id;
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- The constraints
-- ---------------------------------------------------------------------------

-- **The same rule `cardStripToken` states in Dart, and the pair is the thing most likely
-- to drift.** `test/shareable_library_card_test.dart` asserts the Dart half and
-- `supabase/tests/handle_test.sql` asserts this one; both quote the pattern so a
-- mismatch is visible in a diff.
--
-- Lowercase-only is what makes a plain UNIQUE index case-insensitive, which is why
-- **`citext` was dropped**. The plan called for `handle citext UNIQUE NOT NULL` so that
-- `@PaperFox` and `@paperfox` could not both exist -- but this check forbids `@PaperFox`
-- from existing at all, so citext would be guarding against a value the column cannot
-- hold. One canonical representation is a stronger invariant than two that compare equal,
-- and it costs no extension.
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_handle_format
  CHECK (handle ~ '^[a-z0-9_]{3,20}$');

ALTER TABLE public.profiles ALTER COLUMN handle SET NOT NULL;

CREATE UNIQUE INDEX profiles_handle_key ON public.profiles (handle);

-- ---------------------------------------------------------------------------
-- New signups
-- ---------------------------------------------------------------------------

-- A handle at creation, so the "no handle" state never exists and no share is ever gated
-- on setting one. This is the same trigger `20260505053018_auth_trigger.sql` created,
-- with `handle` added and `search_path` pinned -- the original left it unset, which is a
-- SECURITY DEFINER function resolving through whatever schema the caller has in front.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (id, handle)
  VALUES (NEW.id, public.generate_handle());
  RETURN NEW;
END;
$$;
