# Runbook

Operations for the Delhi NCR ride-hailing platform (SPEC §17, §18, §19). One VPS runs everything with Docker Compose; the admin panel is on Cloudflare Pages; the apps talk to `https://api.<domain>`.

## 1. Server setup (once)

Ubuntu 24.04, 2 vCPU / 4 GB (2 GB is enough only without OSRM).

```bash
# Docker Engine + Compose plugin
curl -fsSL https://get.docker.com | sh
# Firewall: SSH, HTTP, HTTPS only (SPEC §17.1)
ufw default deny incoming && ufw default allow outgoing
ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw enable
# SSH brute-force protection and unattended security updates
apt-get install -y fail2ban unattended-upgrades && dpkg-reconfigure -plow unattended-upgrades
systemctl enable --now fail2ban

mkdir -p /opt/ride-platform && cd /opt/ride-platform
# From the repo: infra/docker-compose.prod.yml → docker-compose.yml, infra/Caddyfile → Caddyfile,
# infra/backup/ → backup/ (the backup image is built on the server).
```

`/opt/ride-platform/.env` holds every variable from `backend/.env.example` with real values, plus:

| Variable | Used by |
|---|---|
| `API_IMAGE` | image tag to run, e.g. `ghcr.io/<org>/ride-platform/api:<sha>` |
| `API_DOMAIN` | Caddy (`api.example.com`) |
| `POSTGRES_PASSWORD` | postgres, api, worker, backup |
| `BACKUP_BUCKET` | backup (defaults to `S3_BUCKET`) |

