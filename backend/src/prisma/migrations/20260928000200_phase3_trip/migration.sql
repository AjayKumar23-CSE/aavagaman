-- AlterTable
ALTER TABLE "rides" ADD COLUMN     "fee_applied_to_ride_id" UUID,
ADD COLUMN     "otp_attempts" SMALLINT NOT NULL DEFAULT 0;

-- AddForeignKey
ALTER TABLE "rides" ADD CONSTRAINT "rides_fee_applied_to_ride_id_fkey" FOREIGN KEY ("fee_applied_to_ride_id") REFERENCES "rides"("id") ON DELETE NO ACTION ON UPDATE NO ACTION;
