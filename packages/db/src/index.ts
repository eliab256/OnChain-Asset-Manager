// Entry point of @oam/db: the generated Prisma client plus a factory bound to the Postgres driver adapter.
// Prisma 7 talks to the database through a driver adapter, so every service creates its client here.
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "./generated/prisma/client.js";

export * from "./generated/prisma/client.js";

/**
 * Creates a Prisma client for the given Postgres URL.
 * @param databaseUrl Connection string, e.g. postgresql://oam:oam@localhost:5434/oam.
 */
export function createPrismaClient(databaseUrl: string): PrismaClient {
  return new PrismaClient({ adapter: new PrismaPg({ connectionString: databaseUrl }) });
}
