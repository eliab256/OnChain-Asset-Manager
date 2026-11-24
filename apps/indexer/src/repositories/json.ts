// Conversion of decoded event arguments to a JSON value for the `args` column of RawEvent.
// JSON has no bigint: uint/int values become decimal strings (db.md, "Convenzioni").
import type { Prisma } from "@oam/db";

/** Thrown for a value that has no JSON form (function, symbol, class instance, NaN). */
export class NotJsonError extends Error {
  constructor(path: string, value: unknown) {
    super(`Value at ${path} has no JSON form: ${typeof value}`);
    this.name = "NotJsonError";
  }
}

function isPlainObject(value: object): value is Record<string, unknown> {
  const prototype: unknown = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function convert(value: unknown, path: string): Prisma.InputJsonValue {
  switch (typeof value) {
    case "bigint":
      return value.toString();
    case "string":
    case "boolean":
      return value;
    case "number":
      if (!Number.isFinite(value)) throw new NotJsonError(path, value);
      return value;
    case "object": {
      if (value === null) throw new NotJsonError(path, value);
      if (Array.isArray(value)) return value.map((item, i) => convert(item, `${path}[${i}]`));
      if (!isPlainObject(value)) throw new NotJsonError(path, value);
      const out: Record<string, Prisma.InputJsonValue> = {};
      for (const [key, inner] of Object.entries(value)) {
        if (inner === undefined) continue;
        out[key] = convert(inner, `${path}.${key}`);
      }
      return out;
    }
    default:
      throw new NotJsonError(path, value);
  }
}

/**
 * Converts decoded event arguments (named object, positional array, nested tuples) to JSON:
 * bigint to decimal string, arrays and plain objects recursively, undefined properties dropped.
 * Any other value (null, function, symbol, class instance, non-finite number) throws, because
 * viem never decodes one and storing it would hide a bug.
 * @param args The `args` of a decoded log.
 */
export function toJsonArgs(args: unknown): Prisma.InputJsonValue {
  return convert(args, "args");
}
