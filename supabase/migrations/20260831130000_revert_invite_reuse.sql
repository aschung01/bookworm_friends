-- Reverts `create_invite()` to minting a fresh link on every call.
--
-- **This undoes `20260831120000_reuse_live_invite.sql`, which was a mistake.** Two
-- reasons, and the second is the one that matters.
--
-- 1. *Its justification is gone.* Reuse was argued for on the grounds that a sender with
--    several live links could revoke the visible one and leave another working. `Turn off
--    this link` has been removed -- the reference has no such control -- so nobody can
--    revoke anything from the UI, and the incoherence it was protecting against cannot
--    arise. What is left of the argument is that a sender "cannot reason about their
--    outstanding invites", which is not a thing the app ever asks them to do: there is no
--    list of links anywhere, only the one code on the sheet.
--
-- 2. *The reference mints a new link per share, which was checked rather than assumed.*
--    Flighty hands out a new id each time its invite sheet's button is pressed. That is
--    the behaviour this design follows, and this function was diverging from it on the
--    strength of an internal argument about tidiness.
--
-- What reuse actually cost: an advisory lock, a restatement of the three liveness
-- conditions `redeem_invite()` already owns, and a second place for those conditions to
-- drift out of step. All of it in service of a property nobody asked for.
--
-- A row per opened sheet is the honest cost, and it is a row. Each is capped at 48 hours
-- and 10 uses by the values written into it, so an abandoned invite expires on its own.

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

COMMENT ON FUNCTION public.create_invite() IS
  'Mints a fresh invite on every call, as the reference does. An earlier version reused '
  'the caller''s newest live link; that existed to keep a revoke control coherent, and '
  'the control is gone. See 20260831130000_revert_invite_reuse.sql.';
