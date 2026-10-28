import {
  encodePacked,
  getAddress,
  isAddress,
  isAddressEqual,
  isHex,
  maxUint24,
  size,
  slice,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import { InvalidSwapRouteError } from "../errors.js";

/** `PoolVersion` in src/types.sol. */
export const POOL_VERSION = { V3: 0, V4: 1 } as const;

/** Uniswap V4 `PoolKey`. `fee` is in hundredths of a basis point (3000 = 0.3%), as in Uniswap. */
export type PoolKey = {
  currency0: Address;
  currency1: Address;
  fee: number;
  tickSpacing: number;
  hooks: Address;
};

/** `SwapRoute` in src/types.sol: `poolKey` is read only for V4, `v3Path` only for V3. */
export type SwapRoute = {
  version: number;
  poolKey: PoolKey;
  v3Path: Hex;
};

const EMPTY_POOL_KEY: PoolKey = { currency0: zeroAddress, currency1: zeroAddress, fee: 0, tickSpacing: 0, hooks: zeroAddress };
const MIN_INT24 = -(2 ** 23);
const MAX_INT24 = 2 ** 23 - 1;
const ADDRESS_BYTES = 20;
const HOP_BYTES = 23;

function assertFee(fee: number, field: string): void {
  if (!Number.isInteger(fee) || fee < 0 || BigInt(fee) > maxUint24) {
    throw new InvalidSwapRouteError(`${field} ${fee} is not a uint24`);
  }
}

function assertAddress(value: Address, field: string): void {
  if (!isAddress(value, { strict: false })) throw new InvalidSwapRouteError(`${field} ${value} is not an address`);
}

/**
 * Uniswap V3 route through `tokens`, one pool per hop: `fees[i]` is the fee tier of the pool between
 * `tokens[i]` and `tokens[i + 1]` (500, 3000, 10000, ...). The path is `abi.encodePacked(token, fee, token, ...)`.
 * @throws {InvalidSwapRouteError}
 */
export function v3Route(tokens: readonly Address[], fees: readonly number[]): SwapRoute {
  if (tokens.length < 2) throw new InvalidSwapRouteError(`a V3 path needs at least 2 tokens, received ${tokens.length}`);
  if (fees.length !== tokens.length - 1) {
    throw new InvalidSwapRouteError(`${tokens.length} tokens need ${tokens.length - 1} fees, received ${fees.length}`);
  }
  tokens.forEach((token, i) => {
    assertAddress(token, `tokens[${i}]`);
    if (isAddressEqual(token, zeroAddress)) throw new InvalidSwapRouteError(`tokens[${i}] is the zero address`);
  });
  fees.forEach((fee, i) => assertFee(fee, `fees[${i}]`));
  const types: ("address" | "uint24")[] = ["address"];
  const values: (Address | number)[] = [tokens[0] as Address];
  for (let i = 0; i < fees.length; i++) {
    types.push("uint24", "address");
    values.push(fees[i] as number, tokens[i + 1] as Address);
  }
  return { version: POOL_VERSION.V3, poolKey: EMPTY_POOL_KEY, v3Path: encodePacked(types, values) };
}

/**
 * Uniswap V4 route through a single pool. `currency0` must be lower than `currency1`, as in every V4 pool key.
 * @throws {InvalidSwapRouteError}
 */
export function v4Route(poolKey: PoolKey): SwapRoute {
  assertAddress(poolKey.currency0, "currency0");
  assertAddress(poolKey.currency1, "currency1");
  assertAddress(poolKey.hooks, "hooks");
  if (BigInt(poolKey.currency0) >= BigInt(poolKey.currency1)) {
    throw new InvalidSwapRouteError(`currency0 ${poolKey.currency0} must be lower than currency1 ${poolKey.currency1}`);
  }
  assertFee(poolKey.fee, "fee");
  if (!Number.isInteger(poolKey.tickSpacing) || poolKey.tickSpacing < MIN_INT24 || poolKey.tickSpacing > MAX_INT24) {
    throw new InvalidSwapRouteError(`tickSpacing ${poolKey.tickSpacing} is not an int24`);
  }
  return { version: POOL_VERSION.V4, poolKey: { ...poolKey }, v3Path: "0x" };
}

/**
 * First and last token of a route, the pair `SwapManager._validateRoute` compares with the Index tokens
 * (in either direction).
 * @throws {InvalidSwapRouteError} unknown version or malformed V3 path
 */
export function routeEndpoints(route: SwapRoute): readonly [Address, Address] {
  if (route.version === POOL_VERSION.V4) {
    if (isAddressEqual(route.poolKey.currency0, zeroAddress) && isAddressEqual(route.poolKey.currency1, zeroAddress)) {
      throw new InvalidSwapRouteError("both V4 currencies are the zero address");
    }
    return [route.poolKey.currency0, route.poolKey.currency1];
  }
  if (route.version !== POOL_VERSION.V3) throw new InvalidSwapRouteError(`unknown pool version ${route.version}`);
  if (!isHex(route.v3Path, { strict: true })) throw new InvalidSwapRouteError("the V3 path is not hex");
  const length = size(route.v3Path);
  if (length < ADDRESS_BYTES + HOP_BYTES || (length - ADDRESS_BYTES) % HOP_BYTES !== 0) {
    throw new InvalidSwapRouteError(`a V3 path of ${length} bytes is not 20 + n * 23 bytes with n >= 1`);
  }
  return [getAddress(slice(route.v3Path, 0, ADDRESS_BYTES)), getAddress(slice(route.v3Path, length - ADDRESS_BYTES, length))];
}

/**
 * Same check as `SwapManager._validateRoute`: the route connects `tokenA` and `tokenB`, in either direction.
 * @throws {InvalidSwapRouteError}
 */
export function assertRouteConnects(route: SwapRoute, tokenA: Address, tokenB: Address, name: string): void {
  const [first, last] = routeEndpoints(route);
  const forward = isAddressEqual(first, tokenA) && isAddressEqual(last, tokenB);
  const backward = isAddressEqual(first, tokenB) && isAddressEqual(last, tokenA);
  if (!forward && !backward) {
    throw new InvalidSwapRouteError(`${name} goes from ${first} to ${last}, expected ${tokenA} and ${tokenB}`);
  }
}
