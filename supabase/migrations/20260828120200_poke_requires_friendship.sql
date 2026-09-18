-- `poke_user()`: require friendship, pin `search_path`, and put the push behind the
-- same guard as the audit row.
--
-- Three changes, one of them a behaviour change and two of them fixes to problems the
-- function has had since it was written.
--
-- The behaviour change was flagged at the time. `20260818020000_poke_events.sql:66-69`
-- records it as a known gap -- "it never checks that the poker follows the target, so
-- anyone can poke anyone by username" -- and says tightening it "deserves its own
-- migration". This is that migration. Under friends-only the rule is simply friendship:
-- poke is a person-level act, and there is no relationship short of friendship left in
-- the model.
--
-- ---------------------------------------------------------------------------
-- The guard split, which is a real bug and not a tidiness
-- ---------------------------------------------------------------------------
--
-- The version this replaces has two separate IF blocks. The `poke_events` insert is
-- guarded on `poker_id IS NOT NULL`; the `net.http_post` is guarded only on
-- `target_token IS NOT NULL`. So an anonymous caller -- `auth.uid()` null -- could not
-- write the audit row but **could still fire the push**. And with `poker_id` null,
-- `poker_username` is null too, so `poker_username || '님이 콕 찔렀어요!'` evaluates to
-- NULL and the notification ships with a null title.
--
-- Both effects now sit under one guard. The audit row and the push describe the same
-- event; there is no state in which one should happen and the other should not.
--
-- ---------------------------------------------------------------------------
-- What this does NOT fix
-- ---------------------------------------------------------------------------
--
-- **`supabase/functions/send-notification/index.ts` authenticates nothing.** It takes
-- `target_user_id`, `title` and `body` straight from the request body and forwards them
-- to FCM. Anyone who can reach the URL can send any user any notification, without
-- going through this function at all. The friendship check here is defence in depth and
-- nothing more, and it would be a mistake to read this migration as closing that hole.
-- It needs its own change, and it is tracked in the design record.

CREATE OR REPLACE FUNCTION public.poke_user(target_username text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
-- Pinned empty, with everything below fully qualified. The original left it unset,
-- which for a SECURITY DEFINER function means it resolved through whatever schema the
-- caller had in front of it -- exactly the trap
-- `supabase/migrations/20260821100303_add_profile_handle.sql:57` documents.
SET search_path = ''
AS $$
DECLARE
  target_id uuid;
  target_token text;
  poker_username text;
  poker_id uuid;
  is_friend boolean;
BEGIN
  poker_id := auth.uid();

  SELECT id, fcm_token INTO target_id, target_token
  FROM public.profiles
  WHERE username = target_username;

  SELECT username INTO poker_username
  FROM public.profiles
  WHERE id = poker_id;

  -- Friendship, read directly rather than through `is_profile_visible()`. The two
  -- happen to agree today, but they answer different questions -- one is "may I see
  -- your library", the other is "may I tap you on the shoulder" -- and a poke should
  -- not start working again if visibility is ever widened for some other reason.
  is_friend := poker_id IS NOT NULL AND target_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.friendships fr
    WHERE fr.user_a = least(poker_id, target_id)
      AND fr.user_b = greatest(poker_id, target_id)
  );

  -- One guard for both effects.
  --
  -- Still a silent no-op rather than a raise, which is the contract the previous
  -- version established and gave its reasons for: an unknown username, an
  -- unauthenticated caller and poking yourself all return quietly today, and the app
  -- reports success. A non-friend poke joins that set. Raising would turn a stale
  -- friends list -- someone removed you while your screen was open -- into an error
  -- dialog, which is a worse answer to a race that resolves itself on the next refresh.
  --
  -- `is_friend` already implies both ids are non-null and, because the friendships
  -- check requires `user_a < user_b`, that they differ. The self-poke case is therefore
  -- covered without a separate clause.
  IF is_friend THEN
    INSERT INTO public.poke_events (from_user_id, to_user_id)
    VALUES (poker_id, target_id);

    -- Still inside the guard but still conditional on a token: a poke with no
    -- deliverable notification has happened and is recorded, which is the decision
    -- `20260818020000_poke_events.sql:72-76` sets out.
    IF target_token IS NOT NULL THEN
      PERFORM net.http_post(
        url := current_setting('app.settings.edge_function_url') || '/send-notification',
        body := jsonb_build_object(
          'type', 'poke',
          'target_user_id', target_id,
          'title', poker_username || '님이 콕 찔렀어요!',
          'body', '읽고 있는 책이 궁금해요'
        )
      );
    END IF;
  END IF;
END;
$$;

COMMENT ON FUNCTION public.poke_user(text) IS
  'Fires a poke between friends. Silent no-op for a non-friend, an unknown username, an '
  'unauthenticated caller, or yourself -- the app reports success in every case, which is '
  'the pre-existing contract. NOT a security boundary: send-notification is an open relay, '
  'so this is defence in depth only.';
