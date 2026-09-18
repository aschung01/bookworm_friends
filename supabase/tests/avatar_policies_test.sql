-- Verifies the `avatars` bucket policies against the real database.
--
-- These two policies are the access-control boundary for profile photos, and nothing in
-- the Dart test suite can reach them: the client tests fake the image provider, so they
-- never touch storage at all. Run this after any change to `is_profile_visible()`, the
-- `friendships` policies, or the bucket policies.
--
--   supabase db query --linked -f supabase/tests/avatar_policies_test.sql
--
-- Silence is a pass. Every assertion raises on failure, and the whole thing runs inside
-- a transaction that is rolled back, so it leaves no trace -- it borrows two real
-- profiles rather than inventing any, because `profiles.id` references `auth.users` and
-- fabricating users would be far more invasive than this.
--
-- The role switching is the point. `postgres` bypasses RLS, so a test that did not
-- `set local role authenticated` would pass no matter what the policies said.
--
-- ---------------------------------------------------------------------------
-- What this file used to assert, and why it was wrong
-- ---------------------------------------------------------------------------
--
-- Until `20260828120100_friends_only_visibility.sql` this test **asserted the bug**. It
-- set the owner `is_private = true`, inserted a *unilateral* follow -- stranger follows
-- owner, no reciprocity, no consent -- and then asserted that the follower could read
-- the private profile's photo. It passed, every time, and what it was pinning was that
-- anyone could grant themselves access to a private library by inserting one row.
--
-- That is worth recording rather than quietly deleting: the test was not broken, it was
-- faithful to a design that was. A green suite is only as good as what it claims.
--
-- The structure survives intact. Probes 1 and 4 are unchanged; probe 2's follow becomes
-- a friendship, probe 3's unfollow becomes a removal, and the `is_private` setup goes
-- with the column -- the owner is now simply not a friend, which is what makes them
-- unreadable.

begin;

do $$
declare
  owner_id      uuid;
  stranger_id   uuid;
  lo            uuid;
  hi            uuid;
  object_path   text;
  owner_claims  text;
  other_claims  text;
  n_stranger    int;
  n_friend      int;
  n_removed     int;
  n_owner       int;
begin
  select id into owner_id from public.profiles order by created_at limit 1;
  select id into stranger_id
    from public.profiles where id <> owner_id order by created_at limit 1;

  if owner_id is null or stranger_id is null then
    raise exception 'need at least two profiles to test against';
  end if;

  object_path  := owner_id::text || '/rls-probe.jpg';
  owner_claims := json_build_object('sub', owner_id, 'role', 'authenticated')::text;
  other_claims := json_build_object('sub', stranger_id, 'role', 'authenticated')::text;
  lo := least(owner_id, stranger_id);
  hi := greatest(owner_id, stranger_id);

  -- A profile wearing a photo, and no friendship between the two.
  --
  -- No `is_private` any more: under friends-only every profile is private to
  -- non-friends, so the column had nothing left to gate and was dropped. The absence of
  -- a friendship is now the entire setup.
  update public.profiles set avatar_path = object_path where id = owner_id;
  delete from public.friendships where user_a = lo and user_b = hi;
  insert into storage.objects (bucket_id, name) values ('avatars', object_path)
    on conflict do nothing;

  -- 1. A stranger cannot read the photo.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', other_claims);
  select count(*) into n_stranger
    from storage.objects where bucket_id = 'avatars' and name = object_path;
  execute 'reset role';

  -- 2. A friend can.
  --
  -- **One row, inserted once, granting both directions** -- where this used to be a
  -- one-directional follow that the stranger could write unilaterally. The canonical
  -- ordering is what makes a single insert sufficient.
  insert into public.friendships (user_a, user_b) values (lo, hi)
    on conflict do nothing;
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', other_claims);
  select count(*) into n_friend
    from storage.objects where bucket_id = 'avatars' and name = object_path;
  execute 'reset role';

  -- 3. And stops being able to the moment the friendship is removed. This is the case a
  --    public bucket could never satisfy, and the whole reason the bucket is private.
  delete from public.friendships where user_a = lo and user_b = hi;
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', other_claims);
  select count(*) into n_removed
    from storage.objects where bucket_id = 'avatars' and name = object_path;
  execute 'reset role';

  -- 4. The owner can always read their own, via the manage-own policy rather than the
  --    visibility join -- which is what keeps an avatar readable in the moment between
  --    the upload and the profile row pointing at it.
  execute 'set local role authenticated';
  execute format('set local request.jwt.claims = %L', owner_claims);
  select count(*) into n_owner
    from storage.objects where bucket_id = 'avatars' and name = object_path;
  execute 'reset role';

  if n_stranger <> 0 then
    raise exception 'a stranger read a non-friend''s avatar (% rows)', n_stranger;
  end if;
  if n_friend <> 1 then
    raise exception 'a friend could not read the avatar (% rows)', n_friend;
  end if;
  if n_removed <> 0 then
    raise exception 'removing the friendship did not revoke access (% rows)', n_removed;
  end if;
  if n_owner <> 1 then
    raise exception 'the owner could not read their own avatar (% rows)', n_owner;
  end if;

  raise notice 'avatars policies: all four cases pass';
end $$;

rollback;
