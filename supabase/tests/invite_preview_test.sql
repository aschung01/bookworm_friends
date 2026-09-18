-- Verifies `invite_preview()` -- the one function in this schema granted to `anon`.
--
--   supabase db query --linked -f supabase/tests/invite_preview_test.sql
--
-- Silence is a pass. Rolled back.
--
-- **The assertions that matter are 1 and 6.** The function exists to let a landing page
-- name the inviter without reading `friend_invites`, which is owner-scoped precisely so
-- that holding a token cannot tell you whose it is. So the test has to show two things
-- at once: that an anonymous caller *can* get a display name, and that the same call
-- discloses nothing else and changes nothing. Every other case is a liveness branch.

begin;

do $$
declare
  alice   uuid;
  bob     uuid;
  aname   text;
  inv     public.friend_invites;
  pv      public.invite_preview_result;
  used    int;
  claims  text;
begin
  select id into alice from public.profiles order by created_at limit 1;
  select id into bob from public.profiles where id <> alice order by created_at limit 1;
  if alice is null or bob is null then
    raise exception 'need at least two profiles to test against';
  end if;
  select username into aname from public.profiles where id = alice;

  claims := json_build_object('sub', alice, 'role', 'authenticated')::text;
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', claims);
  select * into inv from public.create_invite();
  execute 'reset role';

  -- 1. An anonymous caller gets the inviter's display name. This is the whole reason
  --    the function exists: with a plain select, RLS returns nothing here.
  execute 'set local role anon';
  execute 'set local request.jwt.claims = ''''';
  select * into pv from public.invite_preview(inv.token);
  execute 'reset role';

  if pv.inviter_username is distinct from aname then
    raise exception 'anon could not read the inviter name (got %)', pv.inviter_username;
  end if;
  if not pv.is_live then
    raise exception 'a fresh invite did not preview as live';
  end if;

  -- 2. A plain anon select on the table still returns nothing. The window is the
  --    function, not a hole in the policy -- if this ever starts returning rows, the
  --    RLS has been loosened and the function is no longer the only way through.
  execute 'set local role anon';
  execute 'set local request.jwt.claims = ''''';
  perform 1 from public.friend_invites where token = inv.token;
  if found then
    raise exception 'anon can read friend_invites directly; RLS has been loosened';
  end if;
  execute 'reset role';

  -- 3. A preview is read-only. Five looks must not spend a use, or opening the page
  --    twice would cost the sender a redemption.
  select used_count into used from public.friend_invites where token = inv.token;
  execute 'set local role anon';
  execute 'set local request.jwt.claims = ''''';
  perform public.invite_preview(inv.token);
  perform public.invite_preview(inv.token);
  perform public.invite_preview(inv.token);
  perform public.invite_preview(inv.token);
  execute 'reset role';
  if (select used_count from public.friend_invites where token = inv.token) <> used then
    raise exception 'previewing an invite consumed a use';
  end if;

  -- 4. A garbage token answers rather than raising, and answers "not live". An error
  --    would tell a prober that their guess was malformed rather than merely wrong.
  execute 'set local role anon';
  execute 'set local request.jwt.claims = ''''';
  select * into pv from public.invite_preview('ZZZZZZZZ');
  execute 'reset role';
  if pv.is_live then
    raise exception 'an unknown token previewed as live';
  end if;
  if pv.inviter_username is not null then
    raise exception 'an unknown token returned a name';
  end if;

  -- 5. Revoked reads as not live. The page must not invite someone through a door the
  --    sender has already closed.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', claims);
  perform public.revoke_invite(inv.token);
  execute 'reset role';

  execute 'set local role anon';
  execute 'set local request.jwt.claims = ''''';
  select * into pv from public.invite_preview(inv.token);
  execute 'reset role';
  if pv.is_live then
    raise exception 'a revoked invite previewed as live';
  end if;
  -- Still named: the page says "지수 invited you, but this link has expired", which
  -- needs the name to say anything useful at all.
  if pv.inviter_username is distinct from aname then
    raise exception 'a revoked invite lost the inviter name';
  end if;

  -- 6. **The leak check.** The composite must carry display fields and nothing else.
  --    An `inviter_id` here would turn any token into a user-id oracle, which is
  --    exactly what the owner-scoped SELECT policy exists to prevent. Asserted against
  --    the type rather than the value, so adding a column fails this test.
  if exists (
    select 1
      from pg_catalog.pg_attribute a
      join pg_catalog.pg_class c on c.oid = a.attrelid
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'invite_preview_result'
       and a.attnum > 0
       and not a.attisdropped
       and a.attname not in (
         'inviter_username', 'inviter_emoji', 'inviter_avatar_path', 'is_live'
       )
  ) then
    raise exception 'invite_preview_result grew a field beyond the display set';
  end if;

  raise notice 'invite_preview: all six cases pass';
end $$;

rollback;