Document storage is Cloudflare R2 (`S3_ENDPOINT` = the R2 URL, `S3_REGION=auto`) or Amazon S3 (`S3_ENDPOINT` empty, `S3_REGION` = the bucket's region, e.g. `ap-south-1`). Either way the bucket must block all public access; the API only needs `PutObject` and `GetObject` on it (D-051).

DNS: `A api.example.com → <VPS IP>` (Cloudflare, DNS-only/grey cloud so Caddy can obtain its certificate).

### OSRM data

```bash
# On a machine with Docker and ~4 GB free (quarterly, SPEC §17.3):
infra/osrm/prepare.sh                     # downloads Geofabrik northern zone, clips to NCR, builds MLD data
# copy infra/osrm/data/ncr.osrm* into the osrm-data volume:
docker run --rm -v ride_osrm-data:/data -v "$PWD/infra/osrm/data":/src alpine sh -c 'cp /src/ncr.osrm* /data/'
docker compose restart osrm
```

`GET /health` reports `osrm:false` while routing is unavailable; estimates then fall back to the Google Routes API (`GOOGLE_MAPS_SERVER_KEY`, D-052) or fail with 503 `ROUTING_UNAVAILABLE`.

## 2. Deploy

CI (`.github/workflows/backend.yml`) builds `ghcr.io/<org>/ride-platform/api:<sha>` and `:latest` on every push to `main`. With the repo variable `DEPLOY_ENABLED=true` and secrets `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, it then runs on the server:

```bash
cd /opt/ride-platform
docker compose pull && docker compose up -d api worker && docker compose exec -T api npx prisma migrate deploy
```

Manual deploy is the same three commands. First boot of a fresh database also needs the seed:

```bash
docker compose exec -T api node dist/prisma/seed.js    # admin user, fare config, NCR polygon; idempotent
```

Check: `curl -s https://api.example.com/health` → `{"status":"ok","db":true,"redis":true,"osrm":true}`; `docker compose logs --tail=50 api worker`.

### Rollback

```bash
# Pick the previous image tag from GHCR (or `docker images`), then:
API_IMAGE=ghcr.io/<org>/ride-platform/api:<previous-sha> docker compose up -d api worker
```

Migrations are forward-only. If a migration must be undone, restore the database from the last backup (section 4) **before** starting the old image, and treat the data written in between as lost.

## 3. Day-to-day checks

| What | Where | Healthy |
|---|---|---|
| API up | UptimeRobot on `GET /health` (1-minute interval) | 200 |
| Errors | Sentry projects: backend, rider app, driver app | no new issues |
| Queues | `docker compose exec redis redis-cli LLEN bull:matching:wait` | near 0 |
| Matching health | admin panel → Dashboard, or `GET /metrics` (`ride_offers_today{response="timeout"}` vs total) | timeouts well below accepts |
| Drivers dropping offline | `docker compose logs worker | grep "heartbeat sweeper"` | occasional, not every 10 s |
| Disk | `df -h /var/lib/docker` | < 80 % |

`GET /metrics` is Prometheus text, protected by `METRICS_TOKEN` (`Authorization: Bearer …` or `?token=`), disabled when the variable is unset.

Nightly jobs (worker, IST): 02:30 backup (backup container), 03:00 ride_tracks retention (`TRACK_RETENTION_DAYS`), Monday 06:00 settlements. The payment poller runs every `PAYMENT_POLL_INTERVAL_SECONDS` and the heartbeat sweeper every `HEARTBEAT_SWEEP_SECONDS`.

## 4. Backups and restore (SPEC §17.7)

The `backup` service runs `pg_dump | gzip | aws s3 cp` nightly to `s3://<bucket>/backups/ride-YYYY-MM-DD.sql.gz` on Cloudflare R2 and prunes files older than `RETENTION_DAYS` (30). Verify: `docker compose logs --since 24h backup`.

Manual backup now: `docker compose exec backup /usr/local/bin/backup.sh`.

### Weekly restore test (into staging)

```bash
# On the staging stack:
docker compose -p ride-staging exec backup /usr/local/bin/restore.sh $(date -d yesterday +%F) ride_restore_test
# prints "rides=<n>" from the restored database, then:
docker compose -p ride-staging exec postgres psql -U ride -d postgres -c 'DROP DATABASE ride_restore_test'
```

Record the date and the row count in the ops log. A failed restore is a P1: fix the backup pipeline the same day.

### Full restore to production

```bash
docker compose stop api worker
docker compose exec backup /usr/local/bin/restore.sh <YYYY-MM-DD> ride_restored
docker compose exec postgres psql -U ride -d postgres -c 'ALTER DATABASE ride RENAME TO ride_broken' -c 'ALTER DATABASE ride_restored RENAME TO ride'
docker compose up -d api worker && docker compose exec -T api npx prisma migrate deploy
```

Redis is not backed up: driver positions rebuild as apps reconnect, and BullMQ repeatable jobs are re-registered when the worker starts.

## 5. Staging (SPEC §17.6)

Same Compose file, separate project name and env file on the same server:

```bash
cd /opt/ride-platform
docker compose -p ride-staging --env-file .env.staging -f docker-compose.yml up -d
```

`.env.staging` differs in `API_DOMAIN=api-staging.example.com`, `POSTGRES_PASSWORD`, `OTP_DEV_BYPASS_CODE=123456`, `NODE_ENV=development`, Razorpay **test** keys and a separate R2 bucket. Caddy of the production project cannot bind 80/443 twice, so either run staging on a second small VPS, or add `api-staging.example.com` as a second site to the production Caddyfile pointing at the staging API container (`ride-staging-api-1:3000`) on a shared Docker network.

Reset staging: `docker compose -p ride-staging down -v && docker compose -p ride-staging up -d && docker compose -p ride-staging exec -T api sh -c 'npx prisma migrate deploy && node dist/prisma/seed.js'`.

## 6. Load test (SPEC §19)

See `backend/test/load/README.md`: seed 100 approved drivers and 50 riders on staging, then `k6 run test/load/ride-load.js`. Pass criteria: `http_req_duration p(95) < 300 ms`, `ride_requests_without_offer == 0`.

## 7. Incidents

| Symptom | Likely cause | Action |
|---|---|---|
| Rides stuck in REQUESTED, no offers | worker down, or no drivers online | `docker compose ps worker`, `logs worker`; check `drivers_online` in `/metrics` |
| Drivers go offline every few seconds | phones not sending locations (battery optimisation) or socket drops | driver app "Reconnecting…"; check Caddy/WebSocket logs; confirm `DRIVER_HEARTBEAT_TTL_SECONDS` |
| Estimates fail 503 `ROUTING_UNAVAILABLE` | OSRM container down or data missing | `logs osrm`; rebuild data (section 1) |
| Online payments never become PAID | webhook not reaching the API | Razorpay dashboard → webhook deliveries; the poller recovers captures within `PAYMENT_POLL_INTERVAL_SECONDS` once the attempt is 5 minutes old |
| OTP SMS not arriving | MSG91 balance/DLT template | `logs api | grep MSG91`; drivers/riders can still use the trip OTP shown in the app |
| `GET /health` `db:false` | Postgres down or disk full | `docker compose ps postgres`, `df -h`; restore from backup if the volume is corrupt |

## 8. Secrets rotation

Rotate `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET` only together with a planned logout of everyone (refresh tokens are HMAC'd with the refresh secret). Razorpay webhook secret: update in Razorpay first, then in `.env`, then `docker compose up -d api`. Storage (R2 or S3) keys: update `.env`, restart `api`, `worker`, `backup`.
