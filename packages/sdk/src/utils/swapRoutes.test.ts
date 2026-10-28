import { fc, test } from "@fast-check/vitest";
import { bytesToHex, concat, getAddress, numberToHex, size, slice, zeroAddress, type Address, type Hex } from "viem";
import { describe, expect, it } from "vitest";
import { InvalidSwapRouteError } from "../errors.js";
import { assertRouteConnects, POOL_VERSION, routeEndpoints, v3Route, v4Route, type PoolKey, type SwapRoute } from "./swapRoutes.js";

const WBTC = getAddress("0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599");
const WETH = getAddress("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
const USDC = getAddress("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
const LINK = getAddress("0x514910771AF9Ca656af840dff83E8264EcF986CA");

const MAX_UINT24 = 2 ** 24 - 1;

// Zero is excluded: v3Route rejects it (an ERC20 path never holds address(0)).
const token = fc
  .uint8Array({ minLength: 20, maxLength: 20 })
  .map((bytes) => getAddress(bytesToHex(bytes)))
  .filter((address) => address !== zeroAddress);
const fee = fc.integer({ min: 0, max: MAX_UINT24 });
const path = fc.integer({ min: 1, max: 4 }).chain((hops) =>
  fc.tuple(fc.array(token, { minLength: hops + 1, maxLength: hops + 1 }), fc.array(fee, { minLength: hops, maxLength: hops })),
);

/** The packed V3 path built by hand: token (20 bytes), then fee (3 bytes) + token (20 bytes) per hop. */
function packedPath(tokens: readonly Address[], fees: readonly number[]): Hex {
  const parts: Hex[] = [tokens[0] as Address];
  fees.forEach((f, i) => parts.push(numberToHex(f, { size: 3 }), tokens[i + 1] as Address));
  return concat(parts);
}

const v3 = (v3Path: Hex): SwapRoute => ({
  version: POOL_VERSION.V3,
  poolKey: { currency0: zeroAddress, currency1: zeroAddress, fee: 0, tickSpacing: 0, hooks: zeroAddress },
  v3Path,
});

const poolKey: PoolKey = { currency0: WBTC, currency1: WETH, fee: 3000, tickSpacing: 60, hooks: zeroAddress };

describe("POOL_VERSION", () => {
  it("follows enum PoolVersion in src/types.sol (V3 = 0, V4 = 1)", () => {
    expect(POOL_VERSION).toEqual({ V3: 0, V4: 1 });
  });
});

describe("v3Route", () => {
  it("packs token, uint24 fee, token as abi.encodePacked does", () => {
    const route = v3Route([WBTC, WETH, USDC], [3000, 500]);
    expect(route.version).toBe(POOL_VERSION.V3);
    expect(route.v3Path.toLowerCase()).toBe(packedPath([WBTC, WETH, USDC], [3000, 500]).toLowerCase());
    expect(size(route.v3Path)).toBe(20 + 2 * 23);
  });

  test.prop([path], { numRuns: 200 })("routeEndpoints returns the first and last token of the path", ([tokens, fees]) => {
    const route = v3Route(tokens, fees);
    expect(size(route.v3Path)).toBe(20 + fees.length * 23);
    expect(route.v3Path.toLowerCase()).toBe(packedPath(tokens, fees).toLowerCase());
    expect(routeEndpoints(route)).toEqual([tokens[0], tokens[tokens.length - 1]]);
  });

  it.each([
    ["one token", [WBTC], []],
    ["no tokens", [], []],
    ["one fee too few", [WBTC, WETH, USDC], [3000]],
    ["one fee too many", [WBTC, WETH], [3000, 500]],
    ["a negative fee", [WBTC, WETH], [-1]],
    ["a fee above uint24", [WBTC, WETH], [MAX_UINT24 + 1]],
    ["a fractional fee", [WBTC, WETH], [0.5]],
    ["a zero-address token", [WBTC, zeroAddress], [3000]],
    ["a malformed address", [WBTC, "0x1234" as Address], [3000]],
  ] as const)("rejects %s with InvalidSwapRouteError", (_name, tokens, fees) => {
    expect(() => v3Route(tokens, fees)).toThrow(InvalidSwapRouteError);
  });

  it.each([0, MAX_UINT24])("accepts the uint24 bound %s", (f) => {
    expect(() => v3Route([WBTC, WETH], [f])).not.toThrow();
  });

  it("does not mutate its inputs", () => {
    const tokens = Object.freeze([WBTC, WETH]);
    const fees = Object.freeze([3000]);
    v3Route(tokens, fees);
    expect(tokens).toEqual([WBTC, WETH]);
    expect(fees).toEqual([3000]);
  });
});

describe("v4Route", () => {
  it("keeps the pool key, an empty V3 path and version V4", () => {
    const route = v4Route(poolKey);
    expect(route).toEqual({ version: POOL_VERSION.V4, poolKey, v3Path: "0x" });
    expect(route.poolKey).not.toBe(poolKey);
    expect(routeEndpoints(route)).toEqual([WBTC, WETH]);
  });

  it("accepts native ETH as currency0 (address(0) sorts first), as Uniswap V4 does", () => {
    expect(routeEndpoints(v4Route({ ...poolKey, currency0: zeroAddress }))).toEqual([zeroAddress, WETH]);
  });

  it.each([
    ["unsorted currencies", { ...poolKey, currency0: WETH, currency1: WBTC }],
    ["equal currencies", { ...poolKey, currency1: WBTC }],
    ["both currencies zero", { ...poolKey, currency0: zeroAddress, currency1: zeroAddress }],
    ["a fee above uint24", { ...poolKey, fee: MAX_UINT24 + 1 }],
    ["a negative fee", { ...poolKey, fee: -1 }],
    ["a tickSpacing above int24", { ...poolKey, tickSpacing: 2 ** 23 }],
    ["a tickSpacing below int24", { ...poolKey, tickSpacing: -(2 ** 23) - 1 }],
    ["a fractional tickSpacing", { ...poolKey, tickSpacing: 1.5 }],
    ["a malformed hooks address", { ...poolKey, hooks: "0xdead" as Address }],
  ])("rejects %s with InvalidSwapRouteError", (_name, key) => {
    expect(() => v4Route(key)).toThrow(InvalidSwapRouteError);
  });

  it.each([2 ** 23 - 1, -(2 ** 23)])("accepts the int24 bound %s for tickSpacing", (tickSpacing) => {
    expect(() => v4Route({ ...poolKey, tickSpacing })).not.toThrow();
  });
});

// Mirrors SwapManager._validateRoute: path.length < 43 || (path.length - 20) % 23 != 0 reverts.
describe("routeEndpoints on hand-built routes", () => {
  const valid = packedPath([WBTC, USDC], [3000]);

  it.each([
    ["empty", "0x"],
    ["20 bytes (a token, no hop)", WBTC],
    ["42 bytes", slice(valid, 0, 42)],
    ["44 bytes", concat([valid, "0x00"])],
    ["43 + 22 bytes", concat([valid, slice(valid, 0, 22)])],
    ["not hex", "0xzz" as Hex],
  ] as const)("V3 path %s -> InvalidSwapRouteError", (_name, v3Path) => {
    expect(() => routeEndpoints(v3(v3Path))).toThrow(InvalidSwapRouteError);
  });

  test.prop([fc.integer({ min: 0, max: 200 })], { numRuns: 200 })(
    "a V3 path is accepted exactly when its length is 20 + 23n with n >= 1",
    (length) => {
      const v3Path = bytesToHex(new Uint8Array(length).fill(1));
      const accepted = length >= 43 && (length - 20) % 23 === 0;
      if (accepted) expect(routeEndpoints(v3(v3Path))).toHaveLength(2);
      else expect(() => routeEndpoints(v3(v3Path))).toThrow(InvalidSwapRouteError);
    },
  );

  it("rejects an unknown pool version", () => {
    expect(() => routeEndpoints({ ...v3(valid), version: 2 })).toThrow(InvalidSwapRouteError);
  });

  it("V4 with both currencies zero -> InvalidSwapRouteError (SwapManager__InvalidV4PoolKey)", () => {
    const route: SwapRoute = { version: POOL_VERSION.V4, poolKey: { ...poolKey, currency0: zeroAddress, currency1: zeroAddress }, v3Path: "0x" };
    expect(() => routeEndpoints(route)).toThrow(InvalidSwapRouteError);
  });

  it("V3 endpoints are read from the path even when the pool key holds other tokens", () => {
    const route: SwapRoute = { ...v3(valid), poolKey };
    expect(routeEndpoints(route)).toEqual([WBTC, USDC]);
  });
});

describe("assertRouteConnects", () => {
  it("accepts the pair in either direction, as _validateRoute does", () => {
    expect(() => assertRouteConnects(v3Route([WBTC, USDC], [3000]), WBTC, USDC, "asset0Usdc")).not.toThrow();
    expect(() => assertRouteConnects(v3Route([USDC, WBTC], [3000]), WBTC, USDC, "asset0Usdc")).not.toThrow();
    expect(() => assertRouteConnects(v4Route(poolKey), WETH, WBTC, "asset0Asset1")).not.toThrow();
  });

  it("accepts intermediate hops through other tokens", () => {
    expect(() => assertRouteConnects(v3Route([WBTC, WETH, USDC], [3000, 500]), WBTC, USDC, "asset0Usdc")).not.toThrow();
  });

  it("compares addresses case-insensitively", () => {
    expect(() =>
      assertRouteConnects(v3Route([WBTC, USDC], [3000]), WBTC.toLowerCase() as Address, USDC.toLowerCase() as Address, "r"),
    ).not.toThrow();
  });

  it.each([
    ["a wrong last token", v3Route([WBTC, WETH], [3000]), WBTC, USDC],
    ["a wrong first token", v3Route([LINK, USDC], [3000]), WBTC, USDC],
    ["the right tokens only in the middle", v3Route([LINK, WBTC, USDC, LINK], [3000, 3000, 3000]), WBTC, USDC],
    ["a V4 pool of another pair", v4Route(poolKey), WBTC, USDC],
  ] as const)("rejects %s with InvalidSwapRouteError", (_name, route, a, b) => {
    expect(() => assertRouteConnects(route, a, b, "route")).toThrow(InvalidSwapRouteError);
  });

  test.prop([path, token, token], { numRuns: 200 })(
    "a route connects (a, b) exactly when its endpoints are {a, b} in some order",
    ([tokens, fees], a, b) => {
      const route = v3Route(tokens, fees);
      const first = tokens[0] as Address;
      const last = tokens[tokens.length - 1] as Address;
      expect(() => assertRouteConnects(route, first, last, "r")).not.toThrow();
      expect(() => assertRouteConnects(route, last, first, "r")).not.toThrow();
      const connects = (a === first && b === last) || (a === last && b === first);
      if (connects) expect(() => assertRouteConnects(route, a, b, "r")).not.toThrow();
      else expect(() => assertRouteConnects(route, a, b, "r")).toThrow(InvalidSwapRouteError);
    },
  );
});
