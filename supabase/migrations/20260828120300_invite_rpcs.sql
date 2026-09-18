-- `create_invite()` and `redeem_invite()`: the only way into a friendship.
--
-- Both are SECURITY DEFINER, which is what lets them write `friendships` and
-- `friend_invites` -- neither table has an INSERT policy, deliberately, so a client
-- cannot friend someone without an invite or forge a token with a distant expiry.
--
-- Design record: `docs/superpowers/specs/2026-08-28-friends-invites-design.md`.

-- ---------------------------------------------------------------------------
-- create_invite
-- ---------------------------------------------------------------------------

-- The alphabet is 32 characters: A-Z and 2-9, less `O`, `I`, `0` and `1`.
--
-- Not base62, and not a uuid, because the bottom tier of the deep-link ladder is a
-- human being reading the code down a phone. `O`/`0` and `I`/`1` are the pairs that
-- cost you a redemption when they are misheard or mistyped, and dropping them costs
-- almost nothing: 32^8 is 1.1 trillion combinations against a table that will hold
-- thousands. Uppercase-only for the same reason -- "lowercase L" is not a thing anyone
-- should have to say out loud.
--
-- Formatted as one run of 8 rather than two groups of 4: the drawings show it inline in
-- a sentence ("Or read them the code: K7M2QP4X"), and a separator would have to be
-- typed or explained.
CREATE OR REPLACE FUNCTION public.generate_invite_token()
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  candidate text;
  i int;
BEGIN
  -- Twenty tries against 1.1e12 combinations. A collision is already vanishingly
  -- unlikely; twenty in a row is not a case worth designing for, so the loop simply
  -- ends and the caller gets an error rather than a silently-reused token. Compare
  -- `generate_handle()`, which falls back to an ugly-but-unique value -- it cannot fail
  -- because a signup depends on it, whereas an invite can be retried by tapping again.
  FOR _attempt IN 1..20 LOOP
    candidate := '';
    FOR i IN 1..8 LOOP
      candidate := candidate ||
        substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    END LOOP;

    IF NOT EXISTS (
      SELECT 1 FROM public.friend_invites WHERE token = candidate
    ) THEN
      RETURN candidate;
    END IF;
  END LOOP;

  RAISE EXCEPTION 'could not generate a unique invite token after 20 attempts';
END;
$$;

REVOKE ALL ON FUNCTION public.generate_invite_token() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_invite_token() FROM anon, authenticated;

-- Returns the whole row rather than just the token: the invite sheet shows the code and
-- the expiry, and a second round trip to read back what you just created is a round
-- trip for nothing.
CREATE OR REPLACE FUNCTION public.create_invite()
RETURNS public.friend_invites
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  inviter uuid;
  created public.friend_invites;
BEGIN
  inviter := auth.uid();
  IF inviter IS NULL THEN
    RAISE EXCEPTION 'must be signed in to create an invite'
      USING errcode = '42501';
  END IF;

  -- 48 hours and 10 uses are Flighty's numbers, stated on their invite sheet. Written
  -- into the row rather than read from it at redemption time, so changing the policy
  -- later does not retroactively expire or extend links already in circulation.
  INSERT INTO public.friend_invites (token, inviter_id, expires_at)
  VALUES (
    public.generate_invite_token(),
    inviter,
    now() + interval '48 hours'
  )
  RETURNING * INTO created;

  RETURN created;
END;
$$;

REVOKE ALL ON FUNCTION public.create_invite() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_invite() TO authenticated;

-- ---------------------------------------------------------------------------
-- redeem_invite
-- ---------------------------------------------------------------------------

-- Returns a reason, not a boolean.
--
-- The drawings distinguish **expired**, **revoked** and **exhausted** because the
-- recovery differs: two of them mean "ask for a new link" and one means "you already
-- used this". A boolean cannot carry that, and a screen that says "this link didn't
-- work" for all three is a screen that makes the reader guess.
--
-- `already_friends` is separate from `ok` for the same reason: it is not a failure, but
-- the success screen would be a lie -- there is no new friendship to celebrate.
CREATE TYPE public.invite_redemption_result AS ENUM (
  'ok',
  'not_found',
  'expired',
  'revoked',
  'exhausted',
  'self',
  'already_friends',
  'not_signed_in'
);

