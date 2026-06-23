// wagmi.config.ts
import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "src/abis/generated.ts",
  plugins: [
    foundry({
      project: "../", // path alla root del progetto Foundry
      include: [
        "Router.sol/**",
        "IndexManager.sol/**",
        "Index.sol/**",
        "SwapManager.sol/**",
        "MultiSigWallet.sol/**",
      ],
    }),
  ],
});
