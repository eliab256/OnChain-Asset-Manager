// The database handle every repository receives as its first argument.
// The pipeline passes the transaction client of the block; a test or a one-off read can pass the
// PrismaClient itself, which is assignable to the same type.
import type { Prisma } from "@oam/db";

/** A Prisma client or the client of an open interactive transaction. */
export type Db = Prisma.TransactionClient;
