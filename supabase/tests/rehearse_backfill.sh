#!/bin/sh
# Rehearse the backfill at the one moment it is answerable: after `friendships` exists
# but before `follows` is dropped.
#
# `run_local.sh` applies every migration, which leaves no `follows` table to backfill
# from. This applies the chain up to and including `20260828120000_friendships.sql`,
# stops, and runs the rehearsal against that state.
#
#   sh supabase/tests/rehearse_backfill.sh
set -eu

CONTAINER="${LSDB_CONTAINER:-lsdb}"
DB="${LSDB_NAME:-rehearse}"
PSQL="docker exec -i $CONTAINER psql -U postgres -v ON_ERROR_STOP=1 -q"
STOP_AFTER="20260828120000_friendships.sql"

if ! docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
  echo "no running container '$CONTAINER'" >&2
  exit 1
fi

docker exec "$CONTAINER" psql -U postgres -q \
  -c "drop database if exists $DB;" -c "create database $DB;" >/dev/null

# The harness pins a database-scoped setting by name; keep it pointing at this one.
sed "s/alter database verify /alter database $DB /" supabase/tests/_harness.sql \
  | $PSQL -d "$DB" >/dev/null

for f in supabase/migrations/*.sql; do
  $PSQL -d "$DB" <"$f" >/dev/null
  if [ "$(basename "$f")" = "$STOP_AFTER" ]; then
    echo "applied through $STOP_AFTER"
    break
  fi
done

$PSQL -d "$DB" <supabase/tests/_seed.sql >/dev/null

printf '%-56s' "backfill_rehearsal.sql"
if $PSQL -d "$DB" <supabase/tests/backfill_rehearsal.sql >/tmp/lsdb_reh 2>&1; then
  echo pass
  grep NOTICE /tmp/lsdb_reh | sed 's/^/  /'
else
  echo FAIL
  grep -E 'ERROR|CONTEXT' /tmp/lsdb_reh | head -5 | sed 's/^/  /'
  exit 1
fi
