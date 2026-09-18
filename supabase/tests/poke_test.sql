-- Verifies `poke_user()` after `20260828120200_poke_requires_friendship.sql`.
--
--   supabase db query --linked -f supabase/tests/poke_test.sql
--
-- Silence is a pass. Rolled back.
--
-- The push assertion depends on `net.http_post` being the recording stub from
-- `_harness.sql`, so probes 4 and 5 are skipped when running against a real database,
-- where the real `pg_net` would attempt a request. Everything else runs either way.
--
-- Probe 5 is the one worth having. The bug it pins was not that an anonymous caller
-- could poke -- they could not write the audit row -- but that they could still reach
-- the *push*, because the two effects were under different guards. It is invisible in
-- `poke_events` and only observable by watching what the function tried to send.

begin;

do $$
declare
  alice        uuid;
  bob          uuid;
  alice_claims text;
  anon_pushes  int;
  n_events     int;
  n_pushes     int;
  has_stub     boolean;
begin
  select id into alice from public.profiles order by created_at limit 1;
  select id into bob from public.profiles where id <> alice order by created_at limit 1;

  if alice is null or bob is null then
    raise exception 'need at least two profiles to test against';
  end if;

  alice_claims := json_build_object('sub', alice, 'role', 'authenticated')::text;

  select exists (
    select 1 from information_schema.tables
    where table_schema = 'net' and table_name = 'http_requests'
  ) into has_stub;

  update public.profiles set username = 'bob_poke_probe', fcm_token = 'probe-token'
   where id = bob;
  delete from public.friendships
   where user_a = least(alice, bob) and user_b = greatest(alice, bob);
  delete from public.poke_events
   where from_user_id in (alice, bob) and to_user_id in (alice, bob);

  -- 1. A non-friend poke records nothing. The behaviour change this migration exists
  --    for: `poke_events.sql:66-69` recorded the gap and deferred it to here.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  perform public.poke_user('bob_poke_probe');
  execute 'reset role';

  select count(*) into n_events from public.poke_events
   where from_user_id = alice and to_user_id = bob;
  if n_events <> 0 then
    raise exception 'a non-friend poke was recorded (% rows)', n_events;
  end if;

  -- 2. It is a silent no-op, not a raise. Reaching this line at all proves it: an
  --    exception above would have aborted the block.

  -- 3. A friend poke records one event.
  insert into public.friendships (user_a, user_b)
    values (least(alice, bob), greatest(alice, bob))
    on conflict do nothing;

  if has_stub then
    delete from net.http_requests;
  end if;

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  perform public.poke_user('bob_poke_probe');
  execute 'reset role';

  select count(*) into n_events from public.poke_events
   where from_user_id = alice and to_user_id = bob;
  if n_events <> 1 then
    raise exception 'a friend poke recorded % events, expected 1', n_events;
  end if;

  if has_stub then
    -- 4. ...and one push, whose title is not null. A null title is what the old
    --    unguarded path produced, so this asserts the payload and not merely the call.
    select count(*) into n_pushes from net.http_requests
     where body ->> 'type' = 'poke';
    if n_pushes <> 1 then
      raise exception 'a friend poke sent % pushes, expected 1', n_pushes;
    end if;
    if exists (select 1 from net.http_requests where body ->> 'title' is null) then
      raise exception 'a poke shipped with a null title';
    end if;

    -- 5. An anonymous caller reaches neither effect.
    --
    --    The old code guarded the insert on `poker_id IS NOT NULL` but the push only on
    --    `target_token IS NOT NULL`, so this exact call fired a push with a null title.
    delete from net.http_requests;
    execute 'set local role anon';
    execute 'set local request.jwt.claims = ''''';
    perform public.poke_user('bob_poke_probe');
    execute 'reset role';

    select count(*) into anon_pushes from net.http_requests;
    if anon_pushes <> 0 then
      raise exception
        'an anonymous caller reached the push path (% requests) -- the guard split is back',
        anon_pushes;
    end if;
  end if;

  -- 6. Self-poke is refused, for free: the friendships check requires user_a < user_b,
  --    so a pair with itself matches nothing.
  update public.profiles set username = 'alice_poke_probe' where id = alice;
  delete from public.poke_events where from_user_id = alice and to_user_id = alice;

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  perform public.poke_user('alice_poke_probe');
  execute 'reset role';

  select count(*) into n_events from public.poke_events
   where from_user_id = alice and to_user_id = alice;
  if n_events <> 0 then
    raise exception 'a self-poke was recorded (% rows)', n_events;
  end if;

  if has_stub then
    raise notice 'poke_user: all six cases pass';
  else
    raise notice 'poke_user: four cases pass (push probes skipped -- no net stub)';
  end if;
end $$;

rollback;
