// Checks the integration harness itself: the test URL guard, the connection to oam_test with the
// migrated schema, and the reset between tests.
import type { PrismaClient } from "@oam/db";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { createTestPrisma, resetDatabase } from "./helpers/db.js";
import { TestDatabaseUrlError, assertTestDatabaseUrl } from "./helpers/env.js";

describe("assertTestDatabaseUrl", () => {
  const dev = "postgresql://oam:oam@localhost:5434/oam";

  it("accepts a postgres database whose name ends in _test", () => {
    const url = "postgresql://oam:oam@localhost:5434/oam_test";
    expect(assertTestDatabaseUrl(url, dev)).toBe(url);
    expect(assertTestDatabaseUrl("postgres://u:p@db:5432/x_test?schema=public")).toBe("postgres://u:p@db:5432/x_test?schema=public");
  });

  it.each([
    ["missing", undefined],
    ["empty", "  "],
    ["not a URL", "oam_test"],
    ["wrong protocol", "mysql://oam:oam@localhost:5434/oam_test"],
    ["the development database", dev],
    ["a name that only contains _test", "postgresql://oam:oam@localhost:5434/oam_test_copy"],
    ["no database name", "postgresql://oam:oam@localhost:5434"],
  ])("rejects %s", (_label, url) => {
    expect(() => assertTestDatabaseUrl(url, dev)).toThrow(TestDatabaseUrlError);
  });

  it("rejects the same database as DATABASE_URL, even when its name ends in _test", () => {
    const url = "postgresql://oam:oam@localhost:5434/oam_test";
    expect(() => assertTestDatabaseUrl(url, "postgresql://other:pw@localhost:5434/oam_test")).toThrow(/same database/);
  });
});

describe("test database", () => {
  let prisma: PrismaClient;

  beforeAll(() => {
    prisma = createTestPrisma();
  });

  beforeEach(async () => {
    await resetDatabase(prisma);
  });

  afterAll(async () => {
    await prisma.$disconnect();
  });

  it("is connected to a database whose name ends in _test, with the migrations applied", async () => {
    const [row] = await prisma.$queryRaw<{ db: string }[]>`SELECT current_database() AS db`;
    expect(row?.db.endsWith("_test")).toBe(true);
    const migrations = await prisma.$queryRaw<{ name: string }[]>`
      SELECT migration_name AS name FROM _prisma_migrations WHERE finished_at IS NOT NULL`;
    expect(migrations.map((m) => m.name)).toContain("20261112000000_init");
  });

  it("writes and reads back a row", async () => {
    await prisma.checkpoint.create({
      data: { chainId: 31337, lastBlockNumber: 42n, lastBlockHash: `0x${"ab".repeat(32)}` },
    });
    const checkpoint = await prisma.checkpoint.findUnique({ where: { chainId: 31337 } });
    expect(checkpoint?.lastBlockNumber).toBe(42n);
  });

  it("empties every table and restarts the ids on reset", async () => {
    await prisma.checkpoint.create({
      data: { chainId: 31337, lastBlockNumber: 1n, lastBlockHash: `0x${"cd".repeat(32)}` },
    });
    const first = await prisma.indexerError.create({ data: { chainId: 31337, message: "first" } });

    await resetDatabase(prisma);

    expect(await prisma.checkpoint.count()).toBe(0);
    expect(await prisma.indexerError.count()).toBe(0);
    const again = await prisma.indexerError.create({ data: { chainId: 31337, message: "again" } });
    expect(again.id).toBe(first.id);
  });
});
