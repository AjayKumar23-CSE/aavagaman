#!/bin/sh
# Restore a dump into a database (weekly restore test on staging, SPEC §17.7).
# Usage: restore.sh <YYYY-MM-DD> <target-db>   e.g. restore.sh 2026-10-03 ride_restore_test
set -eu
DAY="$1"; TARGET="$2"
KEY="backups/ride-${DAY}.sql.gz"
echo "[restore] fetching s3://${S3_BUCKET}/${KEY} into ${TARGET}"
psql -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS \"${TARGET}\"" -c "CREATE DATABASE \"${TARGET}\""
aws --endpoint-url "${S3_ENDPOINT}" s3 cp "s3://${S3_BUCKET}/${KEY}" - | gunzip | psql -d "${TARGET}" -v ON_ERROR_STOP=1 -q
psql -d "${TARGET}" -tAc "SELECT 'rides=' || count(*) FROM rides" 
echo "[restore] ok"
