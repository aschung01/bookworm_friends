-- `cover_read_events`: meter the one feature in the app that costs money per use.
--
-- Every other thing a user can tap is either free or bounded by their own patience.
-- Reading a book cover with an LLM is neither: it is a paid API call, it is triggered by
-- a single button, and the button lives on a screen the user is *already pointing at
-- things with*. A stuck finger, a retry loop or a modified client all bill the project
-- rather than the person, and the barcode path -- which is free, offline and handles the
-- ordinary case -- would go on working perfectly while the bill grew. So the read is
-- metered before it is offered.
--
-- The limits are deliberately generous. Someone cataloguing a shelf of thirty
-- unbarcoded books in one sitting is a real user doing the intended thing, and a limit
-- that stops them is worse than the cost it saves. These numbers are set to stop a
-- *loop*, not to ration normal use.
--
-- Recording the outcome as well as the fact is the other half of the point. Nobody knows
-- yet how often an LLM can actually read a Korean cover in a phone snapshot, and that
-- number decides whether this path deserves to exist at all. Without it the only
-- evidence would be the invoice.

CREATE TABLE public.cover_read_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  -- What came back. 'ok' resolved to a title, 'unreadable' means the model answered but
  -- could not name a book, 'error' means the call itself failed. All three are recorded
  -- because **all three cost money** -- a failed read is billed the same as a good one,
  -- so excluding failures from the meter would leave the cheapest way to burn the budget
  -- unmetered.
  outcome text NOT NULL CHECK (outcome IN ('ok', 'unreadable', 'error'))
);

-- The only query the limiter runs: this user's reads since a cutoff. `user_id` first
-- because it is the equality predicate and `created_at` is the range one -- the reverse
-- order would not let the index serve the window scan.
CREATE INDEX cover_read_events_user_created_idx
  ON public.cover_read_events (user_id, created_at DESC);

ALTER TABLE public.cover_read_events ENABLE ROW LEVEL SECURITY;

-- Readable by its owner. Nothing consumes this today; it is here so a future "you have
-- used 12 of 30 reads this hour" can be answered from the client without a new policy,
-- and because a user being able to see what was spent on their behalf is the right
-- default for a metered feature.
CREATE POLICY "Users can read their own cover reads" ON public.cover_read_events
  FOR SELECT USING (user_id = auth.uid());

-- **Deliberately no INSERT, UPDATE or DELETE policy.** With RLS on and no policy for a
-- command, no client can perform it. That is what makes the meter trustworthy: a client
-- that could insert could also *not* insert, and a client that could delete could reset
-- its own limit. The only writer is the `read-book-cover` Edge Function, which holds the
-- service role key and bypasses RLS -- the same arrangement `poke_events` uses to keep
-- pokes unforgeable.
