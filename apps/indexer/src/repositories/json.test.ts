import { describe, expect, it } from "vitest";
import { NotJsonError, toJsonArgs } from "./json.js";

describe("toJsonArgs", () => {
  it("turns bigint into decimal strings, also above 2^53 and below zero", () => {
    expect(toJsonArgs({ value: 2n ** 255n, delta: -42n })).toEqual({
      value: "57896044618658097711785492504343953926634992332820282019728792003956564819968",
      delta: "-42",
    });
  });

  it("keeps strings, booleans and finite numbers as they are", () => {
    expect(toJsonArgs({ owner: "0xabc", ok: true, logIndex: 3 })).toEqual({ owner: "0xabc", ok: true, logIndex: 3 });
  });

  it("converts arrays, positional args and nested tuples recursively", () => {
    expect(toJsonArgs([1n, ["0xa", 2n], { inner: [3n] }])).toEqual(["1", ["0xa", "2"], { inner: ["3"] }]);
  });

  it("drops undefined properties", () => {
    expect(toJsonArgs({ a: 1n, b: undefined })).toEqual({ a: "1" });
  });

  it("returns a value that survives JSON.stringify unchanged", () => {
    const json = toJsonArgs({ amounts: [1n, 2n], to: "0xdef" });
    expect(JSON.parse(JSON.stringify(json))).toEqual(json);
  });

  it.each([
    ["null", { a: null }, "args.a"],
    ["a function", { a: () => 1 }, "args.a"],
    ["a symbol", [Symbol("x")], "args[0]"],
    ["NaN", { a: { b: Number.NaN } }, "args.a.b"],
    ["a class instance", { a: new Date(0) }, "args.a"],
  ])("throws on %s, naming its path", (_label, args, path) => {
    expect(() => toJsonArgs(args)).toThrow(NotJsonError);
    expect(() => toJsonArgs(args)).toThrow(path);
  });
});
