-- Minimal stand-ins for the Supabase-managed objects the migrations reference, so the
-- real migration chain can be executed against a plain Postgres.
--
-- This is a **test harness, not a schema**. It is never applied to a real database:
-- Supabase provides all of this. It exists so that a migration can be proved to parse,
-- apply in order, and enforce its policies before it is pointed at production -- which
-- matters most for `20260828120100_friends_only_visibility.sql`, a single transaction
-- that drops `follows` after reading it.
--
--   docker exec -i lsdb psql -U postgres -d verify -v ON_ERROR_STOP=1 \
--     -f supabase/tests/_harness.sql
--
-- What is faithful, because the migrations depend on the behaviour:
--
--   * `auth.uid()` reads `request.jwt.claims`, exactly as Supabase's does, so
--     `set local request.jwt.claims` drives the policies in tests.
--   * `auth.users` exists with a uuid primary key, because `profiles.id` references it.
--   * `anon` / `authenticated` / `service_role` exist as roles, because migrations
--     GRANT and REVOKE against them.
--   * `storage.objects` has `bucket_id` and `name`, the two columns the avatars policy
--     joins on.
--
-- What is deliberately fake:
--
--   * `net.http_post` records its arguments instead of making a request. That turns
--     "did the function try to notify?" into an assertable fact, which is how the poke
--     guard-split fix is tested without a network.

create extension if not exists "pgcrypto";

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

grant usage on schema public to anon, authenticated, service_role;

create schema if not exists auth;
create schema if not exists storage;
create schema if not exists net;

grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema storage to anon, authenticated, service_role;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Reads the JWT claims the way Supabase's does, so `set local request.jwt.claims`
-- switches identity in tests. Returns NULL when unset, which is the anonymous case the
-- privacy audit turned on: `is_profile_visible()` had to be checked with `auth.uid()`
-- null, and that is only reachable if this returns NULL rather than raising.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(
    coalesce(
      current_setting('request.jwt.claim.sub', true),
      (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
    ),
    ''
  )::uuid;
$$;

create or replace function auth.role()
returns text
language sql
stable
as $$
  select coalesce(
    current_setting('request.jwt.claim.role', true),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    'anon'
  );
$$;

create table if not exists storage.buckets (
  id text primary key,
  name text not null,
  public boolean not null default false,
  -- The avatars migration sets both of these when it creates its bucket. Present
  -- because the real table has them, not because anything under test reads them.
  file_size_limit bigint,
  allowed_mime_types text[],
  owner uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text references storage.buckets(id),
  name text,
  owner uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  metadata jsonb
);

alter table storage.objects enable row level security;

-- Supabase's helper: splits an object path on '/' and returns the directory parts. The
-- avatars policies use `storage.foldername(name)[1]` to check the owning user id.
create or replace function storage.foldername(name text)
returns text[]
language sql
immutable
as $$
  select string_to_array(regexp_replace(name, '/[^/]*$', ''), '/');
$$;

create or replace function storage.filename(name text)
returns text
language sql
immutable
as $$
  select regexp_replace(name, '^.*/', '');
$$;

-- Records instead of sending. `poke_user()` fires this, and asserting on the recorded
-- row is how the test proves an anonymous caller no longer reaches the push path.
create table if not exists net.http_requests (
  id bigserial primary key,
  url text,
  body jsonb,
  requested_at timestamptz not null default now()
);

create or replace function net.http_post(
  url text,
  body jsonb default '{}'::jsonb,
  params jsonb default '{}'::jsonb,
  headers jsonb default '{}'::jsonb,
  timeout_milliseconds integer default 5000
)
returns bigint
language plpgsql
as $$
declare
  new_id bigint;
begin
  insert into net.http_requests (url, body) values (url, body) returning id into new_id;
  return new_id;
end;
$$;

-- `poke_user()` reads this via current_setting. Real deployments set it as a database
-- setting; a session-level default keeps the function from raising here.
alter database verify set app.settings.edge_function_url = 'http://harness.invalid';

-- Table privileges, which Supabase grants for you and a bare Postgres does not.
--
-- This is the layer *above* RLS and it is easy to conflate the two: without a GRANT,
-- `authenticated` gets "permission denied for table" and never reaches a policy at all
-- -- so a test would report a failure that says nothing about the policy it meant to
-- exercise. Granting broadly here is correct precisely because RLS is what the tests
-- are actually checking: the privilege must not be the thing doing the denying.
--
-- An event trigger rather than a one-shot grant, because migrations run *after* this
-- file and create tables as they go -- `friendships` among them.
create or replace function public._harness_grant_new_tables()
returns event_trigger
language plpgsql
as $$
declare
  obj record;
begin
  for obj in
    select * from pg_event_trigger_ddl_commands()
    where command_tag in ('CREATE TABLE', 'CREATE TABLE AS')
  loop
    execute format(
      'grant select, insert, update, delete on %s to anon, authenticated, service_role',
      obj.object_identity
    );
  end loop;
end;
$$;

drop event trigger if exists _harness_grant_trigger;
create event trigger _harness_grant_trigger
  on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS')
  execute function public._harness_grant_new_tables();

grant select, insert, update, delete on all tables in schema public
  to anon, authenticated, service_role;
grant select, insert, update, delete on storage.objects
  to anon, authenticated, service_role;
grant select on storage.buckets to anon, authenticated, service_role;
grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;
