-- AlterEnum
ALTER TYPE "ProposalStatus" ADD VALUE 'EXPIRED';

-- AlterTable
ALTER TABLE "Index" ADD COLUMN     "name" TEXT NOT NULL,
ADD COLUMN     "symbol" TEXT NOT NULL;

-- AlterTable
ALTER TABLE "PriceFeedProposal" ADD COLUMN     "overwritten" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "TimelockCall" DROP COLUMN "executed";

-- AlterTable
ALTER TABLE "WeightProposal" ADD COLUMN     "overwritten" BOOLEAN NOT NULL DEFAULT false;

