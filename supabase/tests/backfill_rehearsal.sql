-- Rehearses the `follows` -> `friendships` backfill on a synthetic corpus with the same
-- shape as production, and asserts the counts.
--
-- Not a `*_test.sql`, so `run_local.sh` does not pick it up: by the time the migrations
-- have run, `follows` no longer exists. This is run **against a database stopped one
-- migration short**, which is the only point at which the question is answerable:
--
--   sh supabase/tests/rehearse_backfill.sh
--
-- What it pins is the classification, not the production numbers -- mutual pairs become
-- one canonical row, one-way edges become nothing, and the arithmetic closes. The real
-- counts (37 edges / 25 pairs / 12 mutual / 13 one-way) must be re-derived against the
-- live database immediately before migrating; see the design record.

begin;

do $$
declare
  a uuid := '11111111-1111-4111-8111-111111111111';
  b uuid := '22222222-2222-4222-8222-222222222222';
  c uuid := '33333333-3333-4333-8333-333333333333';
  n_edges    int;
  n_pairs    int;
  n_friends  int;
  n_oneway   int;
  n_ab       int;
begin
  -- A corpus in miniature: one mutual pair (a <-> b), and two one-way edges
  -- (a -> c, and c -> ... nothing back). Mirrors the production ratio closely enough
  -- to exercise every branch of the join.
  delete from public.follows
   where follower_id in (a, b, c) or following_id in (a, b, c);

  insert into public.follows (follower_id, following_id) values
    (a, b),   -- mutual, half one
    (b, a),   -- mutual, half two
    (a, c),   -- one-way, dropped
    (c, b);   -- one-way, dropped
  --  ^ note c -> b exists but b -> c does not, so this is one-way despite c also
  --    being followed by a. Reciprocity is per-pair, not per-user, and a naive
  --    "has any edge in both directions" query gets this wrong.

  select count(*) into n_edges from public.follows
   where follower_id in (a, b, c) and following_id in (a, b, c);

  select count(distinct least(follower_id, following_id) || '|' ||
                        greatest(follower_id, following_id))
    into n_pairs
    from public.follows
   where follower_id in (a, b, c) and following_id in (a, b, c);

  -- The statement under test, copied verbatim from the migration.
  insert into public.friendships (user_a, user_b)
  select distinct
    least(f.follower_id, f.following_id),
    greatest(f.follower_id, f.following_id)
  from public.follows f
  join public.follows r
    on r.follower_id = f.following_id
   and r.following_id = f.follower_id
  on conflict do nothing;

  select count(*) into n_friends from public.friendships
   where user_a in (a, b, c) and user_b in (a, b, c);

  n_oneway := n_pairs - n_friends;

  if n_edges <> 4 then
    raise exception 'fixture wrong: expected 4 edges, got %', n_edges;
  end if;
  if n_pairs <> 3 then
    raise exception 'expected 3 distinct pairs, got %', n_pairs;
  end if;
  if n_friends <> 1 then
    raise exception 'expected 1 mutual pair to become a friendship, got %', n_friends;
  end if;
  if n_oneway <> 2 then
    raise exception 'expected 2 one-way pairs dropped, got %', n_oneway;
  end if;
  -- The arithmetic that has to close on production too: mutual*2 + oneway = edges.
  if (n_friends * 2 + n_oneway) <> n_edges then
    raise exception 'arithmetic does not close: %*2 + % <> %', n_friends, n_oneway, n_edges;
  end if;

  -- Exactly one row for the mutual pair, in canonical order, regardless of which
  -- direction the join happened to see first.
  select count(*) into n_ab from public.friendships
   where user_a = least(a, b) and user_b = greatest(a, b);
  if n_ab <> 1 then
    raise exception 'the mutual pair produced % rows, expected exactly 1', n_ab;
  end if;

  raise notice 'backfill rehearsal: 4 edges -> 3 pairs -> 1 friendship, 2 dropped';
end $$;

rollback;
