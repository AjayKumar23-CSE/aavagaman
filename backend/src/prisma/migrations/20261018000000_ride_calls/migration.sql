-- Masked calling (D-058): every call the app bridges through the Aavagaman number.
CREATE TYPE "call_status" AS ENUM ('initiated', 'ringing', 'in_progress', 'completed', 'no_answer', 'busy', 'failed');

CREATE TABLE "ride_calls" (
    "id"               UUID NOT NULL DEFAULT uuid_generate_v4(),
    "ride_id"          UUID NOT NULL,
    "caller_id"        UUID NOT NULL,
    "callee_id"        UUID NOT NULL,
    "provider"         VARCHAR(20) NOT NULL,
    "provider_call_id" VARCHAR(100),
    "status"           "call_status" NOT NULL DEFAULT 'initiated',
    "duration_s"       INTEGER,
    "created_at"       TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ended_at"         TIMESTAMPTZ(6),

    CONSTRAINT "ride_calls_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "ride_calls_ride_id_created_at_idx" ON "ride_calls"("ride_id", "created_at");
CREATE INDEX "ride_calls_provider_call_id_idx" ON "ride_calls"("provider_call_id");

ALTER TABLE "ride_calls" ADD CONSTRAINT "ride_calls_ride_id_fkey" FOREIGN KEY ("ride_id") REFERENCES "rides"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
ALTER TABLE "ride_calls" ADD CONSTRAINT "ride_calls_caller_id_fkey" FOREIGN KEY ("caller_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
ALTER TABLE "ride_calls" ADD CONSTRAINT "ride_calls_callee_id_fkey" FOREIGN KEY ("callee_id") REFERENCES "users"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
