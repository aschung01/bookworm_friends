-- `invite_preview()`: what the landing page is allowed to know.
--
-- The page at libstack.app/i/<token> has to name the inviter before the recipient
-- decides anything -- the drawings are explicit that an unnamed invite does not get
-- tapped, and "Someone invited you" is the fallback, not the design.
--
-- It cannot read the row itself. `friend_invites` SELECT is owner-scoped:
--
--   CREATE POLICY "Inviter can read own invites" ON public.friend_invites
--     FOR SELECT USING (inviter_id = auth.uid());
--
-- An anonymous visitor has no auth.uid(), so an anon-key select returns nothing. That
-- policy is correct and is not being relaxed: the whole point is that holding a token
-- must not let you enumerate who is inviting whom.
--
-- So this function is the one narrow window through it, and its shape is the guard.
--
-- **It returns display fields only.** No inviter_id, no token metadata beyond liveness,
-- nothing about the invite's use count or its other redeemers. Adding inviter_id here
-- would turn a token into a user-id oracle, which is the leak the owner-scoped policy
-- exists to prevent. Everything returned is something the recipient is about to see
-- anyway the moment they accept.
--
-- **It is read-only.** A preview is not a redemption: it must not consume a use, must
-- not record a redemption row, and must not extend or expire anything. Someone opening
-- the page five times has spent nothing.
--
-- Design record: docs/superpowers/specs/2026-08-30-invite-landing-design.md.

CREATE TYPE public.invite_preview_result AS (
  inviter_username text,
  inviter_emoji text,
  inviter_avatar_path text,
  is_live boolean
);

CREATE OR REPLACE FUNCTION public.invite_preview(invite_token text)
RETURNS public.invite_preview_result
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  inv public.friend_invites;
  prof public.profiles;
  out_row public.invite_preview_result;
BEGIN
  -- A garbage token returns a row of NULLs rather than raising. The page renders
  -- "Someone invited you" either way, and an error would tell a prober that their
  -- guess was malformed rather than merely wrong.
  SELECT * INTO inv FROM public.friend_invites WHERE token = invite_token;
  IF NOT FOUND THEN
    out_row.is_live := false;
    RETURN out_row;
  END IF;

  -- Liveness only, with no reason attached. `redeem_invite()` distinguishes expired,
  -- revoked and exhausted because the recovery differs and the reader has already
  -- committed by then; this is a page a stranger can hit with a guessed token, so it
  -- says no more than yes-or-no.
  out_row.is_live := inv.revoked_at IS NULL
                 AND inv.expires_at > now()
                 AND inv.used_count < inv.max_uses;

  SELECT * INTO prof FROM public.profiles WHERE id = inv.inviter_id;
  IF FOUND THEN
    out_row.inviter_username := prof.username;
    out_row.inviter_emoji := prof.emoji;
    out_row.inviter_avatar_path := prof.avatar_path;
  END IF;

  RETURN out_row;
END;
$$;

REVOKE ALL ON FUNCTION public.invite_preview(text) FROM PUBLIC;
-- `anon`, which is the only function in this schema granted to it. That is the entire
-- point -- the caller is a visitor who has not installed the app, let alone signed in.
-- `authenticated` too, so the same page works for a signed-in reader on the web.
GRANT EXECUTE ON FUNCTION public.invite_preview(text) TO anon, authenticated;

COMMENT ON FUNCTION public.invite_preview(text) IS
  'Display fields for the invite landing page, for callers who cannot read '
  'friend_invites. Returns the inviter''s name and avatar plus a liveness boolean -- '
  'never inviter_id, which would make a token into a user-id oracle. Read-only: a '
  'preview never consumes a use.';
