-- CreateEnum
CREATE TYPE "ride_payment" AS ENUM ('cash', 'online');

-- AlterTable
ALTER TABLE "rides" ADD COLUMN     "payment_method" "ride_payment" NOT NULL DEFAULT 'cash';
