-- `friendships`, `friend_invites`, `friend_invite_redemptions`: mutual friendship,
-- entered only through an invite link.
--
-- Tables only. **Nothing here touches the visibility rule**, so this migration is
-- independently safe: `follows` still exists, still grants access, and every policy
-- that reads `is_profile_visible()` behaves exactly as it did. The switch-over is
-- `20260828120100_friends_only_visibility.sql`, which has to be one transaction for
-- reasons that migration explains at length.
--
-- Design record: `docs/superpowers/specs/2026-08-28-friends-invites-design.md`.
-- Drawings: `docs/mockups/friend-requests/index.html`.

-- ---------------------------------------------------------------------------
-- friendships
-- ---------------------------------------------------------------------------

-- One row per pair, and the CHECK is the design rather than a tidiness.
--
-- `follows` can hold (a -> b) without (b -> a), so "are these two friends?" is a
-- question with three answers -- yes, no, and half -- and every reader has to handle
-- the third. The production corpus has 13 such half-edges out of 25 pairs, which is
-- not an edge case. Ordering the pair and making the order a constraint means a
-- half-friendship **cannot be written at all**: there is no row shape that expresses
-- it. Nothing downstream has to detect one, repair one, or decide what it means.
--
-- It also makes removal a single DELETE that severs both directions at once, which is
-- what lets `manage-friend` state "access will be revoked for both of you" as a fact
-- rather than as an intention.
--
-- Every writer must normalise with least()/greatest() before touching this table. A
-- raw (me, them) insert has a 50% chance of raising, which is a loud failure and
-- therefore an acceptable one.
CREATE TABLE public.friendships (
  user_a uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  user_b uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_a, user_b),
  CHECK (user_a < user_b)
);

COMMENT ON TABLE public.friendships IS
  'Mutual friendship, one canonical row per pair. The (user_a < user_b) check makes a '
  'half-friendship unrepresentable, which is why there is no status column: a row is a '
  'friendship, its absence is not one, and there is no third state to store. Adding '
  'status later is one ALTER TABLE with DEFAULT ''accepted'', so this is not a one-way door.';

-- The primary key already indexes (user_a) and (user_a, user_b). A friend list has to
-- match **either** column -- `user_a = me OR user_b = me` -- and the left-most-column
-- rule means the PK does nothing for the second half of that. Without this the friends
-- list is a sequential scan on every open of the tab.
CREATE INDEX friendships_user_b_idx ON public.friendships (user_b);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

-- Participants only.
--
-- Compare `follows`, whose SELECT policy is `USING (true)`
-- (`supabase/migrations/20260505053006_rls_policies.sql:36-37`): the entire social
-- graph is readable today by anyone, including an unauthenticated caller. That is not
-- reproduced here. Who someone's friends are is as private as what they read.
CREATE POLICY "Participants can read friendships" ON public.friendships
  FOR SELECT USING (
    user_a = auth.uid() OR user_b = auth.uid()
  );

-- Either participant can end it, from their side, without the other's involvement.
CREATE POLICY "Participants can delete friendships" ON public.friendships
  FOR DELETE USING (
    user_a = auth.uid() OR user_b = auth.uid()
  );

-- **Deliberately no INSERT policy.** The only writer is `redeem_invite()`, which is
-- SECURITY DEFINER and therefore bypasses RLS -- the same mechanism `poke_user()` uses
-- to write `poke_events`. A client that could INSERT directly could friend anyone
-- without an invite, which would reintroduce by the back door exactly the unilateral
-- grant this whole design removes.
--
-- **And deliberately no UPDATE policy.** There is nothing to update: the table is
-- insert-and-delete. Adding one would be the first step back toward a request queue.

-- ---------------------------------------------------------------------------
-- friend_invites
-- ---------------------------------------------------------------------------

