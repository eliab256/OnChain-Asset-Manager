import { defineConfig } from "vitest/config";

// Two projects: fast unit/property tests next to the sources, fork tests against a running anvil.
export default defineConfig({
  test: {
    projects: [
      {
        test: {
          name: "unit",
          include: ["src/**/*.test.ts"],
          setupFiles: ["./test/setup/fastCheck.ts"],
        },
      },
      {
        test: {
          name: "fork",
          include: ["test/**/*.integration.test.ts"],
          setupFiles: ["./test/setup/fastCheck.ts"],
          testTimeout: 60_000,
          hookTimeout: 60_000,
          pool: "forks",
        },
      },
    ],
  },
});
