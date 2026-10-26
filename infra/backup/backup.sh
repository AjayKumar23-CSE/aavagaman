#!/bin/sh
# Nightly pg_dump → gzip → R2 as backups/ride-YYYY-MM-DD.sql.gz, pruned after RETENTION_DAYS (SPEC §17.7).
set -eu
DAY=$(date +%F)
KEY="backups/ride-${DAY}.sql.gz"
echo "[backup] $(date -Is) dumping ${PGDATABASE} → s3://${S3_BUCKET}/${KEY}"
pg_dump --no-owner --no-privileges "${PGDATABASE}" | gzip -9 \
  | aws --endpoint-url "${S3_ENDPOINT}" s3 cp - "s3://${S3_BUCKET}/${KEY}" --expected-size 2000000000
echo "[backup] uploaded"

CUTOFF=$(date -d "-${RETENTION_DAYS:-30} days" +%F 2>/dev/null || date -v-"${RETENTION_DAYS:-30}"d +%F)
aws --endpoint-url "${S3_ENDPOINT}" s3 ls "s3://${S3_BUCKET}/backups/" | awk '{print $4}' | while read -r f; do
  d=$(echo "$f" | sed -n 's/^ride-\([0-9-]*\)\.sql\.gz$/\1/p')
  if [ -n "$d" ] && [ "$d" \< "$CUTOFF" ]; then
    echo "[backup] pruning $f"
    aws --endpoint-url "${S3_ENDPOINT}" s3 rm "s3://${S3_BUCKET}/backups/$f"
  fi
done
echo "[backup] done"
