// Entry point of the indexer. Minimal start (indexer-roadmap.md step 3): configuration, checks of every RPC
// provider, backfill from the checkpoint to the head, then exit. The live loop and SIGINT / SIGTERM arrive with step 5.
import { fileURLToPath } from "node:url";
import { protocolAddresses } from "@oam/abi";
import { createPrismaClient } from "@oam/db";
import { config as loadDotenv } from "dotenv";
import { closeChainClients, createChainClients } from "./chain/clients.js";
import { checkProviders } from "./chain/providers.js";
import { configSecrets, describeConfig, loadConfig } from "./config.js";
import { handlers } from "./handlers/index.js";
import { errorFields, logger } from "./logger.js";
import { backfill } from "./runner.js";

async function main(): Promise<void> {
  loadDotenv({ path: fileURLToPath(new URL("../.env", import.meta.url)), quiet: true });
  const config = loadConfig(process.env);
  logger.redact(configSecrets(config));
  logger.info("configuration loaded", describeConfig(config));

  const clients = createChainClients(config);
  const prisma = createPrismaClient(config.databaseUrl);
  try {
    const deployment = protocolAddresses[config.chainId];
    const statuses = await checkProviders(clients.providers, { chainId: config.chainId, ...deployment });
    for (const status of statuses) {
      if (status.status === "ok") logger.info("rpc provider checked", { url: status.url });
      else logger.warn("rpc provider unreachable at startup, not checked: used only if it answers later", { url: status.url, ...errorFields(status.error) });
    }
    const startedAt = Date.now();
    const result = await backfill(
      { prisma, client: clients.http, chainId: config.chainId, handlers, batchSize: config.batchSize },
      deployment,
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
