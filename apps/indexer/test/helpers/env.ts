// Test database URL for the integration tests (indexer.md §3, "Test d'integrazione").
// The tests truncate every table, so the URL is accepted only when it names a database ending in
// "_test" and is not the DATABASE_URL the indexer writes to.
import { fileURLToPath } from "node:url";
import { config as loadDotenv } from "dotenv";

export const TEST_DATABASE_SUFFIX = "_test";

/** Thrown when TEST_DATABASE_URL is missing or could point at a database that is not a test one. */
export class TestDatabaseUrlError extends Error {
  constructor(message: string) {
    super(`${message}. Set TEST_DATABASE_URL in apps/indexer/.env (see .env.example).`);
    this.name = "TestDatabaseUrlError";
  }
}

/**
 * Checks that a URL is safe to truncate: postgres protocol, a database name ending in "_test",
 * and a different database from `databaseUrl`.
 * @param raw The candidate TEST_DATABASE_URL.
 * @param databaseUrl The DATABASE_URL of the indexer, if set.
 * @returns The URL, unchanged.
 */
export function assertTestDatabaseUrl(raw: string | undefined, databaseUrl?: string): string {
  if (raw === undefined || raw.trim() === "") throw new TestDatabaseUrlError("TEST_DATABASE_URL is not set");
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new TestDatabaseUrlError("TEST_DATABASE_URL is not a valid URL");
  }
  if (url.protocol !== "postgres:" && url.protocol !== "postgresql:") {
    throw new TestDatabaseUrlError("TEST_DATABASE_URL must use the postgres:// or postgresql:// protocol");
  }
  const name = decodeURIComponent(url.pathname.replace(/^\//, ""));
  if (!name.endsWith(TEST_DATABASE_SUFFIX)) {
    throw new TestDatabaseUrlError(`TEST_DATABASE_URL names the database "${name}", which does not end in "${TEST_DATABASE_SUFFIX}"`);
  }
  if (databaseUrl !== undefined && sameDatabase(url, databaseUrl)) {
    throw new TestDatabaseUrlError("TEST_DATABASE_URL points at the same database as DATABASE_URL");
  }
  return raw;
}

function sameDatabase(a: URL, rawB: string): boolean {
  let b: URL;
  try {
    b = new URL(rawB);
  } catch {
    return false;
  }
  return a.hostname === b.hostname && (a.port || "5432") === (b.port || "5432") && a.pathname === b.pathname;
}

/** Loads apps/indexer/.env (without overriding variables already set) and returns the checked test URL. */
export function testDatabaseUrl(): string {
  loadDotenv({ path: fileURLToPath(new URL("../../.env", import.meta.url)), quiet: true });
  return assertTestDatabaseUrl(process.env["TEST_DATABASE_URL"], process.env["DATABASE_URL"]);
}
