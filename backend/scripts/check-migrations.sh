#!/usr/bin/env bash
# Fails if schema.prisma and the SQL migrations have drifted (SPEC §18).
# The indexes Prisma cannot model (docs/DECISIONS.md D-004) are expected to
# show up as DROP INDEX in the diff and are ignored.
# Needs SHADOW_DATABASE_URL pointing at an empty PostGIS database.
set -euo pipefail
export PRISMA_HIDE_UPDATE_MESSAGE=1
cd "$(dirname "$0")/.."

diff_sql=$(npx prisma migrate diff \
  --from-migrations src/prisma/migrations \
  --to-schema-datamodel src/prisma/schema.prisma \
  --shadow-database-url "$SHADOW_DATABASE_URL" \
  --script 2>/dev/null)

remaining=$(printf '%s\n' "$diff_sql" \
  | grep -vE '^\s*(--.*)?$' \
  | grep -vE 'DROP INDEX "(one_active_vehicle_per_driver|one_active_ride_per_driver|service_areas_gix|rides_pickup_gix)";' \
  | grep -vE '^(CREATE SCHEMA|-- This is an empty migration)' || true)

if [ -n "$remaining" ]; then
  echo "schema.prisma and migrations have drifted. Unexpected diff:"
  echo "$remaining"
  echo
  echo "Create a migration: npx prisma migrate dev --create-only --name <change>"
  exit 1
fi
echo "Migrations match schema.prisma."
