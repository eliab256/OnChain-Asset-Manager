import { describe, expect, it, vi } from "vitest";
import { errorFields, errorMessage, logger } from "./logger.js";

describe("errorMessage", () => {
  it("uses the message of an Error", () => {
    expect(errorMessage(new Error("boom"))).toBe("boom");
  });

  it("describes an event-like object without message (WebSocket ErrorEvent)", () => {
    class ErrorEvent {
      readonly type = "error";
    }
    expect(errorMessage(new ErrorEvent())).toBe("ErrorEvent: error");
  });

  it("does not throw on an object without prototype", () => {
    const bare = Object.create(null) as { type?: string };
    bare.type = "error";

    expect(errorMessage(bare)).toBe("Object: error");
  });

  it("falls back to String() for primitives", () => {
    expect(errorMessage("plain")).toBe("plain");
    expect(errorMessage(undefined)).toBe("undefined");
  });
});

describe("logger.redact", () => {
  it("masks a registered secret in every line, including error messages", async () => {
    const { logger } = await import("./logger.js");
    const { vi } = await import("vitest");
    const lines: string[] = [];
    const spy = vi.spyOn(console, "error").mockImplementation((line: string) => lines.push(line));

    logger.redact(["/v2/SuperSecretKey123456"]);
    logger.error("indexer stopped", { error: "URL: https://eth-mainnet.g.alchemy.com/v2/SuperSecretKey123456" });
    spy.mockRestore();

    expect(lines).toHaveLength(1);
    expect(lines[0]).not.toContain("SuperSecretKey123456");
    expect(lines[0]).toContain("https://eth-mainnet.g.alchemy.com***");
  });

  it("ignores values too short to be real secrets (local password 'oam')", async () => {
    const { logger } = await import("./logger.js");
    const { vi } = await import("vitest");
    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((line: string) => lines.push(line));

    logger.redact(["oam"]);
    logger.info("loaded @oam/abi");
    spy.mockRestore();

    expect(lines[0]).toContain("@oam/abi");
  });
});

describe("errorFields", () => {
  it("adds the stack of an Error", () => {
    const fields = errorFields(new Error("boom"));

    expect(fields.error).toBe("boom");
    expect(String(fields.stack)).toContain("logger.test.ts");
  });

  it("has no stack for a value that is not an Error", () => {
    expect(errorFields("plain")).toEqual({ error: "plain" });
  });
});

describe("log line", () => {
  it("keeps time, level and message first and not overwritable by fields", () => {
    const lines: string[] = [];
    const spy = vi.spyOn(console, "log").mockImplementation((line: string) => lines.push(line));

    logger.info("hello", { level: "debug", message: "other", block: 5n });
    spy.mockRestore();

    const parsed = JSON.parse(lines[0] ?? "{}") as Record<string, unknown>;
    expect(Object.keys(parsed)).toEqual(["time", "level", "message", "block"]);
    expect(parsed.level).toBe("info");
    expect(parsed.message).toBe("hello");
    expect(parsed.block).toBe("5");
  });
});