-- 48 hours and 10 uses are Flighty's numbers, stated on their invite sheet, and they
-- are stored per-row rather than hardcoded in the RPC so a future change does not
-- retroactively expire or extend links already in the wild.
--
-- `token` is the primary key and is the whole address of an invite: it appears in the
-- URL, and it is what a sender reads aloud when every link tier has failed. 8
-- characters from an alphabet without O/0/I/1 -- see `create_invite()` in
-- `20260828120300_invite_rpcs.sql` for why that alphabet and not base62.
CREATE TABLE public.friend_invites (
  token text PRIMARY KEY,
  inviter_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  -- A cap rather than single-use, because the drawn flow is someone pasting one link
  -- into a group chat. Single-use would make the second reader's tap a failure.
  max_uses integer NOT NULL DEFAULT 10 CHECK (max_uses > 0),
  used_count integer NOT NULL DEFAULT 0 CHECK (used_count >= 0),
  -- Set rather than deleted, so a revoked token stays claimed and cannot be reissued
  -- to someone else by a later `create_invite()` collision. It is also what lets the
  -- dead-link screen say *revoked* rather than *expired*, which are different
  -- recoveries: one means ask again, the other means you already used this.
  revoked_at timestamptz
);

COMMENT ON COLUMN public.friend_invites.used_count IS
  'Incremented by redeem_invite() only, and only on a redemption that actually created a '
  'friendship. Dismissing the consent screen does not consume a use -- the sender''s link '
  'must not be silently spent by someone who changed their mind.';

CREATE INDEX friend_invites_inviter_idx
  ON public.friend_invites (inviter_id, created_at DESC);

ALTER TABLE public.friend_invites ENABLE ROW LEVEL SECURITY;

-- The inviter can see their own invites. **The redeemer never reads this table**: they
-- reach it through `redeem_invite()`, which is SECURITY DEFINER, so nothing here has
-- to expose a token -- or the identity of its owner -- to the person holding it.
--
-- That matters more than it looks. A SELECT policy permitting "anyone who knows the
-- token" would turn this table into an oracle: a stranger could probe tokens and learn
-- who is inviting, when, and how often.
CREATE POLICY "Inviter can read own invites" ON public.friend_invites
  FOR SELECT USING (inviter_id = auth.uid());

-- Revoking is the one field a client may change, and only on its own row. Written as
-- two policies rather than one so the WITH CHECK cannot be forgotten: USING says which
-- rows you may attempt, WITH CHECK says what they may become.
CREATE POLICY "Inviter can revoke own invites" ON public.friend_invites
  FOR UPDATE USING (inviter_id = auth.uid())
  WITH CHECK (inviter_id = auth.uid());

-- No INSERT policy: `create_invite()` is the only writer, so a client cannot forge a
-- token with a distant expiry or an unlimited use count.

-- ---------------------------------------------------------------------------
-- friend_invite_redemptions
-- ---------------------------------------------------------------------------

-- Who redeemed what. The composite primary key is doing real work: it makes a second
-- redemption by the same person a no-op rather than a double-count, which is what
-- keeps `used_count` honest when someone taps the same link twice -- or taps it, backs
-- out of the consent screen, and taps it again.
CREATE TABLE public.friend_invite_redemptions (
  token text NOT NULL REFERENCES public.friend_invites(token) ON DELETE CASCADE,
  redeemer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (token, redeemer_id)
);

ALTER TABLE public.friend_invite_redemptions ENABLE ROW LEVEL SECURITY;

-- Both sides of the transaction can see it: the redeemer because it is their act, the
-- inviter because it is their link. The inviter's half is a join back through
-- `friend_invites`, which is itself owner-scoped.
CREATE POLICY "Participants can read redemptions" ON public.friend_invite_redemptions
  FOR SELECT USING (
    redeemer_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.friend_invites i
      WHERE i.token = friend_invite_redemptions.token
        AND i.inviter_id = auth.uid()
    )
  );

-- No INSERT, UPDATE or DELETE policy. `redeem_invite()` is the only writer, and a
-- redemption is a historical fact -- there is nothing to amend and nothing to retract.
