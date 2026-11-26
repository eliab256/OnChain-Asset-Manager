// The indexer as a child process (src/index.ts run by node with tsx), for the tests that need the real entry point:
// the live loop, SIGINT / SIGTERM and the exit code. Every line the process writes is parsed as the logger's JSON.
import { spawn, type ChildProcess } from "node:child_process";
import { fileURLToPath } from "node:url";

/** One line of the logger (src/logger.ts): time, level, message and free fields. */
export type LogLine = { time: string; level: string; message: string; [field: string]: unknown };

export type IndexerProcess = {
  /** Every line written so far, stdout and stderr together, in arrival order. */
  readonly lines: readonly LogLine[];
  /** Resolves with the first line whose message is `message` (already written or still to come). */
  waitFor: (message: string, timeoutMs?: number) => Promise<LogLine>;
  /** Sends `signal` and resolves with the exit code once the process has ended. */
  stop: (signal?: NodeJS.Signals, timeoutMs?: number) => Promise<number | null>;
};

const INDEXER_DIR = fileURLToPath(new URL("../../", import.meta.url));

/**
 * Starts the indexer with `env` on top of the test process's environment. Variables set here win over
 * apps/indexer/.env, because dotenv does not override what is already set (an empty string included).
 */
export function startIndexer(env: Record<string, string>): IndexerProcess {
  const child: ChildProcess = spawn(process.execPath, ["--import", "tsx", "src/index.ts"], {
    cwd: INDEXER_DIR,
    env: { ...process.env, ...env },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const lines: LogLine[] = [];
  const waiters = new Set<() => void>();
  let exit: { code: number | null } | undefined;
  const exited = new Promise<number | null>((resolve) => {
    child.on("exit", (code) => {
      exit = { code };
      for (const wake of waiters) wake();
      resolve(code);
    });
  });

  function onData(chunk: Buffer, buffer: { rest: string }): void {
    buffer.rest += chunk.toString("utf8");
    const parts = buffer.rest.split("\n");
    buffer.rest = parts.pop() ?? "";
    for (const part of parts) {
      if (part.trim() === "") continue;
      try {
        lines.push(JSON.parse(part) as LogLine);
      } catch {
        // Not the logger's JSON (a stack trace printed by a library): kept as a message of its own.
        lines.push({ time: new Date().toISOString(), level: "raw", message: part });
      }
    }
    for (const wake of waiters) wake();
  }
  const out = { rest: "" };
  const err = { rest: "" };
  child.stdout?.on("data", (chunk: Buffer) => onData(chunk, out));
  child.stderr?.on("data", (chunk: Buffer) => onData(chunk, err));

  function waitFor(message: string, timeoutMs = 20_000): Promise<LogLine> {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => done(new Error(`no "${message}" within ${timeoutMs} ms; lines: ${describe()}`)), timeoutMs);
      function check(): void {
        const line = lines.find((l) => l.message === message);
        if (line !== undefined) return done(undefined, line);
        if (exit !== undefined) done(new Error(`indexer exited with ${exit.code} before "${message}"; lines: ${describe()}`));
      }
      function done(error: Error | undefined, line?: LogLine): void {
        clearTimeout(timer);
        waiters.delete(check);
        if (error !== undefined) reject(error);
        else resolve(line as LogLine);
      }
      waiters.add(check);
      check();
    });
  }

  async function stop(signal: NodeJS.Signals = "SIGINT", timeoutMs = 20_000): Promise<number | null> {
    if (exit !== undefined) return exit.code;
    child.kill(signal);
    let timer: NodeJS.Timeout | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error(`indexer still running ${timeoutMs} ms after ${signal}; lines: ${describe()}`)), timeoutMs);
    });
    try {
      return await Promise.race([exited, timeout]);
    } finally {
      clearTimeout(timer);
    }
  }

  function describe(): string {
    return lines.map((l) => `${l.level} ${l.message}`).join(" | ");
  }

  return { lines, waitFor, stop };
}
