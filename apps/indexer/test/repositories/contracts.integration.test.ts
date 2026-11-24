import { ContractKind } from "@oam/db";
import { protocolAddresses } from "@oam/abi";
import { describe, expect, it } from "vitest";
import { insertFixedContracts, insertIndexContract, loadContractKinds } from "../../src/repositories/contracts.js";
import { useTestDatabase } from "../helpers/db.js";

const fixed = protocolAddresses[31337];

describe("contracts repository", () => {
  const db = useTestDatabase();

  it("inserts the six fixed contracts with their kind, in lowercase, at the deployment's startBlock", async () => {
    expect(await insertFixedContracts(db(), 31337, fixed)).toBe(6);
    const kinds = await loadContractKinds(db(), 31337);
    expect(kinds).toEqual(
      new Map([
        [fixed.indexManager.toLowerCase(), ContractKind.INDEX_MANAGER],
        [fixed.router.toLowerCase(), ContractKind.ROUTER],
        [fixed.priceFeedManager.toLowerCase(), ContractKind.PRICE_FEED_MANAGER],
        [fixed.swapManager.toLowerCase(), ContractKind.SWAP_MANAGER],
        [fixed.multiSigWallet.toLowerCase(), ContractKind.MULTISIG_WALLET],
        [fixed.timelock.toLowerCase(), ContractKind.TIMELOCK],
      ]),
    );
    const rows = await db().contract.findMany();
    expect(rows.every((row) => row.startBlock === fixed.startBlock)).toBe(true);
  });

  it("leaves out IndexFactory and USDC", async () => {
    await insertFixedContracts(db(), 31337, fixed);
    const kinds = await loadContractKinds(db(), 31337);
    expect(kinds.has(fixed.indexFactory.toLowerCase())).toBe(false);
    expect(kinds.has(fixed.usdc.toLowerCase())).toBe(false);
  });

  it("inserts nothing on the second bootstrap", async () => {
    await insertFixedContracts(db(), 31337, fixed);
    expect(await insertFixedContracts(db(), 31337, fixed)).toBe(0);
    expect(await db().contract.count()).toBe(6);
  });

  it("adds an Index once, in lowercase, with its creation block", async () => {
    const index = "0x00000000000000000000000000000000000000AA";
    expect(await insertIndexContract(db(), 31337, index, 40n)).toBe(true);
    expect(await insertIndexContract(db(), 31337, index, 40n)).toBe(false);
    const row = await db().contract.findUnique({ where: { chainId_address: { chainId: 31337, address: index.toLowerCase() } } });
    expect(row).toMatchObject({ kind: ContractKind.INDEX, startBlock: 40n });
  });

  it("reads only the contracts of the requested chain", async () => {
    await insertFixedContracts(db(), 31337, fixed);
    await insertIndexContract(db(), 31338, "0x00000000000000000000000000000000000000bb", 1n);
    expect((await loadContractKinds(db(), 31338)).size).toBe(1);
    expect((await loadContractKinds(db(), 31337)).size).toBe(6);
  });
});
