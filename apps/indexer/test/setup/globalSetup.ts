// Global setup of the integration project: runs once, before any integration file.
// Checks TEST_DATABASE_URL and applies the existing migrations of @oam/db to it with
// `prisma migrate deploy`, which also creates the database when it does not exist yet.
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { testDatabaseUrl } from "../helpers/env.js";

const repoRoot = fileURLToPath(new URL("../../../../", import.meta.url));

export default function setup(): void {
  const url = testDatabaseUrl();
  try {
    execFileSync("npm", ["run", "migrate:deploy", "--workspace", "@oam/db", "--silent"], {
      cwd: repoRoot,
      // DATABASE_URL is what prisma.config.ts reads; dotenv there does not override it.
      env: { ...process.env, DATABASE_URL: url, PRISMA_HIDE_UPDATE_MESSAGE: "1" },
      stdio: "pipe",
    });
  } catch (error) {
    const output = (name: "stdout" | "stderr"): string =>
      typeof error === "object" && error !== null && name in error ? String((error as Record<string, unknown>)[name]) : "";
    throw new Error(`prisma migrate deploy failed on the test database (is Postgres up? make db)\n${output("stdout")}${output("stderr")}`, {
      cause: error,
    });
  }
}
