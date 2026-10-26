#!/usr/bin/env bash
# Production OSRM data (SPEC §17.3). Re-run quarterly.
# Usage: infra/osrm/prepare.sh [output-dir]   (default: infra/osrm/data)
set -euo pipefail

OUT="${1:-$(cd "$(dirname "$0")" && pwd)/data}"
PBF_URL="${PBF_URL:-https://download.geofabrik.de/asia/india/northern-zone-latest.osm.pbf}"
BBOX="76.6,28.0,77.9,29.1"   # SPEC §17.3 clip box
OSRM_IMAGE="${OSRM_IMAGE:-osrm/osrm-backend}"
OSMIUM_IMAGE="${OSMIUM_IMAGE:-stefda/osmium-tool}"

mkdir -p "$OUT"
cd "$OUT"

echo "==> Downloading $PBF_URL"
curl -fL -o northern-zone.osm.pbf "$PBF_URL"

echo "==> Clipping to NCR bbox $BBOX"
docker run --rm -v "$PWD:/data" "$OSMIUM_IMAGE" \
  osmium extract -b "$BBOX" /data/northern-zone.osm.pbf -o /data/ncr.osm.pbf --overwrite

echo "==> Building MLD graph"
docker run --rm -v "$PWD:/data" "$OSRM_IMAGE" osrm-extract -p /opt/car.lua /data/ncr.osm.pbf
docker run --rm -v "$PWD:/data" "$OSRM_IMAGE" osrm-partition /data/ncr.osrm
docker run --rm -v "$PWD:/data" "$OSRM_IMAGE" osrm-customize /data/ncr.osrm

rm -f northern-zone.osm.pbf
echo "==> Done. Copy $OUT/ncr.osrm* into the osrm-data volume."
