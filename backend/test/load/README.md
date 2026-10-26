# Load test (SPEC §19)

100 simulated online drivers sending a location every 4 s, plus 5 ride requests per minute, for 10 minutes.
Targets: API p95 < 300 ms, no dropped offers (every request gets at least one `ride_offers` row).

Run against **staging** (OTP bypass enabled), never production.

```sh
# 1. Create 100 approved drivers + 50 riders and save their tokens (needs the admin credentials).
API_BASE_URL=https://api-staging.example.com ADMIN_EMAIL=... ADMIN_PASSWORD=... \
  npx ts-node test/load/seed.ts            # writes test/load/accounts.json

# 2. Drive the load (k6: https://k6.io).
API_BASE_URL=https://api-staging.example.com k6 run test/load/ride-load.js
```

`seed.ts` registers each driver with six auto-approved documents, so the staging R2 bucket is not touched
(the documents are never uploaded; only their keys are recorded). Clean up afterwards by resetting the
staging database (`docs/RUNBOOK.md`, "Reset staging").
