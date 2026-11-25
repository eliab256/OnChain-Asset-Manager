// Entry point of the indexer. Minimal start (indexer-roadmap.md step 3): configuration, chain id check,
// backfill from the checkpoint to the head, then exit. The live loop and SIGINT / SIGTERM arrive with step 5.
import { fileURLToPath } from "node:url";
import { protocolAddresses } from "@oam/abi";
import { createPrismaClient } from "@oam/db";
import { config as loadDotenv } from "dotenv";
import { assertChainId, closeChainClients, createChainClients } from "./chain/clients.js";
import { configSecrets, describeConfig, loadConfig } from "./config.js";
import { errorFields, logger } from "./logger.js";
import type { HandlerMap } from "./pipeline.js";
import { backfill } from "./runner.js";

/** Handlers by event name: none yet, every event is only stored in RawEvent (the first ones come with step 4). */
const handlers: HandlerMap = {};

async function main(): Promise<void> {
  loadDotenv({ path: fileURLToPath(new URL("../.env", import.meta.url)), quiet: true });
  const config = loadConfig(process.env);
  logger.redact(configSecrets(config));
  logger.info("configuration loaded", describeConfig(config));

  const clients = createChainClients(config);
  const prisma = createPrismaClient(config.databaseUrl);
  try {
    await assertChainId(clients.http, config.chainId);
    const startedAt = Date.now();
    const result = await backfill(
      { prisma, client: clients.http, chainId: config.chainId, handlers, batchSize: config.batchSize },
      protocolAddresses[config.chainId],
    );
    logger.info("backfill done", {
      chainId: config.chainId,
      fromBlock: result.bootstrap.fromBlock,
      head: result.head,
      blocksProcessed: result.range.blocksProcessed,
      insertedContracts: result.bootstrap.insertedContracts,
      elapsedMs: Date.now() - startedAt,
    });
  } finally {
    // A failure while closing must not hide the error that stopped the process.
    await prisma.$disconnect().catch((error: unknown) => logger.warn("prisma disconnect failed", errorFields(error)));
    await closeChainClients(clients);
  }
}

main().catch((error: unknown) => {
  logger.error("indexer stopped", errorFields(error));
  process.exitCode = 1;
});
