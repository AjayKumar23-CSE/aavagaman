-- Keep the telephony provider's reason when a masked call fails (e.g. Exotel trial: number not verified).
ALTER TABLE "ride_calls" ADD COLUMN "failure_reason" VARCHAR(300);
