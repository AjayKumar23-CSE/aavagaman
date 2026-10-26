/**
 * Seed (SPEC §5): one admin user, one fare_config row, one Delhi NCR service area.
 * Idempotent — safe to run on every deploy.
 */
import { existsSync, readFileSync } from 'node:fs';
import { VEHICLE_TYPES, VehicleType } from '../common/vehicle-types';
import { resolve } from 'node:path';
import { PrismaClient } from '@prisma/client';
import * as argon2 from 'argon2';

if (existsSync('.env')) process.loadEnvFile('.env');

const prisma = new PrismaClient();

function need(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Seed needs ${name} to be set`);
  return v;
}

async function seedAdmin() {
  const phone = need('SEED_ADMIN_PHONE');
  const email = need('SEED_ADMIN_EMAIL');
  const existing = await prisma.user.findUnique({ where: { phone } });
  if (existing) return console.log(`admin: exists (${email})`);
  await prisma.user.create({
    data: {
      phone,
      email,
      name: 'Admin',
      role: 'admin',
      passwordHash: await argon2.hash(need('SEED_ADMIN_PASSWORD'), { type: argon2.argon2id }),
    },
  });
  console.log(`admin: created (${email})`);
}

/** Starting fares per vehicle class (D-056); the admin panel changes them with new versions. */
const FARE_DEFAULTS: Record<VehicleType, Record<'baseFare' | 'perKm' | 'perMin' | 'minFare' | 'cancellationFee', number>> = {
  bike: { baseFare: 20, perKm: 6, perMin: 1, minFare: 30, cancellationFee: 10 },
  auto: { baseFare: 30, perKm: 9, perMin: 1, minFare: 40, cancellationFee: 20 },
  mini: { baseFare: 40, perKm: 10, perMin: 1.25, minFare: 60, cancellationFee: 25 },
  sedan: { baseFare: 50, perKm: 12, perMin: 1.5, minFare: 80, cancellationFee: 30 },
};

async function seedFareConfig() {
  for (const vehicleType of VEHICLE_TYPES) {
    if (await prisma.fareConfig.count({ where: { vehicleType } })) {
      console.log(`fare_config ${vehicleType}: exists`);
      continue;
    }
    const f = FARE_DEFAULTS[vehicleType];
    await prisma.fareConfig.create({ data: { vehicleType, ...f, commissionPct: 15 } });
    console.log(`fare_config ${vehicleType}: created (${f.baseFare} / ${f.perKm} / ${f.perMin} / min ${f.minFare})`);
  }
}

async function seedServiceArea() {
  const name = 'Delhi NCR';
  const [{ count }] = await prisma.$queryRaw<{ count: bigint }[]>`
    SELECT count(*) FROM service_areas WHERE name = ${name}`;
  if (count > 0n) return console.log('service_areas: exists');

  const file =
    process.env.SEED_NCR_GEOJSON ?? resolve(__dirname, '../../../infra/seed/ncr.geojson');
  const fc = JSON.parse(readFileSync(file, 'utf8'));
  const geometry = JSON.stringify(fc.features[0].geometry);
  await prisma.$executeRaw`
    INSERT INTO service_areas (name, polygon)
    VALUES (${name}, ST_GeomFromGeoJSON(${geometry})::geography)`;
  console.log(`service_areas: created (${name})`);
}

async function main() {
  await seedAdmin();
  await seedFareConfig();
  await seedServiceArea();
}

main()
  .catch((e) => {
    console.error(e);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
