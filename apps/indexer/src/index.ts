// Entry point of the indexer (indexer.md §4): configuration, checks of every RPC provider, backfill from the
// checkpoint to the head, then the live loop until SIGINT / SIGTERM or a permanent error. A stop waits for the
// block in progress, then closes Prisma and the clients: the next start resumes from the checkpoint.
import { fileURLToPath } from "node:url";
import { protocolAddresses } from "@oam/abi";
import { createPrismaClient } from "@oam/db";
import { config as loadDotenv } from "dotenv";
import { closeChainClients, createChainClients } from "./chain/clients.js";
import { checkProviders } from "./chain/providers.js";
import { configSecrets, describeConfig, loadConfig } from "./config.js";
import { handlers } from "./handlers/index.js";
import { startLive, wsBlockWatch } from "./live.js";
import { errorFields, logger } from "./logger.js";
import { backfill, catchUpRound, createCatchUp } from "./runner.js";

/** Exit code of a forced stop (second signal), the shell's convention for SIGINT. */
const FORCED_EXIT_CODE = 130;

/** Resolves when `signal` aborts. */
function aborted(signal: AbortSignal): Promise<void> {
  return new Promise((resolve) => {
    if (signal.aborted) return resolve();
    signal.addEventListener("abort", () => resolve(), { once: true });
  });
}

async function main(): Promise<void> {
  loadDotenv({ path: fileURLToPath(new URL("../.env", import.meta.url)), quiet: true });
  const config = loadConfig(process.env);
  logger.redact(configSecrets(config));
  logger.info("configuration loaded", describeConfig(config));

  // The first signal asks for a clean stop; a second one, while waiting for it, exits at once.
  const stop = new AbortController();
  const onSignal = (signal: NodeJS.Signals): void => {
    if (stop.signal.aborted) {
      logger.warn("second signal: exiting without waiting for the block in progress", { signal });
      process.exit(FORCED_EXIT_CODE);
    }
    logger.info("stop requested: finishing the block in progress", { signal });
    stop.abort();
  };
  process.on("SIGINT", onSignal);
  process.on("SIGTERM", onSignal);

  const clients = createChainClients(config);
  const prisma = createPrismaClient(config.databaseUrl);
  try {
    const deployment = protocolAddresses[config.chainId];
    const statuses = await checkProviders(clients.providers, { chainId: config.chainId, ...deployment });
    for (const status of statuses) {
      if (status.status === "ok") logger.info("rpc provider checked", { url: status.url });
      else logger.warn("rpc provider unreachable at startup, not checked: used only if it answers later", { url: status.url, ...errorFields(status.error) });
    }

    const deps = { prisma, client: clients.http, chainId: config.chainId, handlers, batchSize: config.batchSize };
    const startedAt = Date.now();
    const result = await backfill({ ...deps, signal: stop.signal }, deployment);
    logger.info(result.range.stopped ? "backfill stopped" : "backfill done", {
      chainId: config.chainId,
      fromBlock: result.bootstrap.fromBlock,
      head: result.head,
      lastBlock: result.range.lastBlock,
      blocksProcessed: result.range.blocksProcessed,
      insertedContracts: result.bootstrap.insertedContracts,
      elapsedMs: Date.now() - startedAt,
    });
    if (stop.signal.aborted) return;

    let fatal: { error: unknown } | undefined;
    const catchUp = createCatchUp(catchUpRound(deps, deployment.startBlock), {
      onFatal: (error) => {
        fatal = { error };
        stop.abort();
      },
    });
    const live = startLive({
      trigger: catchUp.trigger,
      watch: clients.ws === undefined ? undefined : wsBlockWatch(clients.ws),
      guardMs: config.pollIntervalMs,
    });
    logger.info("live", { websocket: clients.ws !== undefined, guardMs: config.pollIntervalMs });
    // Blocks produced during the backfill would otherwise wait for the next announcement or the guard.
    catchUp.trigger();

    await aborted(stop.signal);
    live.stop();
    await catchUp.stop();
    if (fatal !== undefined) throw fatal.error;
    logger.info("indexer stopped cleanly");
  } finally {
    process.off("SIGINT", onSignal);
    process.off("SIGTERM", onSignal);
    // A failure while closing must not hide the error that stopped the process.
    await prisma.$disconnect().catch((error: unknown) => logger.warn("prisma disconnect failed", errorFields(error)));
    await closeChainClients(clients);
  }
}

main().catch((error: unknown) => {
  logger.error("indexer stopped", errorFields(error));
  process.exitCode = 1;
});
