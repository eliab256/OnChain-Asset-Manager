// ESLint flat config for every TypeScript workspace (packages/*, apps/*).
// Type-aware rules use the tsconfig of each package through the project service.
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactHooks from "eslint-plugin-react-hooks";
import reactRefresh from "eslint-plugin-react-refresh";

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
      "packages/db/src/generated/",
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
          allowDefaultProject: ["packages/*/vitest.config.ts"],
        },
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    // React front-end (apps/web): rules of hooks and Vite fast refresh boundaries
    files: ["apps/web/**/*.{ts,tsx}"],
    extends: [reactHooks.configs.flat.recommended],
    plugins: { "react-refresh": reactRefresh },
    rules: {
      "react-refresh/only-export-components": [
        "warn",
        { allowConstantExport: true },
      ],
    },
  },
  {
    // Plain JS config files are not part of any tsconfig project
    files: ["**/*.{js,mjs,cjs}"],
    extends: [tseslint.configs.disableTypeChecked],
  },
);
