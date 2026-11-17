// Process log: one JSON object per line on stdout/stderr. bigint values are written as decimal strings.
// Every line goes through the redaction of the registered secrets (RPC keys, DB password), so a secret
// cannot leak through an error message that quotes a URL (viem's HTTP errors do).
import { redact } from "./secrets.js";

export type LogLevel = "debug" | "info" | "warn" | "error";
export type LogFields = Record<string, unknown>;

/**
 * Shorter values are not redacted line-wide: the local database password "oam" would mask the "oam"
 * of every "@oam/abi" in the log. Such a value is not a real secret; describeConfig still masks it.
 */
export const MIN_REDACTED_LENGTH = 6;

let secrets: readonly string[] = [];

function write(level: LogLevel, message: string, fields: LogFields | undefined): void {
  // `base` is spread twice: first to keep time, level and message at the start of the line, then again
  // so a field with the same name (`{ level: "debug" }`) cannot overwrite them.
  const base = { time: new Date().toISOString(), level, message };
  const line = JSON.stringify({ ...base, ...fields, ...base }, (_key, value: unknown) =>
    typeof value === "bigint" ? value.toString() : value,
  );
  const safeLine = redact(line, secrets);
  if (level === "error" || level === "warn") console.error(safeLine);
  else console.log(safeLine);
}

/**
 * Readable message of anything thrown. viem errors already carry a multi-line message; a WebSocket
 * failure arrives as an ErrorEvent, which is not an Error and would print as "[object ErrorEvent]".
 */
export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (error !== null && typeof error === "object") {
    const { message, type } = error as { message?: unknown; type?: unknown };
    if (typeof message === "string" && message !== "") return message;
    // An object made with Object.create(null) has no constructor: this function runs inside the last
    // catch of the process, so it must never throw itself.
    if (typeof type === "string") return `${(error.constructor as { name?: string } | undefined)?.name ?? "Object"}: ${type}`;
  }
  return String(error);
}

/**
 * Log fields describing a thrown value: `error` with the message and, for a real Error, `stack`
 * (where it was thrown). The stack goes through the same redaction as the rest of the line.
 */
export function errorFields(error: unknown): LogFields {
  const fields: LogFields = { error: errorMessage(error) };
  if (error instanceof Error && error.stack !== undefined) fields.stack = error.stack;
  return fields;
}

export const logger = {
  debug: (message: string, fields?: LogFields) => write("debug", message, fields),
  info: (message: string, fields?: LogFields) => write("info", message, fields),
  warn: (message: string, fields?: LogFields) => write("warn", message, fields),
  error: (message: string, fields?: LogFields) => write("error", message, fields),
  /**
   * Registers strings that must never appear in a log line; they are written as ***.
   * Called once at startup with the secrets of the configuration, before anything else is logged.
   */
  redact: (values: readonly string[]) => {
    secrets = [...secrets, ...values.filter((v) => v.length >= MIN_REDACTED_LENGTH)];
  },
};
