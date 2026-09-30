-- status 3 = set aside: the reader closed the book short of the end.
--
-- No DDL: `books.status` is a smallint with no CHECK constraint, so the value needs
-- nothing but a name. No CHECK is added here either -- the column has none today and
-- adding one would be a change of a different kind, applied to 473 existing rows.
--
-- `finish_date` on one of these rows is the day the book was CLOSED, not the day it was
-- finished. That is what lets the read view's month grouping and year rail keep working
-- untouched: both read finish_date and neither cares why the book ended.
--
-- Applied through the Supabase MCP server's `apply_migration` rather than `supabase db
-- push`, because this checkout carries pending migrations from parallel work and a push
-- cannot cherry-pick. The filename's timestamp is the one `apply_migration` stamped into
-- `supabase_migrations.schema_migrations`, so the two agree and the CLI does not read this
-- as still-pending -- the drift `AGENTS.md` warns about, avoided by naming the file rather
-- than by a follow-up UPDATE.
comment on column public.books.status is
  '0 not started, 1 reading, 2 finished, 3 set aside (closed short of the end; finish_date is the day it was closed)';
