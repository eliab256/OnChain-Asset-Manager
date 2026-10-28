// Single entry point of the fork project. All suites share one anvil node and isolate each test
// with evm_snapshot / evm_revert, so they must run in one file: separate files would run in
// parallel worker processes against the same node and revert each other's state.
import { afterEach, beforeEach, describe, it } from "vitest";
import { describeTitle, revert, setupContext, snapshot } from "./helpers/chain.js";
import { batchesSuite } from "./suites/batches.js";
import { indexManagerSuite } from "./suites/indexManager.js";
import { multiSigSuite } from "./suites/multiSig.js";
import { previewsSuite } from "./suites/previews.js";
import { readsSuite } from "./suites/reads.js";
import { routerSuite } from "./suites/router.js";

// Resolved at collection time so the suite is skipped (not failed) when no node is running.
const ctx = await setupContext();

describe.skipIf(ctx === undefined)(`@oam/sdk on ${describeTitle(ctx)}`, () => {
  if (ctx === undefined) {
    it.skip("needs `make anvil && make deploy-anvil` or `make anvil-fork && make deploy-fork`", () => {});
    return;
  }

  let id: `0x${string}`;
  beforeEach(async () => {
    id = await snapshot(ctx);
  });
  afterEach(async () => {
    await revert(ctx, id);
  });

  readsSuite(ctx);
  routerSuite(ctx);
  previewsSuite(ctx);
  indexManagerSuite(ctx);
  batchesSuite(ctx);
  multiSigSuite(ctx);
});
