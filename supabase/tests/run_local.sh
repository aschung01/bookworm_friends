#!/bin/sh
# Apply every migration in order to a throwaway Postgres, then run the SQL tests.
#
# The point is that a migration is *executed* before it is pointed at production, not
# merely written. That matters most for `20260828120100_friends_only_visibility.sql`,
# which is one transaction that drops `follows` after reading it: a syntax error or a
# policy that fails to create is not something to discover against real data.
#
#   docker run -d --name lsdb -e POSTGRES_PASSWORD=postgres -p 55433:5432 postgres:15
#   sh supabase/tests/run_local.sh
#
# `_harness.sql` stubs the Supabase-managed objects (auth, storage, net). It is a test
# fixture and is never applied to a real database.
#
# Exits non-zero on the first failure. Silence from a test file is a pass.
set -eu

CONTAINER="${LSDB_CONTAINER:-lsdb}"
DB="${LSDB_NAME:-verify}"
PSQL="docker exec -i $CONTAINER psql -U postgres -v ON_ERROR_STOP=1 -q"

if ! docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then
  echo "no running container '$CONTAINER'." >&2
  echo "  docker run -d --name $CONTAINER -e POSTGRES_PASSWORD=postgres -p 55433:5432 postgres:15" >&2
  exit 1
fi

echo "recreating $DB"
docker exec "$CONTAINER" psql -U postgres -q \
  -c "drop database if exists $DB;" -c "create database $DB;" >/dev/null

echo "harness"
$PSQL -d "$DB" <supabase/tests/_harness.sql >/dev/null

echo "migrations"
for f in supabase/migrations/*.sql; do
  printf '  %-56s' "$(basename "$f")"
  if $PSQL -d "$DB" <"$f" >/tmp/lsdb_out 2>&1; then
    echo ok
  else
    echo FAIL
    sed 's/^/      /' /tmp/lsdb_out
    exit 1
  fi
done

echo "seed"
$PSQL -d "$DB" <supabase/tests/_seed.sql >/dev/null

echo "tests"
status=0
for f in supabase/tests/*_test.sql; do
  printf '  %-56s' "$(basename "$f")"
  if $PSQL -d "$DB" <"$f" >/tmp/lsdb_out 2>&1; then
    echo pass
  else
    echo FAIL
    grep -E 'ERROR|CONTEXT|NOTICE' /tmp/lsdb_out | head -6 | sed 's/^/      /'
    status=1
  fi
done

exit $status
