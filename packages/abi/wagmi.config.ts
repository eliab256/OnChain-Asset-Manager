import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

// ABIs are generated from the Foundry artifacts in out/.
// The plugin does not run forge itself: it passes the project path to the
// shell unquoted and the repo path contains a space. The npm scripts run
// `forge build` first; in watch mode the plugin regenerates whenever out/ changes.
export default defineConfig({
  out: "src/generated.ts",
  plugins: [
    foundry({
      project: "../..",
      include: [
        "Index.sol/Index.json",
        "IndexManager.sol/IndexManager.json",
        "IndexFactory.sol/IndexFactory.json",
        "Router.sol/Router.json",
        "SwapManager.sol/SwapManager.json",
        "PriceFeedManager.sol/PriceFeedManager.json",
        "MultiSigWallet.sol/MultiSigWallet.json",
        "TimelockController.sol/TimelockController.json",
      ],
      forge: {
        build: false,
        rebuild: false,
      },
    }),
  ],
});