-- Composite return: the outcome, plus who the inviter is when there is one. The consent
-- screen has to name them ("지수 wants to share books with you") before the reader
-- decides, so a redemption that returned only a verdict would force a second lookup
-- against a table the redeemer cannot read.
CREATE TYPE public.invite_redemption AS (
  result public.invite_redemption_result,
  inviter_id uuid
);

CREATE OR REPLACE FUNCTION public.redeem_invite(invite_token text)
RETURNS public.invite_redemption
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  redeemer uuid;
  inv public.friend_invites;
  out_row public.invite_redemption;
  lo uuid;
  hi uuid;
  inserted int;
BEGIN
  redeemer := auth.uid();
  out_row.inviter_id := NULL;

  IF redeemer IS NULL THEN
    out_row.result := 'not_signed_in';
    RETURN out_row;
  END IF;

  -- Locked, because `used_count` is read and then written. Two people tapping the same
  -- link at the same moment must not both see use 9 of 10.
  SELECT * INTO inv FROM public.friend_invites
   WHERE token = invite_token
   FOR UPDATE;

  IF NOT FOUND THEN
    out_row.result := 'not_found';
    RETURN out_row;
  END IF;

  out_row.inviter_id := inv.inviter_id;

  -- Order matters here. Revoked is checked before expired because a revoked link that
  -- has also aged out should say revoked: it is the more specific fact, and the one the
  -- inviter acted on deliberately.
  IF inv.revoked_at IS NOT NULL THEN
    out_row.result := 'revoked';
    RETURN out_row;
  END IF;

  IF inv.expires_at <= now() THEN
    out_row.result := 'expired';
    RETURN out_row;
  END IF;

  IF inv.inviter_id = redeemer THEN
    -- The most likely accident: the sender taps their own link to check it works.
    out_row.result := 'self';
    RETURN out_row;
  END IF;

  lo := least(inv.inviter_id, redeemer);
  hi := greatest(inv.inviter_id, redeemer);

  IF EXISTS (
    SELECT 1 FROM public.friendships WHERE user_a = lo AND user_b = hi
  ) THEN
    -- Checked before the use cap, so re-tapping a link you have already used does not
    -- report "exhausted" -- which would be true and useless.
    out_row.result := 'already_friends';
    RETURN out_row;
  END IF;

  IF inv.used_count >= inv.max_uses THEN
    out_row.result := 'exhausted';
    RETURN out_row;
  END IF;

  INSERT INTO public.friendships (user_a, user_b) VALUES (lo, hi)
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS inserted = ROW_COUNT;

  INSERT INTO public.friend_invite_redemptions (token, redeemer_id)
  VALUES (invite_token, redeemer)
  ON CONFLICT DO NOTHING;

  -- Incremented only when a friendship was actually created. The `already_friends`
  -- branch above returns before this, so a repeat tap cannot consume a use -- and
  -- neither can dismissing the consent screen, which never calls this function at all.
  IF inserted > 0 THEN
    UPDATE public.friend_invites
       SET used_count = used_count + 1
     WHERE token = invite_token;
  END IF;

  out_row.result := 'ok';
  RETURN out_row;
END;
$$;

REVOKE ALL ON FUNCTION public.redeem_invite(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.redeem_invite(text) TO authenticated;

COMMENT ON FUNCTION public.redeem_invite(text) IS
  'The only writer of public.friendships. Returns a reason rather than a boolean because '
  'expired, revoked and exhausted have different recoveries. Consumes a use only when a '
  'friendship is actually created, so a repeat tap -- or a dismissed consent screen -- '
  'never spends the sender''s link.';

-- ---------------------------------------------------------------------------
-- revoke_invite
-- ---------------------------------------------------------------------------

-- A plain UPDATE would do, and the RLS policy on `friend_invites` permits it. This
-- exists so the client has one verb per intention rather than reaching into a column,
-- and so "revoked" is always a timestamp set by the database clock.
CREATE OR REPLACE FUNCTION public.revoke_invite(invite_token text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  affected int;
BEGIN
  UPDATE public.friend_invites
     SET revoked_at = now()
   WHERE token = invite_token
     AND inviter_id = auth.uid()
     AND revoked_at IS NULL;

  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_invite(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.revoke_invite(text) TO authenticated;
