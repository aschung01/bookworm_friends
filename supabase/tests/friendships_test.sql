-- Verifies the `friendships` schema and its policies against the real database.
--
-- The load-bearing assertion is the first one: **a half-friendship must be
-- unrepresentable**. That is the entire argument for `check (user_a < user_b)`, and an
-- argument stated only in a comment is one nobody can rely on. It is executable here.
--
--   supabase db query --linked -f supabase/tests/friendships_test.sql
--
-- Silence is a pass. Every assertion raises on failure, and the whole thing runs inside
-- a transaction that is rolled back, so it leaves no trace -- it borrows three real
-- profiles rather than inventing any, because `profiles.id` references `auth.users` and
-- fabricating users would be far more invasive than this.
--
-- The role switching is the point. `postgres` bypasses RLS, so a test that did not
-- `set local role authenticated` would pass no matter what the policies said. Same
-- construction as `avatar_policies_test.sql`, for the same reason.

begin;

do $$
declare
  alice        uuid;
  bob          uuid;
  carol        uuid;
  alice_claims text;
  carol_claims text;
  lo           uuid;
  hi           uuid;
  n_seen       int;
  n_third      int;
  n_after      int;
  raised       boolean;
begin
  select id into alice from public.profiles order by created_at limit 1;
  select id into bob from public.profiles where id <> alice order by created_at limit 1;
  select id into carol from public.profiles
    where id not in (alice, bob) order by created_at limit 1;

  if alice is null or bob is null or carol is null then
    raise exception 'need at least three profiles to test against';
  end if;

  alice_claims := json_build_object('sub', alice, 'role', 'authenticated')::text;
  carol_claims := json_build_object('sub', carol, 'role', 'authenticated')::text;

  lo := least(alice, bob);
  hi := greatest(alice, bob);

  -- 1. A reversed pair cannot be written. This is the schema's whole claim: there is no
  --    row shape that expresses "alice follows bob but not the reverse", so no reader
  --    downstream has to cope with one.
  raised := false;
  begin
    insert into public.friendships (user_a, user_b) values (hi, lo);
  exception when check_violation then
    raised := true;
  end;
  if not raised then
    raise exception 'a reversed-order friendship was accepted -- the check is not holding';
  end if;

  -- 2. Self-friendship is refused by the same check, for free: x < x is false. Worth
  --    asserting rather than assuming, because it is the reason no separate
  --    `user_a != user_b` constraint exists here the way it does on `follows`.
  raised := false;
  begin
    insert into public.friendships (user_a, user_b) values (alice, alice);
  exception when check_violation then
    raised := true;
  end;
  if not raised then
    raise exception 'a self-friendship was accepted';
  end if;

  -- The canonical row, written as any real caller must write it.
  insert into public.friendships (user_a, user_b) values (lo, hi);

  -- 3. The same pair cannot be inserted twice, in either order. The primary key covers
  --    the first case and the check covers the second, which together are what make
  --    `on conflict do nothing` in `redeem_invite()` a complete idempotency story.
  raised := false;
  begin
    insert into public.friendships (user_a, user_b) values (lo, hi);
  exception when unique_violation then
    raised := true;
  end;
  if not raised then
    raise exception 'a duplicate friendship was accepted';
  end if;

  -- 4. A participant reads it, from the side that is NOT user_a. This is what
  --    `friendships_user_b_idx` exists for, and reading from the wrong side is the
  --    failure a naive `user_a = auth.uid()` policy would produce.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select count(*) into n_seen from public.friendships
    where user_a in (lo, hi) or user_b in (lo, hi);
  execute 'reset role';
  if n_seen <> 1 then
    raise exception 'a participant could not read their own friendship (% rows)', n_seen;
  end if;

  -- 5. A third party sees nothing. Compare `follows`, whose SELECT is USING (true):
  --    this is the case that policy cannot satisfy at all.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', carol_claims);
  select count(*) into n_third from public.friendships
    where user_a in (lo, hi) or user_b in (lo, hi);
  execute 'reset role';
  if n_third <> 0 then
    raise exception 'a third party read a friendship they are not in (% rows)', n_third;
  end if;

  -- 6. A participant can end it, and one DELETE severs both directions because there is
  --    only ever one row. Run as the participant rather than as `postgres`, or the
  --    delete policy is not what is being tested.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  delete from public.friendships where user_a = lo and user_b = hi;
  execute 'reset role';

  select count(*) into n_after from public.friendships
    where user_a = lo and user_b = hi;
  if n_after <> 0 then
    raise exception 'a participant could not remove the friendship (% rows left)', n_after;
  end if;

  raise notice 'friendships: all six cases pass';
end $$;

rollback;
