// ESLint flat config for every TypeScript workspace (packages/*, apps/*).
// Type-aware rules use the tsconfig of each package through the project service.
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: [
      "**/node_modules/",
      "**/dist/",
      "lib/",
      "out/",
      "cache/",
      "broadcast/",
      "coverage/",
      "packages/abi/src/generated.ts",
      "apps/indexer/src/generated/",
    ],
  },
  js.configs.recommended,
  tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: {
          // Config files outside every tsconfig "include"
          defaultProject: "tsconfig.base.json",
          allowDefaultProject: ["packages/*/vitest.config.ts", "apps/*/prisma.config.ts"],
        },
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    // Plain JS config files are not part of any tsconfig project
    files: ["**/*.{js,mjs,cjs}"],
    extends: [tseslint.configs.disableTypeChecked],
  },
);
