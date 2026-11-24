import { defineConfig } from "vitest/config";

// Two projects (indexer.md §3): unit tests next to the sources, with no RPC and no DB, and integration
// tests against a real Postgres (database oam_test) and, from the pipeline on, a running anvil.
export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: "unit",
          include: ["src/**/*.test.ts"],
        },
      },
      {
        test: {
          name: "integration",
          include: ["test/**/*.integration.test.ts"],
          globalSetup: ["./test/setup/globalSetup.ts"],
          testTimeout: 30_000,
          hookTimeout: 60_000,
          // One process for every integration file, one file at a time: the files share the same
          // database (and the same anvil), so running them in parallel would truncate each other's rows.
          // fileParallelism is not a per-project option in vitest 3, singleFork is.
          pool: "forks",
          poolOptions: { forks: { singleFork: true } },
        },
      },
    ],
  },
});
