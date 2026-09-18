-- `create_invite()` reuses a live link instead of minting a new one each time.
--
-- **The bug this fixes is a sender with several valid links and no idea which.** The
-- invite sheet calls this in `initState`, so opening it, closing it and opening it again
-- produced two rows, each good for 48 hours and 10 uses. The code read down a phone
-- yesterday was not the code on screen today, and revoking the one you could see left
-- the other one live. An earlier comment shrugged that the cost was "a row"; the cost is
-- actually that a sender cannot reason about their own outstanding invites.
--
-- **Reuse belongs here, not in the client.** Picking "my newest live invite" from Dart
-- means a select followed by a conditional insert, which is a race: two sheets opened in
-- the same second both see nothing and both insert. Inside one SECURITY DEFINER function
-- the read and the write are one statement away from each other and the advisory lock
-- below closes the rest.
--
-- Live means the same three things `redeem_invite()` checks, and they are deliberately
-- restated rather than factored out: a helper shared between the two would make it
-- possible to loosen redemption by editing something that reads like a formatter.

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

  -- Serialised per inviter, so two sheets opened at once cannot both find nothing and
  -- both insert. Transaction-scoped, so it is released on commit or rollback without a
  -- matching unlock -- and keyed on the inviter, so two different people never wait on
  -- each other. `hashtextextended` because `pg_advisory_xact_lock` wants a bigint and a
  -- uuid does not cast to one.
  PERFORM pg_advisory_xact_lock(
    pg_catalog.hashtextextended(inviter::text, 0)
  );

  -- The newest still-usable link. `used_count > 0` is not a disqualifier: a link shared
  -- into a group chat and used twice is exactly the link the sender wants to keep
  -- showing, which is the whole reason `max_uses` is 10 rather than 1.
  SELECT * INTO created
    FROM public.friend_invites
   WHERE inviter_id = inviter
     AND revoked_at IS NULL
     AND expires_at > now()
     AND used_count < max_uses
   ORDER BY created_at DESC
   LIMIT 1;

  IF FOUND THEN
    RETURN created;
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

COMMENT ON FUNCTION public.create_invite() IS
  'Returns the caller''s newest live invite, minting one only when there is none. '
  'Reuse is here rather than in the client because a select-then-insert from Dart '
  'races itself; the advisory lock makes concurrent sheet opens safe. A partly-used '
  'link still counts as live -- that is what max_uses > 1 is for.';
