/*
  Warnings:

  - You are about to drop the column `hasTransferredIn` on the `Position` table. All the data in the column will be lost.

*/
-- AlterEnum
ALTER TYPE "NotificationType" ADD VALUE 'SHARES_RECEIVED';

-- AlterTable
ALTER TABLE "Position" DROP COLUMN "hasTransferredIn";

-- CreateTable
CREATE TABLE "WalletGroup" (
    "id" BIGSERIAL NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WalletGroup_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WalletLink" (
    "address" VARCHAR(42) NOT NULL,
    "groupId" BIGINT NOT NULL,
    "signature" TEXT NOT NULL,
    "linkedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WalletLink_pkey" PRIMARY KEY ("address")
);

-- CreateTable
CREATE TABLE "TransferCostDeclaration" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "recipient" VARCHAR(42) NOT NULL,
    "pricePerShareUsd" DECIMAL(78,0) NOT NULL,
    "signature" TEXT NOT NULL,
    "declaredAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TransferCostDeclaration_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TransferCost" (
    "transferId" BIGINT NOT NULL,
    "selfTransfer" BOOLEAN NOT NULL DEFAULT false,
    "costBasisUsd" DECIMAL(78,0),

    CONSTRAINT "TransferCost_pkey" PRIMARY KEY ("transferId")
);

-- CreateTable
CREATE TABLE "PositionCost" (
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "user" VARCHAR(42) NOT NULL,
    "costBasisUsd" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "unknownCostShares" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "realizedPnlUsd" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PositionCost_pkey" PRIMARY KEY ("chainId","indexAddress","user")
);

-- CreateIndex
CREATE INDEX "WalletLink_groupId_idx" ON "WalletLink"("groupId");

-- CreateIndex
CREATE UNIQUE INDEX "TransferCostDeclaration_chainId_txHash_indexAddress_recipie_key" ON "TransferCostDeclaration"("chainId", "txHash", "indexAddress", "recipient");

-- CreateIndex
CREATE INDEX "TransferCost_selfTransfer_costBasisUsd_idx" ON "TransferCost"("selfTransfer", "costBasisUsd");

-- AddForeignKey
ALTER TABLE "WalletLink" ADD CONSTRAINT "WalletLink_groupId_fkey" FOREIGN KEY ("groupId") REFERENCES "WalletGroup"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TransferCost" ADD CONSTRAINT "TransferCost_transferId_fkey" FOREIGN KEY ("transferId") REFERENCES "ShareTransfer"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "PositionCost" ADD CONSTRAINT "PositionCost_chainId_indexAddress_user_fkey" FOREIGN KEY ("chainId", "indexAddress", "user") REFERENCES "Position"("chainId", "indexAddress", "user") ON DELETE CASCADE ON UPDATE CASCADE;
