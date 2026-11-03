-- CreateEnum
CREATE TYPE "IndexAction" AS ENUM ('INITIALIZE', 'REBALANCE', 'PROPOSE_WEIGHTS', 'EXECUTE_WEIGHTS', 'CANCEL_WEIGHTS', 'COLLECT_FEES');

-- CreateEnum
CREATE TYPE "ContractKind" AS ENUM ('INDEX_MANAGER', 'INDEX', 'PRICE_FEED_MANAGER', 'SWAP_MANAGER', 'ROUTER', 'MULTISIG_WALLET', 'TIMELOCK', 'PRICE_FEED_AGGREGATOR');

-- CreateEnum
CREATE TYPE "TradeKind" AS ENUM ('SEED', 'MINT', 'REDEEM');

-- CreateEnum
CREATE TYPE "ProposalStatus" AS ENUM ('PENDING', 'EXECUTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "RebalanceOrigin" AS ENUM ('DIRECT', 'WEIGHTS_UPDATE');

-- CreateEnum
CREATE TYPE "RebalanceOutcome" AS ENUM ('SUCCESS', 'FAILED', 'SKIPPED');

-- CreateEnum
CREATE TYPE "NavTrigger" AS ENUM ('EVENT', 'PRICE');

-- CreateEnum
CREATE TYPE "TimelockOpStatus" AS ENUM ('SCHEDULED', 'EXECUTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "SignatureStatus" AS ENUM ('VALID', 'USED', 'INVALIDATED', 'ARCHIVED');

-- CreateEnum
CREATE TYPE "NotificationType" AS ENUM ('TRADE_CONFIRMED', 'REBALANCE_EXECUTED', 'REBALANCE_FAILED', 'WEIGHTS_PROPOSED', 'WEIGHTS_UPDATED', 'WEIGHTS_CANCELLED', 'PRICE_FEED_STALE', 'MULTISIG_TO_SIGN', 'MULTISIG_READY');

-- CreateEnum
CREATE TYPE "KeeperJob" AS ENUM ('REBALANCE', 'EXECUTE_WEIGHTS', 'COLLECT_FEES');

-- CreateEnum
CREATE TYPE "KeeperAttemptStatus" AS ENUM ('PENDING', 'SUCCESS', 'PARTIAL', 'FAILED');

-- CreateTable
CREATE TABLE "Block" (
    "chainId" INTEGER NOT NULL,
    "number" BIGINT NOT NULL,
    "hash" CHAR(66) NOT NULL,
    "parentHash" CHAR(66) NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Block_pkey" PRIMARY KEY ("chainId","number")
);

-- CreateTable
CREATE TABLE "Checkpoint" (
    "chainId" INTEGER NOT NULL,
    "lastBlockNumber" BIGINT NOT NULL,
    "lastBlockHash" CHAR(66) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Checkpoint_pkey" PRIMARY KEY ("chainId")
);

-- CreateTable
CREATE TABLE "RawEvent" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "blockNumber" BIGINT NOT NULL,
    "blockHash" CHAR(66) NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,
    "address" VARCHAR(42) NOT NULL,
    "eventName" TEXT NOT NULL,
    "args" JSONB NOT NULL,

    CONSTRAINT "RawEvent_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Contract" (
    "chainId" INTEGER NOT NULL,
    "address" VARCHAR(42) NOT NULL,
    "kind" "ContractKind" NOT NULL,
    "startBlock" BIGINT NOT NULL,
    "parentAddress" VARCHAR(42),
    "active" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Contract_pkey" PRIMARY KEY ("chainId","address")
);

-- CreateTable
CREATE TABLE "IndexerError" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "blockNumber" BIGINT,
    "context" TEXT,
    "message" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "IndexerError_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Token" (
    "chainId" INTEGER NOT NULL,
    "address" VARCHAR(42) NOT NULL,
    "symbol" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "decimals" INTEGER NOT NULL,

    CONSTRAINT "Token_pkey" PRIMARY KEY ("chainId","address")
);

-- CreateTable
CREATE TABLE "Index" (
    "chainId" INTEGER NOT NULL,
    "address" VARCHAR(42) NOT NULL,
    "asset0" VARCHAR(42) NOT NULL,
    "asset1" VARCHAR(42) NOT NULL,
    "feePercentage" INTEGER NOT NULL,
    "assetManager" VARCHAR(42) NOT NULL,
    "initialWeight0" INTEGER NOT NULL,
    "initialWeight1" INTEGER NOT NULL,
    "weight0" INTEGER NOT NULL,
    "weight1" INTEGER NOT NULL,
    "reserve0" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "reserve1" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "totalSupply" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "accruedFees" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "holderCount" INTEGER NOT NULL DEFAULT 0,
    "createdBlock" BIGINT NOT NULL,
    "createdTxHash" CHAR(66) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL,
    "initialized" BOOLEAN NOT NULL DEFAULT false,
    "initializer" VARCHAR(42),
    "initializedBlock" BIGINT,
    "initializedAt" TIMESTAMP(3),
    "updatedBlock" BIGINT NOT NULL,

    CONSTRAINT "Index_pkey" PRIMARY KEY ("chainId","address")
);

-- CreateTable
CREATE TABLE "Trade" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "kind" "TradeKind" NOT NULL,
    "user" VARCHAR(42) NOT NULL,
    "shares" DECIMAL(78,0) NOT NULL,
    "asset0Amount" DECIMAL(78,0) NOT NULL,
    "asset1Amount" DECIMAL(78,0) NOT NULL,
    "usdcAmount" DECIMAL(78,0),
    "feeAmount" DECIMAL(78,0),
    "asset0UsdValue" DECIMAL(78,0),
    "asset1UsdValue" DECIMAL(78,0),
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Trade_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ShareTransfer" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "from" VARCHAR(42) NOT NULL,
    "to" VARCHAR(42) NOT NULL,
    "value" DECIMAL(78,0) NOT NULL,
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ShareTransfer_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Position" (
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "user" VARCHAR(42) NOT NULL,
    "balance" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "sharesMinted" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "sharesBurned" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "usdcIn" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "usdcOut" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "feesPaid" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "seedUsdValue" DECIMAL(78,0) NOT NULL DEFAULT 0,
    "hasTransferredIn" BOOLEAN NOT NULL DEFAULT false,
    "updatedBlock" BIGINT NOT NULL,

    CONSTRAINT "Position_pkey" PRIMARY KEY ("chainId","indexAddress","user")
);

-- CreateTable
CREATE TABLE "Allowance" (
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "owner" VARCHAR(42) NOT NULL,
    "spender" VARCHAR(42) NOT NULL,
    "value" DECIMAL(78,0) NOT NULL,
    "updatedBlock" BIGINT NOT NULL,
    "updatedTx" CHAR(66) NOT NULL,

    CONSTRAINT "Allowance_pkey" PRIMARY KEY ("chainId","indexAddress","owner","spender")
);

-- CreateTable
CREATE TABLE "Rebalance" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "origin" "RebalanceOrigin" NOT NULL,
    "outcome" "RebalanceOutcome" NOT NULL,
    "caller" VARCHAR(42),
    "asset0ReserveBefore" DECIMAL(78,0),
    "asset1ReserveBefore" DECIMAL(78,0),
    "asset0ReserveAfter" DECIMAL(78,0),
    "asset1ReserveAfter" DECIMAL(78,0),
    "reasonData" TEXT,
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Rebalance_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WeightProposal" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "oldWeight0" INTEGER NOT NULL,
    "oldWeight1" INTEGER NOT NULL,
    "newWeight0" INTEGER NOT NULL,
    "newWeight1" INTEGER NOT NULL,
    "executableAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "status" "ProposalStatus" NOT NULL DEFAULT 'PENDING',
    "proposer" VARCHAR(42),
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,
    "closedBy" VARCHAR(42),
    "closedBlock" BIGINT,
    "closedTxHash" CHAR(66),
    "closedAt" TIMESTAMP(3),

    CONSTRAINT "WeightProposal_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "FeeCollection" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "feeCollector" VARCHAR(42) NOT NULL,
    "amount" DECIMAL(78,0) NOT NULL,
    "caller" VARCHAR(42),
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "FeeCollection_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "IndexActionLog" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "caller" VARCHAR(42) NOT NULL,
    "action" "IndexAction" NOT NULL,
    "success" BOOLEAN NOT NULL,
    "reasonData" TEXT,
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "IndexActionLog_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "NavSnapshot" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "indexAddress" VARCHAR(42) NOT NULL,
    "blockNumber" BIGINT NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,
    "trigger" "NavTrigger" NOT NULL,
    "reserve0" DECIMAL(78,0) NOT NULL,
    "reserve1" DECIMAL(78,0) NOT NULL,
    "totalSupply" DECIMAL(78,0) NOT NULL,
    "price0Usd" DECIMAL(78,0) NOT NULL,
    "price1Usd" DECIMAL(78,0) NOT NULL,
    "navUsd" DECIMAL(78,0) NOT NULL,
    "sharePriceUsd" DECIMAL(78,0) NOT NULL,

    CONSTRAINT "NavSnapshot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PriceFeed" (
    "chainId" INTEGER NOT NULL,
    "asset" VARCHAR(42) NOT NULL,
    "feed" VARCHAR(42) NOT NULL,
    "aggregator" VARCHAR(42),
    "maxDelay" INTEGER NOT NULL,
    "decimals" INTEGER,
    "lastRoundId" DECIMAL(78,0),
    "lastAnswer" DECIMAL(78,0),
    "lastUpdatedAt" TIMESTAMP(3),
    "registeredBlock" BIGINT NOT NULL,
    "updatedBlock" BIGINT NOT NULL,

    CONSTRAINT "PriceFeed_pkey" PRIMARY KEY ("chainId","asset")
);

-- CreateTable
CREATE TABLE "PriceFeedProposal" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "asset" VARCHAR(42) NOT NULL,
    "feed" VARCHAR(42) NOT NULL,
    "maxDelay" INTEGER NOT NULL,
    "executableAt" TIMESTAMP(3) NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "status" "ProposalStatus" NOT NULL DEFAULT 'PENDING',
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,
    "closedBlock" BIGINT,
    "closedTxHash" CHAR(66),
    "closedAt" TIMESTAMP(3),

    CONSTRAINT "PriceFeedProposal_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PricePoint" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "feed" VARCHAR(42) NOT NULL,
    "aggregator" VARCHAR(42) NOT NULL,
    "roundId" DECIMAL(78,0) NOT NULL,
    "answer" DECIMAL(78,0) NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "PricePoint_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RoleMember" (
    "chainId" INTEGER NOT NULL,
    "contract" VARCHAR(42) NOT NULL,
    "role" CHAR(66) NOT NULL,
    "account" VARCHAR(42) NOT NULL,
    "grantedBy" VARCHAR(42) NOT NULL,
    "grantedBlock" BIGINT NOT NULL,
    "grantedTxHash" CHAR(66) NOT NULL,

    CONSTRAINT "RoleMember_pkey" PRIMARY KEY ("chainId","contract","role","account")
);

-- CreateTable
CREATE TABLE "MultisigWallet" (
    "chainId" INTEGER NOT NULL,
    "address" VARCHAR(42) NOT NULL,
    "owners" TEXT[],
    "requiredConfirmations" INTEGER NOT NULL,
    "createdBlock" BIGINT NOT NULL,

    CONSTRAINT "MultisigWallet_pkey" PRIMARY KEY ("chainId","address")
);

-- CreateTable
CREATE TABLE "MultisigTransaction" (
    "chainId" INTEGER NOT NULL,
    "wallet" VARCHAR(42) NOT NULL,
    "txId" DECIMAL(78,0) NOT NULL,
    "proposer" VARCHAR(42) NOT NULL,
    "target" VARCHAR(42) NOT NULL,
    "value" DECIMAL(78,0) NOT NULL,
    "data" TEXT NOT NULL,
    "confirmations" INTEGER NOT NULL DEFAULT 0,
    "executed" BOOLEAN NOT NULL DEFAULT false,
    "executor" VARCHAR(42),
    "executedBlock" BIGINT,
    "executedTxHash" CHAR(66),
    "executedAt" TIMESTAMP(3),
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MultisigTransaction_pkey" PRIMARY KEY ("chainId","wallet","txId")
);

-- CreateTable
CREATE TABLE "MultisigConfirmation" (
    "chainId" INTEGER NOT NULL,
    "wallet" VARCHAR(42) NOT NULL,
    "txId" DECIMAL(78,0) NOT NULL,
    "owner" VARCHAR(42) NOT NULL,
    "active" BOOLEAN NOT NULL,
    "confirmedBlock" BIGINT NOT NULL,
    "confirmedTxHash" CHAR(66) NOT NULL,
    "revokedBlock" BIGINT,
    "revokedTxHash" CHAR(66),

    CONSTRAINT "MultisigConfirmation_pkey" PRIMARY KEY ("chainId","wallet","txId","owner")
);

-- CreateTable
CREATE TABLE "MultisigSignature" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "wallet" VARCHAR(42) NOT NULL,
    "txId" DECIMAL(78,0) NOT NULL,
    "signer" VARCHAR(42) NOT NULL,
    "signature" TEXT NOT NULL,
    "nonce" DECIMAL(78,0) NOT NULL,
    "digest" CHAR(66) NOT NULL,
    "status" "SignatureStatus" NOT NULL DEFAULT 'VALID',
    "usedTxHash" CHAR(66),
    "submittedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "MultisigSignature_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "TimelockConfig" (
    "chainId" INTEGER NOT NULL,
    "address" VARCHAR(42) NOT NULL,
    "minDelay" BIGINT NOT NULL,
    "updatedBlock" BIGINT NOT NULL,

    CONSTRAINT "TimelockConfig_pkey" PRIMARY KEY ("chainId","address")
);

-- CreateTable
CREATE TABLE "TimelockOperation" (
    "chainId" INTEGER NOT NULL,
    "timelock" VARCHAR(42) NOT NULL,
    "operationId" CHAR(66) NOT NULL,
    "predecessor" CHAR(66) NOT NULL,
    "salt" CHAR(66),
    "delay" BIGINT NOT NULL,
    "readyAt" TIMESTAMP(3) NOT NULL,
    "status" "TimelockOpStatus" NOT NULL DEFAULT 'SCHEDULED',
    "scheduledBlock" BIGINT NOT NULL,
    "scheduledTxHash" CHAR(66) NOT NULL,
    "scheduledAt" TIMESTAMP(3) NOT NULL,
    "closedBlock" BIGINT,
    "closedTxHash" CHAR(66),
    "closedAt" TIMESTAMP(3),

    CONSTRAINT "TimelockOperation_pkey" PRIMARY KEY ("chainId","timelock","operationId")
);

-- CreateTable
CREATE TABLE "TimelockCall" (
    "chainId" INTEGER NOT NULL,
    "timelock" VARCHAR(42) NOT NULL,
    "operationId" CHAR(66) NOT NULL,
    "callIndex" INTEGER NOT NULL,
    "target" VARCHAR(42) NOT NULL,
    "value" DECIMAL(78,0) NOT NULL,
    "data" TEXT NOT NULL,
    "executed" BOOLEAN NOT NULL DEFAULT false,

    CONSTRAINT "TimelockCall_pkey" PRIMARY KEY ("chainId","timelock","operationId","callIndex")
);

-- CreateTable
CREATE TABLE "ProxyUpgrade" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "proxy" VARCHAR(42) NOT NULL,
    "implementation" VARCHAR(42) NOT NULL,
    "timelockOperationId" CHAR(66),
    "blockNumber" BIGINT NOT NULL,
    "txHash" CHAR(66) NOT NULL,
    "logIndex" INTEGER NOT NULL,
    "timestamp" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ProxyUpgrade_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Notification" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "recipient" VARCHAR(42) NOT NULL,
    "type" "NotificationType" NOT NULL,
    "indexAddress" VARCHAR(42),
    "payload" JSONB NOT NULL,
    "dedupKey" TEXT NOT NULL,
    "read" BOOLEAN NOT NULL DEFAULT false,
    "readAt" TIMESTAMP(3),
    "blockNumber" BIGINT,
    "txHash" CHAR(66),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "KeeperAttempt" (
    "id" BIGSERIAL NOT NULL,
    "chainId" INTEGER NOT NULL,
    "job" "KeeperJob" NOT NULL,
    "indexAddress" VARCHAR(42),
    "status" "KeeperAttemptStatus" NOT NULL DEFAULT 'PENDING',
    "txHash" CHAR(66),
    "nonce" INTEGER,
    "gasLimit" DECIMAL(78,0),
    "reasonData" TEXT,
    "decodedError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "KeeperAttempt_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Block_chainId_hash_key" ON "Block"("chainId", "hash");

-- CreateIndex
CREATE INDEX "RawEvent_chainId_address_eventName_idx" ON "RawEvent"("chainId", "address", "eventName");

-- CreateIndex
CREATE INDEX "RawEvent_chainId_eventName_blockNumber_idx" ON "RawEvent"("chainId", "eventName", "blockNumber");

-- CreateIndex
CREATE INDEX "RawEvent_chainId_blockNumber_idx" ON "RawEvent"("chainId", "blockNumber");

-- CreateIndex
CREATE UNIQUE INDEX "RawEvent_chainId_txHash_logIndex_key" ON "RawEvent"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "Contract_chainId_kind_active_idx" ON "Contract"("chainId", "kind", "active");

-- CreateIndex
CREATE INDEX "IndexerError_chainId_createdAt_idx" ON "IndexerError"("chainId", "createdAt");

-- CreateIndex
CREATE INDEX "Index_chainId_asset0_idx" ON "Index"("chainId", "asset0");

-- CreateIndex
CREATE INDEX "Index_chainId_asset1_idx" ON "Index"("chainId", "asset1");

-- CreateIndex
CREATE INDEX "Trade_chainId_indexAddress_timestamp_idx" ON "Trade"("chainId", "indexAddress", "timestamp");

-- CreateIndex
CREATE INDEX "Trade_chainId_user_timestamp_idx" ON "Trade"("chainId", "user", "timestamp");

-- CreateIndex
CREATE UNIQUE INDEX "Trade_chainId_txHash_logIndex_key" ON "Trade"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "ShareTransfer_chainId_indexAddress_blockNumber_idx" ON "ShareTransfer"("chainId", "indexAddress", "blockNumber");

-- CreateIndex
CREATE INDEX "ShareTransfer_chainId_from_idx" ON "ShareTransfer"("chainId", "from");

-- CreateIndex
CREATE INDEX "ShareTransfer_chainId_to_idx" ON "ShareTransfer"("chainId", "to");

-- CreateIndex
CREATE UNIQUE INDEX "ShareTransfer_chainId_txHash_logIndex_key" ON "ShareTransfer"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "Position_chainId_user_idx" ON "Position"("chainId", "user");

-- CreateIndex
CREATE INDEX "Allowance_chainId_owner_idx" ON "Allowance"("chainId", "owner");

-- CreateIndex
CREATE INDEX "Rebalance_chainId_indexAddress_timestamp_idx" ON "Rebalance"("chainId", "indexAddress", "timestamp");

-- CreateIndex
CREATE INDEX "Rebalance_chainId_outcome_idx" ON "Rebalance"("chainId", "outcome");

-- CreateIndex
CREATE UNIQUE INDEX "Rebalance_chainId_txHash_logIndex_key" ON "Rebalance"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "WeightProposal_chainId_indexAddress_status_idx" ON "WeightProposal"("chainId", "indexAddress", "status");

-- CreateIndex
CREATE INDEX "WeightProposal_chainId_status_executableAt_idx" ON "WeightProposal"("chainId", "status", "executableAt");

-- CreateIndex
CREATE UNIQUE INDEX "WeightProposal_chainId_txHash_logIndex_key" ON "WeightProposal"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "FeeCollection_chainId_indexAddress_timestamp_idx" ON "FeeCollection"("chainId", "indexAddress", "timestamp");

-- CreateIndex
CREATE UNIQUE INDEX "FeeCollection_chainId_txHash_logIndex_key" ON "FeeCollection"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "IndexActionLog_chainId_indexAddress_action_timestamp_idx" ON "IndexActionLog"("chainId", "indexAddress", "action", "timestamp");

-- CreateIndex
CREATE INDEX "IndexActionLog_chainId_caller_idx" ON "IndexActionLog"("chainId", "caller");

-- CreateIndex
CREATE INDEX "IndexActionLog_chainId_success_action_idx" ON "IndexActionLog"("chainId", "success", "action");

-- CreateIndex
CREATE UNIQUE INDEX "IndexActionLog_chainId_txHash_logIndex_key" ON "IndexActionLog"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "NavSnapshot_chainId_indexAddress_timestamp_idx" ON "NavSnapshot"("chainId", "indexAddress", "timestamp");

-- CreateIndex
CREATE UNIQUE INDEX "NavSnapshot_chainId_indexAddress_blockNumber_key" ON "NavSnapshot"("chainId", "indexAddress", "blockNumber");

-- CreateIndex
CREATE INDEX "PriceFeed_chainId_feed_idx" ON "PriceFeed"("chainId", "feed");

-- CreateIndex
CREATE INDEX "PriceFeedProposal_chainId_asset_status_idx" ON "PriceFeedProposal"("chainId", "asset", "status");

-- CreateIndex
CREATE UNIQUE INDEX "PriceFeedProposal_chainId_txHash_logIndex_key" ON "PriceFeedProposal"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "PricePoint_chainId_feed_updatedAt_idx" ON "PricePoint"("chainId", "feed", "updatedAt");

-- CreateIndex
CREATE UNIQUE INDEX "PricePoint_chainId_txHash_logIndex_key" ON "PricePoint"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "RoleMember_chainId_account_idx" ON "RoleMember"("chainId", "account");

-- CreateIndex
CREATE INDEX "MultisigTransaction_chainId_wallet_executed_idx" ON "MultisigTransaction"("chainId", "wallet", "executed");

-- CreateIndex
CREATE UNIQUE INDEX "MultisigTransaction_chainId_txHash_logIndex_key" ON "MultisigTransaction"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "MultisigSignature_chainId_wallet_status_idx" ON "MultisigSignature"("chainId", "wallet", "status");

-- CreateIndex
CREATE UNIQUE INDEX "MultisigSignature_chainId_wallet_txId_signer_key" ON "MultisigSignature"("chainId", "wallet", "txId", "signer");

-- CreateIndex
CREATE INDEX "TimelockOperation_chainId_status_idx" ON "TimelockOperation"("chainId", "status");

-- CreateIndex
CREATE INDEX "ProxyUpgrade_chainId_proxy_blockNumber_idx" ON "ProxyUpgrade"("chainId", "proxy", "blockNumber");

-- CreateIndex
CREATE UNIQUE INDEX "ProxyUpgrade_chainId_txHash_logIndex_key" ON "ProxyUpgrade"("chainId", "txHash", "logIndex");

-- CreateIndex
CREATE INDEX "Notification_chainId_recipient_read_createdAt_idx" ON "Notification"("chainId", "recipient", "read", "createdAt");

-- CreateIndex
CREATE INDEX "Notification_chainId_blockNumber_idx" ON "Notification"("chainId", "blockNumber");

-- CreateIndex
CREATE UNIQUE INDEX "Notification_chainId_recipient_type_dedupKey_key" ON "Notification"("chainId", "recipient", "type", "dedupKey");

-- CreateIndex
CREATE INDEX "KeeperAttempt_chainId_job_createdAt_idx" ON "KeeperAttempt"("chainId", "job", "createdAt");

-- CreateIndex
CREATE INDEX "KeeperAttempt_chainId_status_idx" ON "KeeperAttempt"("chainId", "status");

-- AddForeignKey
ALTER TABLE "Trade" ADD CONSTRAINT "Trade_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "ShareTransfer" ADD CONSTRAINT "ShareTransfer_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Position" ADD CONSTRAINT "Position_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Allowance" ADD CONSTRAINT "Allowance_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Rebalance" ADD CONSTRAINT "Rebalance_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WeightProposal" ADD CONSTRAINT "WeightProposal_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "FeeCollection" ADD CONSTRAINT "FeeCollection_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "IndexActionLog" ADD CONSTRAINT "IndexActionLog_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "NavSnapshot" ADD CONSTRAINT "NavSnapshot_chainId_indexAddress_fkey" FOREIGN KEY ("chainId", "indexAddress") REFERENCES "Index"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MultisigTransaction" ADD CONSTRAINT "MultisigTransaction_chainId_wallet_fkey" FOREIGN KEY ("chainId", "wallet") REFERENCES "MultisigWallet"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MultisigConfirmation" ADD CONSTRAINT "MultisigConfirmation_chainId_wallet_fkey" FOREIGN KEY ("chainId", "wallet") REFERENCES "MultisigWallet"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "MultisigSignature" ADD CONSTRAINT "MultisigSignature_chainId_wallet_fkey" FOREIGN KEY ("chainId", "wallet") REFERENCES "MultisigWallet"("chainId", "address") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "TimelockCall" ADD CONSTRAINT "TimelockCall_chainId_timelock_operationId_fkey" FOREIGN KEY ("chainId", "timelock", "operationId") REFERENCES "TimelockOperation"("chainId", "timelock", "operationId") ON DELETE CASCADE ON UPDATE CASCADE;
