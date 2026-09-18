-- Verifies all six call sites of `is_profile_visible()` against the real database.
--
-- Five of the six inherit the rule by calling the function, and **inheritance is
-- exactly what this file exists to prove**. `20260828120100_friends_only_visibility.sql`
-- rewrites one function and replaces one policy; the claim that this reaches shelves,
-- books, memos, compliments and avatars is a claim about indirection, and indirection
-- is the kind of thing that is obviously true right up until a policy turns out to have
-- inlined the predicate. One of them already had.
--
--   supabase db query --linked -f supabase/tests/visibility_test.sql
--
-- Silence is a pass. Runs in a transaction that is rolled back.
--
-- Each probe runs three times -- stranger, friend, anonymous -- because the bug this
-- design fixes was specifically an *anonymous* read. The old predicate led with
-- `is_private = false`, evaluated before any relationship check, so a caller with no
-- `auth.uid()` matched it and could read every non-private library in the database.
-- A test that only checks "stranger" would have passed against that.

begin;

do $$
declare
  owner_id     uuid;
  friend_id    uuid;
  stranger_id  uuid;
  lo           uuid;
  hi           uuid;
  shelf_id     uuid;
  probe_book   uuid;
  memo_id      uuid;
  object_path  text;
  friend_claims   text;
  stranger_claims text;
  n int;
begin
  select id into owner_id from public.profiles order by created_at limit 1;
  select id into friend_id from public.profiles where id <> owner_id
    order by created_at limit 1;
  select id into stranger_id from public.profiles where id not in (owner_id, friend_id)
    order by created_at limit 1;

  if owner_id is null or friend_id is null or stranger_id is null then
    raise exception 'need at least three profiles to test against';
  end if;

  friend_claims   := json_build_object('sub', friend_id, 'role', 'authenticated')::text;
  stranger_claims := json_build_object('sub', stranger_id, 'role', 'authenticated')::text;

  -- A library belonging to `owner_id`, one row in each protected table.
  insert into public.shelves (user_id, name, position)
    values (owner_id, 'rls probe shelf', 0)
    returning id into shelf_id;

  insert into public.books (user_id, shelf_id, isbn, title, thumbnail, status, position)
    values (owner_id, shelf_id, '9780000000001', 'RLS Probe', '', 0, 0)
    returning id into probe_book;

  insert into public.book_memos (user_id, book_id, content)
    values (owner_id, probe_book, 'probe memo')
    returning id into memo_id;

  -- Praise written BY the stranger ON the owner's book, so the compliments probe is
  -- about book visibility rather than about authorship: the policy also lets you see
  -- praise you sent, and that clause must not be what makes this pass.
  insert into public.book_compliments (book_id, from_user_id, compliment)
    values (probe_book, stranger_id, '🔥');

  object_path := owner_id::text || '/rls-probe.jpg';
  update public.profiles set avatar_path = object_path where id = owner_id;
  insert into storage.objects (bucket_id, name) values ('avatars', object_path)
    on conflict do nothing;

  -- No friendship yet.
  delete from public.friendships
   where (user_a = least(owner_id, friend_id) and user_b = greatest(owner_id, friend_id));

  -- ---------------------------------------------------------------------
  -- A. A stranger sees nothing, at any of the six sites
  -- ---------------------------------------------------------------------
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', stranger_claims);

  select count(*) into n from public.profiles where id = owner_id;
  if n <> 0 then raise exception 'stranger read a profile (%)', n; end if;

  select count(*) into n from public.shelves where id = shelf_id;
  if n <> 0 then raise exception 'stranger read a shelf (%)', n; end if;

  select count(*) into n from public.books where id = probe_book;
  if n <> 0 then raise exception 'stranger read a book (%)', n; end if;

  select count(*) into n from public.book_memos where id = memo_id;
  if n <> 0 then raise exception 'stranger read a memo (%)', n; end if;

  select count(*) into n from storage.objects
   where bucket_id = 'avatars' and name = object_path;
  if n <> 0 then raise exception 'stranger read an avatar (%)', n; end if;

  execute 'reset role';

  -- ---------------------------------------------------------------------
  -- B. An anonymous caller sees nothing either
  --
  -- The regression that matters most. `auth.uid()` is NULL here, and the old
  -- predicate's leading `is_private = false` made that sufficient.
  -- ---------------------------------------------------------------------
  execute 'set local role anon';
  execute 'set local request.jwt.claims = ''''';

  select count(*) into n from public.profiles where id = owner_id;
  if n <> 0 then raise exception 'ANONYMOUS read a profile (%) -- the hole is open', n; end if;

  select count(*) into n from public.shelves where id = shelf_id;
  if n <> 0 then raise exception 'ANONYMOUS read a shelf (%) -- the hole is open', n; end if;

  select count(*) into n from public.books where id = probe_book;
  if n <> 0 then raise exception 'ANONYMOUS read a book (%) -- the hole is open', n; end if;

  execute 'reset role';

  -- ---------------------------------------------------------------------
  -- C. A friend sees all six
  -- ---------------------------------------------------------------------
  lo := least(owner_id, friend_id);
  hi := greatest(owner_id, friend_id);
  insert into public.friendships (user_a, user_b) values (lo, hi)
    on conflict do nothing;

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', friend_claims);

  select count(*) into n from public.profiles where id = owner_id;
  if n <> 1 then raise exception 'friend could not read the profile (%)', n; end if;

  select count(*) into n from public.shelves where id = shelf_id;
  if n <> 1 then raise exception 'friend could not read the shelf (%)', n; end if;

  select count(*) into n from public.books where id = probe_book;
  if n <> 1 then raise exception 'friend could not read the book (%)', n; end if;

  select count(*) into n from public.book_memos where id = memo_id;
  if n <> 1 then raise exception 'friend could not read the memo (%)', n; end if;

  -- Site 5, reached through `is_book_visible()` rather than directly. This is the
  -- indirection the migration never touches and therefore most needs proving.
  --
  -- The probe variable is deliberately NOT named `book_id`: a local with a column's
  -- name makes `where book_id = book_id` a tautology that passes against anything,
  -- and plpgsql raises rather than silently accepting it. Aliased and qualified.
  select count(*) into n from public.book_compliments bc where bc.book_id = probe_book;
  if n < 1 then raise exception 'friend could not read praise on a visible book (%)', n; end if;

  -- Site 6, in another schema entirely.
  select count(*) into n from storage.objects
   where bucket_id = 'avatars' and name = object_path;
  if n <> 1 then raise exception 'friend could not read the avatar (%)', n; end if;

  execute 'reset role';

  -- ---------------------------------------------------------------------
  -- D. Removing the friendship revokes all six, in both directions
  -- ---------------------------------------------------------------------
  delete from public.friendships where user_a = lo and user_b = hi;

  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', friend_claims);

  select count(*) into n from public.profiles where id = owner_id;
  if n <> 0 then raise exception 'removal did not revoke the profile (%)', n; end if;

  select count(*) into n from public.books where id = probe_book;
  if n <> 0 then raise exception 'removal did not revoke the books (%)', n; end if;

  select count(*) into n from storage.objects
   where bucket_id = 'avatars' and name = object_path;
  if n <> 0 then raise exception 'removal did not revoke the avatar (%)', n; end if;

  execute 'reset role';

  raise notice 'visibility: six call sites, four states each -- all pass';
end $$;

rollback;
