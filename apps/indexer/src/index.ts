// Entry point of the indexer. For now (indexer-roadmap.md steps 1-2) it reads the configuration,
// checks the RPC chain id and logs both; bootstrap, backfill and live loop arrive with steps 3-4.
import { fileURLToPath } from "node:url";
import { config as loadDotenv } from "dotenv";
import { assertChainId, closeChainClients, createChainClients } from "./chain/clients.js";
import { configSecrets, describeConfig, loadConfig } from "./config.js";
import { errorFields, logger } from "./logger.js";

async function main(): Promise<void> {
  loadDotenv({ path: fileURLToPath(new URL("../.env", import.meta.url)), quiet: true });
  const config = loadConfig(process.env);
  logger.redact(configSecrets(config));
  logger.info("configuration loaded", describeConfig(config));

  const clients = createChainClients(config);
  try {
    await assertChainId(clients.http, config.chainId);
    const head = await clients.http.getBlockNumber();
    logger.info("rpc connected", { chainId: config.chainId, head, websocket: clients.ws !== undefined });
  } finally {
    await closeChainClients(clients);
  }
}

main().catch((error: unknown) => {
  logger.error("indexer stopped", errorFields(error));
  process.exitCode = 1;
});
