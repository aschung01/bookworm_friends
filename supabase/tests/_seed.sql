-- Three profiles for the SQL tests to borrow.
--
-- The tests deliberately do not invent users -- `avatar_policies_test.sql` says why:
-- `profiles.id` references `auth.users`, so fabricating one inside a test would be far
-- more invasive than borrowing. Against the linked database there are real rows to
-- borrow. Against a throwaway container there are none, so this creates the minimum:
-- three users, three profiles, and nothing else.
--
-- Applied by `run_local.sh` only, after the migrations. Never applied to a real
-- database. Three rather than two because the friendship tests need a third party who
-- is not in the pair, which is the case a `USING (true)` policy cannot fail.

insert into auth.users (id, email)
values
  ('11111111-1111-4111-8111-111111111111', 'alice@example.test'),
  ('22222222-2222-4222-8222-222222222222', 'bob@example.test'),
  ('33333333-3333-4333-8333-333333333333', 'carol@example.test')
on conflict (id) do nothing;

-- `handle_new_user()` fires on auth.users insert and creates the profile row, so these
-- may already exist. Update rather than insert-or-ignore, to guarantee the usernames
-- the tests read.
-- `handle` is NOT NULL as of `20260821100303_add_profile_handle.sql`, so these are
-- spelled out rather than left to `generate_handle()`: a test that borrows "the first
-- profile by created_at" wants stable, recognisable rows.
insert into public.profiles (id, username, handle, created_at)
values
  ('11111111-1111-4111-8111-111111111111', 'alice', 'alice_test', now() - interval '3 days'),
  ('22222222-2222-4222-8222-222222222222', 'bob',   'bob_test',   now() - interval '2 days'),
  ('33333333-3333-4333-8333-333333333333', 'carol', 'carol_test', now() - interval '1 day')
on conflict (id) do update
  set username = excluded.username,
      handle = excluded.handle;
