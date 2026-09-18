-- `poke_events`: start recording pokes now, so the feed has a history to show later.
--
-- This table has **no reader today**, and that is the point. `poke_user()` sends a
-- push notification and stores nothing, so a poke exists only as an alert on someone's
-- lock screen and is gone the moment it is dismissed. The Activity feed will want
-- "minho poked you" alongside the other events -- and every poke that happens before
-- this table exists is lost permanently. Recording is cheap; the history is not
-- recoverable. So this ships ahead of the thing that consumes it, deliberately.
--
-- Phase 4's audit is why it ships *now* rather than with the feed: the feed itself is
-- deferred until after release, because there is no activity to show yet (zero
-- start/finish events in the last 90 days, the newest praise 939 days old). Waiting for
-- the feed would mean launching without recording, which is the one ordering that
-- throws data away.
--
-- Shaped after `follows`, which is the other table describing a directed act between two
-- people: two profile references, a timestamp, and a CHECK that the two differ.

CREATE TABLE public.poke_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  to_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Poking yourself is not a thing. `poke_user()` guards this too, so the constraint is
  -- a backstop rather than the enforcement -- see the note in the function below about
  -- why it guards instead of relying on this.
  CHECK (from_user_id != to_user_id)
);

-- No uniqueness constraint, unlike `book_compliments`. Praise is a state ("I like this
-- book") and so is one-per-person-per-book; a poke is an event ("hello"), and poking
-- twice is two pokes rather than a duplicate. That does leave the table open to spam,
-- which is a rate-limiting problem and not a schema one.

-- The only query anyone will write against this: what arrived for me, newest first.
-- Added up front, unlike `books.authors`, because that column serves a client-side
-- aggregate over rows already in memory while this is a genuine recency lookup on a
-- table that grows without bound.
CREATE INDEX poke_events_to_user_created_idx
  ON public.poke_events (to_user_id, created_at DESC);

ALTER TABLE public.poke_events ENABLE ROW LEVEL SECURITY;

-- Both parties can read a poke: the sender because they sent it, the recipient because
-- the feed is going to say "X poked you".
CREATE POLICY "Participants can read pokes" ON public.poke_events
  FOR SELECT USING (
    to_user_id = auth.uid() OR from_user_id = auth.uid()
  );

-- **Deliberately no INSERT, UPDATE or DELETE policy.** With RLS on and no policy for a
-- command, no client can perform it -- so a poke cannot be forged, back-dated or
-- deleted from the app or through the API. The only writer is `poke_user()`, which is
-- SECURITY DEFINER and owned by the migration role, so it bypasses RLS. That is the
-- same mechanism the function already relies on to read `profiles.fcm_token`.

-- Record the poke, then notify.
--
-- Three things worth knowing about the version this replaces, all of them preserved
-- rather than fixed here, because this migration is about recording and not about poke
-- policy:
--
--   * It looks the target up by **username**, and silently does nothing when no such
--     user exists -- `target_token` is null, the IF is skipped, and the caller still
--     gets a success toast. Unchanged.
--   * It never checks that the poker follows the target, so anyone can poke anyone by
--     username. That is a real policy gap and it is listed in the design record's
--     "Still open" beside the praise ones. Unchanged here on purpose: tightening it is
--     a behaviour change that deserves its own migration.
--   * A target with no `fcm_token` gets no notification.
--
-- The insert sits **outside** the token check, and that is a decision rather than an
-- oversight: a poke with no deliverable notification still happened. The sender pressed
-- the button and was told it worked, so the feed should be able to say so. Recording
-- only the deliverable ones would make the history depend on whether the recipient had
-- push enabled at the time.
CREATE OR REPLACE FUNCTION public.poke_user(target_username text)
RETURNS void AS $$
DECLARE
  target_id uuid;
  target_token text;
  poker_username text;
  poker_id uuid;
BEGIN
  poker_id := auth.uid();

  SELECT id, fcm_token INTO target_id, target_token
  FROM public.profiles
  WHERE username = target_username;

  SELECT username INTO poker_username
  FROM public.profiles
  WHERE id = poker_id;

  -- Guarded rather than left to the CHECK constraint. A failed CHECK raises, which
  -- would abort the whole function and turn today's silent no-ops -- an unknown
  -- username, an unauthenticated caller, poking yourself -- into an error the app
  -- reports as "poke failed". Recording history must not change what the button does.
  IF poker_id IS NOT NULL AND target_id IS NOT NULL AND target_id != poker_id THEN
    INSERT INTO public.poke_events (from_user_id, to_user_id)
    VALUES (poker_id, target_id);
  END IF;

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
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
