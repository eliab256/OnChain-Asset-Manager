// Database helpers of the integration tests: a Prisma client on the test database and a reset
// that empties every table between tests.
import { createPrismaClient, type PrismaClient } from "@oam/db";
import { afterAll, beforeAll, beforeEach } from "vitest";
import { testDatabaseUrl } from "./env.js";

/** Creates a Prisma client on TEST_DATABASE_URL (checked: the name must end in "_test"). */
export function createTestPrisma(): PrismaClient {
  return createPrismaClient(testDatabaseUrl());
}

/** Prisma's own bookkeeping table: emptying it would make migrate deploy apply the init again. */
const KEPT_TABLES = new Set(["_prisma_migrations"]);

/**
 * Empties every table of the public schema (except the migrations table) in one statement,
 * restarting the autoincrement ids so that tests see the same ids on every run.
 * @param prisma A client created by createTestPrisma.
 */
export async function resetDatabase(prisma: PrismaClient): Promise<void> {
  const rows = await prisma.$queryRaw<{ tablename: string }[]>`
    SELECT tablename FROM pg_tables WHERE schemaname = 'public'`;
  const tables = rows.map((row) => row.tablename).filter((name) => !KEPT_TABLES.has(name));
  if (tables.length === 0) return;
  const list = tables.map((name) => `"public"."${name.replaceAll('"', '""')}"`).join(", ");
  await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${list} RESTART IDENTITY CASCADE`);
}

/**
 * Registers the usual hooks of an integration file: one client for the file, an empty database
 * before each test (before, not after: a failed test leaves its rows to inspect), disconnect at the end.
 * @returns A getter for the client, valid inside tests and hooks.
 */
export function useTestDatabase(): () => PrismaClient {
  let prisma: PrismaClient | undefined;
  beforeAll(() => {
    prisma = createTestPrisma();
  });
  beforeEach(async () => {
    await resetDatabase(get());
  });
  afterAll(async () => {
    await prisma?.$disconnect();
  });
  function get(): PrismaClient {
    if (prisma === undefined) throw new Error("useTestDatabase: the client exists only inside tests and hooks");
    return prisma;
  }
  return get;
}
