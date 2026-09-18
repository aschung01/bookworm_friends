-- Verifies `create_invite()` and `redeem_invite()` against the real database.
--
--   supabase db query --linked -f supabase/tests/invites_test.sql
--
-- Silence is a pass. Rolled back.
--
-- The assertion that matters most is number 8: **dismissing the consent screen must not
-- consume a use.** It is the one case with no code path of its own -- the app simply
-- does not call `redeem_invite` -- so the only way to pin it is to show that
-- `used_count` moves on redemption and on nothing else.

begin;

do $$
declare
  alice        uuid;
  bob          uuid;
  carol        uuid;
  alice_claims text;
  bob_claims   text;
  carol_claims text;
  inv          public.friend_invites;
  res          public.invite_redemption;
  tok          text;
  n            int;
  used         int;
begin
  select id into alice from public.profiles order by created_at limit 1;
  select id into bob from public.profiles where id <> alice order by created_at limit 1;
  select id into carol from public.profiles where id not in (alice, bob)
    order by created_at limit 1;

  if alice is null or bob is null or carol is null then
    raise exception 'need at least three profiles to test against';
  end if;

  alice_claims := json_build_object('sub', alice, 'role', 'authenticated')::text;
  bob_claims   := json_build_object('sub', bob,   'role', 'authenticated')::text;
  carol_claims := json_build_object('sub', carol, 'role', 'authenticated')::text;

  delete from public.friendships
   where user_a in (alice, bob, carol) and user_b in (alice, bob, carol);

  -- 1. Alice creates an invite.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select * into inv from public.create_invite();
  execute 'reset role';

  tok := inv.token;
  if tok is null then
    raise exception 'create_invite returned no token';
  end if;

  -- 2. The token is 8 characters from the unambiguous alphabet. Asserted rather than
  --    assumed because the whole point of the alphabet is being readable aloud, and a
  --    stray O or 1 is only discovered by someone failing to type it.
  if length(tok) <> 8 then
    raise exception 'token is % characters, expected 8: %', length(tok), tok;
  end if;
  if tok !~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{8}$' then
    raise exception 'token contains an ambiguous character: %', tok;
  end if;
  if inv.used_count <> 0 or inv.max_uses <> 10 then
    raise exception 'new invite has used_count=% max_uses=%', inv.used_count, inv.max_uses;
  end if;
  if inv.expires_at <= now() then
    raise exception 'new invite is already expired';
  end if;

  -- 3. The inviter redeeming their own link is refused, and does not spend a use.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select * into res from public.redeem_invite(tok);
  execute 'reset role';

  if res.result <> 'self' then
    raise exception 'self-redemption returned %, expected self', res.result;
  end if;
  select used_count into used from public.friend_invites where token = tok;
  if used <> 0 then
    raise exception 'a refused self-redemption consumed a use (used_count=%)', used;
  end if;

  -- 4. Bob redeems: one friendship, one redemption row, one use.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', bob_claims);
  select * into res from public.redeem_invite(tok);
  execute 'reset role';

  if res.result <> 'ok' then
    raise exception 'redemption returned %, expected ok', res.result;
  end if;
  if res.inviter_id <> alice then
    raise exception 'redemption named the wrong inviter';
  end if;

  select count(*) into n from public.friendships
   where user_a = least(alice, bob) and user_b = greatest(alice, bob);
  if n <> 1 then
    raise exception 'redemption created % friendships, expected 1', n;
  end if;

  select count(*) into n from public.friend_invite_redemptions
   where token = tok and redeemer_id = bob;
  if n <> 1 then
    raise exception 'redemption wrote % rows, expected 1', n;
  end if;

  select used_count into used from public.friend_invites where token = tok;
  if used <> 1 then
    raise exception 'used_count is %, expected 1', used;
  end if;

  -- 5. Bob redeeming again is idempotent: no second friendship, no second use.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', bob_claims);
  select * into res from public.redeem_invite(tok);
  execute 'reset role';

  if res.result <> 'already_friends' then
    raise exception 'second redemption returned %, expected already_friends', res.result;
  end if;
  select used_count into used from public.friend_invites where token = tok;
  if used <> 1 then
    raise exception 'a repeat tap consumed a second use (used_count=%)', used;
  end if;

  -- 6. Expired, revoked and exhausted are distinguishable. Each gets its own token, so
  --    one state cannot mask another.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select * into inv from public.create_invite();
  execute 'reset role';
  update public.friend_invites set expires_at = now() - interval '1 minute'
   where token = inv.token;
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', carol_claims);
  select * into res from public.redeem_invite(inv.token);
  execute 'reset role';
  if res.result <> 'expired' then
    raise exception 'expired link returned %', res.result;
  end if;

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select * into inv from public.create_invite();
  execute 'reset role';
  update public.friend_invites set revoked_at = now() where token = inv.token;
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', carol_claims);
  select * into res from public.redeem_invite(inv.token);
  execute 'reset role';
  if res.result <> 'revoked' then
    raise exception 'revoked link returned %', res.result;
  end if;

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select * into inv from public.create_invite();
  execute 'reset role';
  update public.friend_invites set used_count = max_uses where token = inv.token;
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', carol_claims);
  select * into res from public.redeem_invite(inv.token);
  execute 'reset role';
  if res.result <> 'exhausted' then
    raise exception 'exhausted link returned %', res.result;
  end if;

  -- 7. An unknown token is `not_found`, not an error.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', carol_claims);
  select * into res from public.redeem_invite('ZZZZZZZZ');
  execute 'reset role';
  if res.result <> 'not_found' then
    raise exception 'unknown token returned %', res.result;
  end if;

  -- 8. **Dismissal costs nothing.** The consent screen's ✕ never calls redeem_invite,
  --    so a live token must be exactly as it was: same use count, no redemption row,
  --    and still redeemable afterwards by someone else.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select * into inv from public.create_invite();
  execute 'reset role';
  tok := inv.token;

  -- ...nothing happens here. That is the test.

  select used_count into used from public.friend_invites where token = tok;
  if used <> 0 then
    raise exception 'a dismissed invite consumed a use (used_count=%)', used;
  end if;
  select count(*) into n from public.friend_invite_redemptions where token = tok;
  if n <> 0 then
    raise exception 'a dismissed invite wrote a redemption row';
  end if;

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', carol_claims);
  select * into res from public.redeem_invite(tok);
  execute 'reset role';
  if res.result <> 'ok' then
    raise exception 'a dismissed invite was not still redeemable (%)', res.result;
  end if;

  -- 9. Revoking is owner-only. Carol cannot revoke Alice's link.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select * into inv from public.create_invite();
  execute 'reset role';

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', carol_claims);
  if public.revoke_invite(inv.token) then
    raise exception 'a non-owner revoked an invite';
  end if;
  execute 'reset role';

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  if not public.revoke_invite(inv.token) then
    raise exception 'the owner could not revoke their own invite';
  end if;
  execute 'reset role';

  -- 10. **Every call mints a new link.** The reference hands out a new id per share, and
  --     a version of `create_invite()` that reused the caller's newest live link shipped
  --     briefly before being reverted (`20260831130000_revert_invite_reuse.sql`). It was
  --     added to keep a revoke control coherent; the control is gone and so is the reuse.
  --     Pinned here because re-adding it is a one-line change that no other assertion
  --     would notice.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', alice_claims);
  select * into inv from public.create_invite();
  tok := inv.token;
  select * into inv from public.create_invite();
  execute 'reset role';
  if inv.token = tok then
    raise exception 'create_invite reused a link instead of minting one';
  end if;

  raise notice 'invites: all ten cases pass';
end $$;

rollback;
