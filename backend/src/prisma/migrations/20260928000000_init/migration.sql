-- CreateExtension
CREATE EXTENSION IF NOT EXISTS "postgis";

-- CreateExtension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- CreateEnum
CREATE TYPE "user_role" AS ENUM ('rider', 'driver', 'admin');

-- CreateEnum
CREATE TYPE "user_status" AS ENUM ('active', 'blocked');

-- CreateEnum
CREATE TYPE "verification_status" AS ENUM ('pending', 'approved', 'rejected', 'suspended');

-- CreateEnum
CREATE TYPE "ride_status" AS ENUM ('REQUESTED', 'ACCEPTED', 'ARRIVED', 'STARTED', 'COMPLETED', 'PAID', 'CANCELLED', 'NO_DRIVER');

-- CreateEnum
CREATE TYPE "cancel_actor" AS ENUM ('rider', 'driver', 'admin', 'system');

-- CreateEnum
CREATE TYPE "offer_response" AS ENUM ('accepted', 'rejected', 'timeout');

-- CreateEnum
CREATE TYPE "payment_method" AS ENUM ('cash', 'upi', 'card', 'wallet');

-- CreateEnum
CREATE TYPE "payment_status" AS ENUM ('pending', 'paid', 'failed', 'refunded');

-- CreateEnum
CREATE TYPE "doc_type" AS ENUM ('driving_licence', 'rc', 'insurance', 'permit', 'id_proof', 'selfie', 'fitness');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "phone" VARCHAR(15) NOT NULL,
    "name" VARCHAR(80),
    "email" VARCHAR(120),
    "role" "user_role" NOT NULL,
    "status" "user_status" NOT NULL DEFAULT 'active',
    "password_hash" TEXT,
    "fcm_token" TEXT,
    "rating_avg" DECIMAL(3,2) DEFAULT 5.00,
    "rating_count" INTEGER DEFAULT 0,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "drivers" (
    "user_id" UUID NOT NULL,
    "licence_no" VARCHAR(40),
    "licence_expiry" DATE,
    "id_last4" VARCHAR(4),
    "selfie_key" TEXT,
    "verification_status" "verification_status" NOT NULL DEFAULT 'pending',
    "reviewer_note" TEXT,
    "approved_by" UUID,
    "approved_at" TIMESTAMPTZ(6),
    "cancel_count_today" INTEGER DEFAULT 0,
    "cancel_count_reset_at" DATE,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "drivers_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "vehicles" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "driver_id" UUID NOT NULL,
    "reg_number" VARCHAR(15) NOT NULL,
    "make" VARCHAR(40),
    "model" VARCHAR(40),
    "colour" VARCHAR(30),
    "vehicle_type" VARCHAR(20) NOT NULL DEFAULT 'sedan',
    "fuel_type" VARCHAR(20),
    "insurance_expiry" DATE,
    "permit_expiry" DATE,
    "fitness_expiry" DATE,
    "active" BOOLEAN DEFAULT true,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "vehicles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "driver_documents" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "driver_id" UUID NOT NULL,
    "doc_type" "doc_type" NOT NULL,
    "file_key" TEXT NOT NULL,
    "status" "verification_status" NOT NULL DEFAULT 'pending',
    "reviewer_note" TEXT,
    "expiry" DATE,
    "uploaded_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "driver_documents_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "fare_config" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "vehicle_type" VARCHAR(20) NOT NULL DEFAULT 'sedan',
    "base_fare" DECIMAL(8,2) NOT NULL,
    "per_km" DECIMAL(8,2) NOT NULL,
    "per_min" DECIMAL(8,2) NOT NULL,
    "min_fare" DECIMAL(8,2) NOT NULL,
    "cancellation_fee" DECIMAL(8,2) NOT NULL DEFAULT 30,
    "night_multiplier" DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    "night_enabled" BOOLEAN NOT NULL DEFAULT false,
    "commission_pct" DECIMAL(5,2) NOT NULL DEFAULT 15.00,
    "gst_pct" DECIMAL(5,2) NOT NULL DEFAULT 5.00,
    "effective_from" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_by" UUID,

    CONSTRAINT "fare_config_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "service_areas" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "name" VARCHAR(60) NOT NULL,
    "polygon" geography(Polygon,4326) NOT NULL,
    "active" BOOLEAN DEFAULT true,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "service_areas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "rides" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "rider_id" UUID NOT NULL,
    "driver_id" UUID,
    "vehicle_id" UUID,
    "status" "ride_status" NOT NULL DEFAULT 'REQUESTED',
    "vehicle_type" VARCHAR(20) NOT NULL DEFAULT 'sedan',
    "pickup_point" geography(Point,4326) NOT NULL,
    "pickup_address" TEXT NOT NULL,
    "drop_point" geography(Point,4326) NOT NULL,
    "drop_address" TEXT NOT NULL,
    "est_distance_m" INTEGER,
    "est_duration_s" INTEGER,
    "est_fare_min" DECIMAL(8,2),
    "est_fare_max" DECIMAL(8,2),
    "actual_distance_m" INTEGER,
    "actual_duration_s" INTEGER,
    "final_fare" DECIMAL(8,2),
    "fare_config_id" UUID,
    "cancellation_fee" DECIMAL(8,2) DEFAULT 0,
    "cancelled_by" "cancel_actor",
    "cancel_reason" TEXT,
    "trip_otp" CHAR(4) NOT NULL,
    "share_token" VARCHAR(32),
    "requested_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "accepted_at" TIMESTAMPTZ(6),
    "arrived_at" TIMESTAMPTZ(6),
    "started_at" TIMESTAMPTZ(6),
    "completed_at" TIMESTAMPTZ(6),
    "paid_at" TIMESTAMPTZ(6),
    "cancelled_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "rides_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ride_offers" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "ride_id" UUID NOT NULL,
    "driver_id" UUID NOT NULL,
    "distance_to_pickup_m" INTEGER,
    "offered_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "responded_at" TIMESTAMPTZ(6),
    "response" "offer_response",

    CONSTRAINT "ride_offers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ride_events" (
    "id" BIGSERIAL NOT NULL,
    "ride_id" UUID NOT NULL,
    "from_status" "ride_status",
    "to_status" "ride_status" NOT NULL,
    "actor" "cancel_actor" NOT NULL,
    "actor_id" UUID,
    "meta" JSONB,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ride_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ride_tracks" (
    "ride_id" UUID NOT NULL,
    "recorded_at" TIMESTAMPTZ(6) NOT NULL,
    "point" geography(Point,4326) NOT NULL,
    "speed_mps" REAL,
    "accuracy_m" REAL,

    CONSTRAINT "ride_tracks_pkey" PRIMARY KEY ("ride_id","recorded_at")
);

-- CreateTable
CREATE TABLE "payments" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "ride_id" UUID NOT NULL,
    "method" "payment_method" NOT NULL,
    "amount" DECIMAL(8,2) NOT NULL,
    "status" "payment_status" NOT NULL DEFAULT 'pending',
    "gateway_order_id" TEXT,
    "gateway_payment_id" TEXT,
    "gateway_signature" TEXT,
    "paid_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ratings" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "ride_id" UUID NOT NULL,
    "from_user_id" UUID NOT NULL,
    "to_user_id" UUID NOT NULL,
    "stars" SMALLINT NOT NULL,
    "comment" TEXT,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ratings_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "driver_settlements" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "driver_id" UUID NOT NULL,
    "period_start" DATE NOT NULL,
    "period_end" DATE NOT NULL,
    "rides_count" INTEGER,
    "gross_fares" DECIMAL(10,2),
    "commission" DECIMAL(10,2),
    "cash_collected" DECIMAL(10,2),
    "online_collected" DECIMAL(10,2),
    "amount_payable" DECIMAL(10,2),
    "settled_at" TIMESTAMPTZ(6),
    "reference" TEXT,
    "settled_by" UUID,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "driver_settlements_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "sos_alerts" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "ride_id" UUID,
    "user_id" UUID NOT NULL,
    "point" geography(Point,4326),
    "acknowledged_by" UUID,
    "acknowledged_at" TIMESTAMPTZ(6),
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sos_alerts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_log" (
    "id" BIGSERIAL NOT NULL,
    "actor_id" UUID,
    "action" VARCHAR(60) NOT NULL,
    "entity" VARCHAR(40),
    "entity_id" UUID,
    "before" JSONB,
    "after" JSONB,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL DEFAULT uuid_generate_v4(),
    "user_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "expires_at" TIMESTAMPTZ(6) NOT NULL,
    "revoked_at" TIMESTAMPTZ(6),
    "device" JSONB,
    "created_at" TIMESTAMPTZ(6) DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_phone_key" ON "users"("phone");

-- CreateIndex
CREATE UNIQUE INDEX "rides_share_token_key" ON "rides"("share_token");

-- CreateIndex
CREATE INDEX "rides_status_time" ON "rides"("status", "requested_at" DESC);

-- CreateIndex
CREATE INDEX "rides_rider" ON "rides"("rider_id", "requested_at" DESC);

-- CreateIndex
CREATE INDEX "rides_driver" ON "rides"("driver_id", "requested_at" DESC);

-- CreateIndex
CREATE INDEX "ride_offers_ride" ON "ride_offers"("ride_id");

-- CreateIndex
CREATE INDEX "ride_events_ride" ON "ride_events"("ride_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "payments_ride_id_key" ON "payments"("ride_id");

-- CreateIndex
CREATE UNIQUE INDEX "ratings_ride_id_from_user_id_key" ON "ratings"("ride_id", "from_user_id");

-- CreateIndex
CREATE UNIQUE INDEX "driver_settlements_driver_id_period_start_key" ON "driver_settlements"("driver_id", "period_start");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "refresh_tokens_user_id_idx" ON "refresh_tokens"("user_id");

-- AddForeignKey
ALTER TABLE "drivers" ADD CONSTRAINT "drivers_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "drivers" ADD CONSTRAINT "drivers_approved_by_fkey" FOREIGN KEY ("approved_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "vehicles" ADD CONSTRAINT "vehicles_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "drivers"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "driver_documents" ADD CONSTRAINT "driver_documents_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "drivers"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "fare_config" ADD CONSTRAINT "fare_config_created_by_fkey" FOREIGN KEY ("created_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rides" ADD CONSTRAINT "rides_rider_id_fkey" FOREIGN KEY ("rider_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rides" ADD CONSTRAINT "rides_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "drivers"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rides" ADD CONSTRAINT "rides_vehicle_id_fkey" FOREIGN KEY ("vehicle_id") REFERENCES "vehicles"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "rides" ADD CONSTRAINT "rides_fare_config_id_fkey" FOREIGN KEY ("fare_config_id") REFERENCES "fare_config"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ride_offers" ADD CONSTRAINT "ride_offers_ride_id_fkey" FOREIGN KEY ("ride_id") REFERENCES "rides"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ride_offers" ADD CONSTRAINT "ride_offers_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "drivers"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ride_events" ADD CONSTRAINT "ride_events_ride_id_fkey" FOREIGN KEY ("ride_id") REFERENCES "rides"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ride_tracks" ADD CONSTRAINT "ride_tracks_ride_id_fkey" FOREIGN KEY ("ride_id") REFERENCES "rides"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_ride_id_fkey" FOREIGN KEY ("ride_id") REFERENCES "rides"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ratings" ADD CONSTRAINT "ratings_ride_id_fkey" FOREIGN KEY ("ride_id") REFERENCES "rides"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ratings" ADD CONSTRAINT "ratings_from_user_id_fkey" FOREIGN KEY ("from_user_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ratings" ADD CONSTRAINT "ratings_to_user_id_fkey" FOREIGN KEY ("to_user_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "driver_settlements" ADD CONSTRAINT "driver_settlements_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "drivers"("user_id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "driver_settlements" ADD CONSTRAINT "driver_settlements_settled_by_fkey" FOREIGN KEY ("settled_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sos_alerts" ADD CONSTRAINT "sos_alerts_ride_id_fkey" FOREIGN KEY ("ride_id") REFERENCES "rides"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sos_alerts" ADD CONSTRAINT "sos_alerts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "sos_alerts" ADD CONSTRAINT "sos_alerts_acknowledged_by_fkey" FOREIGN KEY ("acknowledged_by") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;


-- ---------------------------------------------------------------------------
-- Indexes Prisma cannot express (SPEC §5). Keep in sync with docs/DECISIONS.md D-004.
-- ---------------------------------------------------------------------------

-- One active vehicle per driver
CREATE UNIQUE INDEX "one_active_vehicle_per_driver" ON "vehicles"("driver_id") WHERE "active";

-- Spatial indexes
CREATE INDEX "service_areas_gix" ON "service_areas" USING GIST ("polygon");
CREATE INDEX "rides_pickup_gix" ON "rides" USING GIST ("pickup_point");

-- A driver can have at most one ride in an active state
CREATE UNIQUE INDEX "one_active_ride_per_driver" ON "rides"("driver_id")
  WHERE "status" IN ('ACCEPTED', 'ARRIVED', 'STARTED');
