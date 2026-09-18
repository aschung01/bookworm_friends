-- Verifies `profiles.handle` against the real database.
--
-- The handle exists for one reason: the exported Library Card's machine-readable strip is
-- a fixed-width **Latin-only** grid, and `cardStripToken` in Dart *rejects* anything that
-- is not already strip-safe rather than transliterating it. So the format check here and
-- that function are **the same rule stated twice**, in two languages, in two repositories
-- of truth -- which is exactly the kind of pair that drifts. The pattern is quoted in
-- both places and asserted in both: `test/shareable_library_card_test.dart` holds the
-- Dart half.
--
--   supabase db query --linked -f supabase/tests/handle_test.sql
--
-- Silence is a pass. Every assertion raises on failure, and the whole thing runs inside a
-- transaction that is rolled back, so it leaves no trace -- it borrows one real profile
-- rather than inventing any, because `profiles.id` references `auth.users` and fabricating
-- users would be far more invasive than this.

begin;

do $$
declare
  victim_id   uuid;
  kept        text;
  other_id    uuid;
  taken       text;
  generated   text;
  rejected    text[] := array[
    'ab',                       -- two characters
    'PaperFox',                 -- uppercase
    'paper fox',                -- a space
    'paper-fox',                -- a hyphen
    'paper.fox',                -- a dot
    '독서하는_사람',              -- non-ASCII, which is the whole reason this column exists
    'paper_fox_012345678901'    -- 22 characters
  ];
  candidate   text;
  n_null      int;
  n_dupe      int;
  n_bad       int;
begin
  select id, handle into victim_id, kept
    from public.profiles order by created_at limit 1;
  select id, handle into other_id, taken
    from public.profiles where id <> victim_id order by created_at limit 1;

  if victim_id is null or other_id is null then
    raise exception 'need at least two profiles to test against';
  end if;

  -- 1. The backfill left no gap and no collision, and every row satisfies the format.
  --
  -- Asserted over the whole table rather than over a fixture: `NOT NULL` and the unique
  -- index would have refused the migration if this were false, so what is really being
  -- checked is that the migration *ran* -- which is the failure mode of a schema change
  -- that was written and never pushed.
  select count(*) filter (where handle is null) into n_null from public.profiles;
  select count(*) into n_dupe from (
    select handle from public.profiles group by handle having count(*) > 1
  ) duplicates;
  select count(*) filter (where handle !~ '^[a-z0-9_]{3,20}$')
    into n_bad from public.profiles;

  if n_null <> 0 then
    raise exception 'backfill left % profiles without a handle', n_null;
  end if;
  if n_dupe <> 0 then
    raise exception 'backfill produced % duplicated handles', n_dupe;
  end if;
  if n_bad <> 0 then
    raise exception '% handles do not match the strip format', n_bad;
  end if;

  -- 2. The format check refuses everything the strip cannot print.
  --
  -- Each of these is a real shape from this database or from the plan's argument, not an
  -- invented edge: `독서하는_사람` is what 126 of 136 usernames look like, `paper fox` is
  -- what 90 of them contain, and `PaperFox` is the case the plan wanted `citext` for --
  -- which is unnecessary precisely because this check refuses it outright.
  foreach candidate in array rejected loop
    begin
      update public.profiles set handle = candidate where id = victim_id;
      raise exception 'the format check accepted %L', candidate;
    exception
      when check_violation then null;   -- expected
    end;
    -- The failed UPDATE aborted its own subtransaction, so the row is unchanged; assert
    -- that rather than assume it.
    if (select handle from public.profiles where id = victim_id) <> kept then
      raise exception 'a rejected handle still changed the row';
    end if;
  end loop;

  -- 3. It accepts the shapes it should: three characters, twenty, digits, underscores.
  foreach candidate in array array['abc', 'a_1', 'paper_fox_412', 'abcdefghij0123456789']
  loop
    update public.profiles set handle = candidate where id = victim_id;
    if (select handle from public.profiles where id = victim_id) <> candidate then
      raise exception 'the format check rejected %L', candidate;
    end if;
  end loop;
  update public.profiles set handle = kept where id = victim_id;

  -- 4. Uniqueness is enforced, and it is case-insensitive *by construction* rather than
  -- by collation: there is exactly one representation of any handle, because the check
  -- above admits only lowercase.
  begin
    update public.profiles set handle = taken where id = victim_id;
    raise exception 'two profiles were allowed the same handle';
  exception
    when unique_violation then null;    -- expected
  end;

  begin
    update public.profiles set handle = upper(taken) where id = victim_id;
    raise exception 'an uppercase handle was stored at all';
  exception
    when check_violation then null;     -- expected, and this is why citext is not needed
  end;

  -- 5. The generator returns something a person would read as a name.
  --
  -- The point of the assertion is the *shape*, not the words: at relaunch every reader is
  -- a new signup and almost none will open the editor, so whatever this returns is what
  -- appears on nearly every card that leaves the app. `reader_4f2c1204` would satisfy the
  -- format check and fail this.
  generated := public.generate_handle();
  if generated !~ '^[a-z0-9_]{3,20}$' then
    raise exception 'the generator produced %L, which the check would refuse', generated;
  end if;
  if generated !~ '^[a-z]+_[a-z]+_[0-9]{3}$' then
    raise exception 'the generator produced %L, which is not pronounceable', generated;
  end if;
  if exists (select 1 from public.profiles where handle = generated) then
    raise exception 'the generator returned a handle already taken';
  end if;

  -- 6. It is not reachable from the Data API.
  --
  -- A SECURITY DEFINER function is only safe if the API roles cannot call it, and Postgres
  -- grants EXECUTE to PUBLIC on every new function by default -- so this is a revoke that
  -- is easy to forget and impossible to notice.
  if has_function_privilege(
       'authenticated', 'public.generate_handle()', 'execute'
     ) then
    raise exception 'authenticated can call generate_handle() as an RPC';
  end if;
  if has_function_privilege('anon', 'public.generate_handle()', 'execute') then
    raise exception 'anon can call generate_handle() as an RPC';
  end if;

  raise notice 'handle: all assertions passed';
end;
$$;

rollback;
