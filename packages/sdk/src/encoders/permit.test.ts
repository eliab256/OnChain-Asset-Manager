import { fc, test } from "@fast-check/vitest";
import {
  bytesToHex,
  concat,
  encodeAbiParameters,
  getAddress,
  hashTypedData,
  keccak256,
  recoverTypedDataAddress,
  toHex,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { describe, expect, it } from "vitest";
import { InvalidSignatureError, SdkError } from "../errors.js";
import {
  buildPermitTypedData,
  joinPermitSignature,
  PERMIT_TYPES,
  permitDomainFromEip712Domain,
  splitPermitSignature,
  type PermitDomain,
} from "./permit.js";

// Anvil account 0: a well-known test key, signing happens locally in the test.
const account = privateKeyToAccount("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
const USDC = getAddress("0x5FbDB2315678afecb367f032d93F642f64180aa3");
const INDEX = getAddress("0x2d2DF19A06b90e886EDcf42f0D9bB0147076084d");
const ROUTER = getAddress("0x53839913417ebc7171723489F29B9B54F49b4EEA");

const domain: PermitDomain = { name: "USD Coin", version: "1", chainId: 31337, verifyingContract: USDC };

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
const uint256 = fc.bigInt({ min: 0n, max: 2n ** 256n - 1n });
const word = fc.uint8Array({ minLength: 32, maxLength: 32 }).map((bytes) => bytesToHex(bytes));

/** EIP-712 digest of an EIP-2612 permit built by hand from the standard, as ERC20Permit computes it. */
function permitDigest(d: PermitDomain, m: { owner: Hex; spender: Hex; value: bigint; nonce: bigint; deadline: bigint }): Hex {
  const domainTypeHash = keccak256(
    toHex("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
  );
  const domainSeparator = keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "bytes32" }, { type: "bytes32" }, { type: "uint256" }, { type: "address" }],
      [domainTypeHash, keccak256(toHex(d.name)), keccak256(toHex(d.version)), BigInt(d.chainId), d.verifyingContract],
    ),
  );
  const permitTypeHash = keccak256(
    toHex("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
  );
  const structHash = keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "address" }, { type: "address" }, { type: "uint256" }, { type: "uint256" }, { type: "uint256" }],
      [permitTypeHash, m.owner, m.spender, m.value, m.nonce, m.deadline],
    ),
  );
  return keccak256(concat(["0x1901", domainSeparator, structHash]));
}

describe("PERMIT_TYPES", () => {
  it("is the EIP-2612 Permit struct, in order", () => {
    expect(PERMIT_TYPES.Permit.map((field) => `${field.type} ${field.name}`)).toEqual([
      "address owner",
      "address spender",
      "uint256 value",
      "uint256 nonce",
      "uint256 deadline",
    ]);
  });
});

describe("buildPermitTypedData", () => {
  const params = { domain, owner: account.address, spender: INDEX, value: 100_000_000n, nonce: 0n, deadline: 1_900_000_000n };

  it("passes every field through unchanged", () => {
    const typedData = buildPermitTypedData(params);
    expect(typedData.domain).toEqual(domain);
    expect(typedData.types).toBe(PERMIT_TYPES);
    expect(typedData.primaryType).toBe("Permit");
    expect(typedData.message).toEqual({
      owner: params.owner,
      spender: params.spender,
      value: params.value,
      nonce: params.nonce,
      deadline: params.deadline,
    });
  });

  // Router.buyExactUsdcAmountOfSharesWithPermit calls usdc.permit(msg.sender, _indexAddress, ...):
  // a permit signed for any other spender (e.g. the Router) is rejected with ERC2612InvalidSigner.
  it("security: a permit for a Router buy is signed with spender = Index and recovers to the owner", async () => {
    const typedData = buildPermitTypedData(params);
    expect(typedData.message.spender).toBe(INDEX);
    expect(typedData.message.spender).not.toBe(ROUTER);
    const signature = await account.signTypedData(typedData);
    expect(await recoverTypedDataAddress({ ...typedData, signature })).toBe(account.address);
  });

  it("security: a signature for spender = Index does not verify for spender = Router", async () => {
    const signature = await account.signTypedData(buildPermitTypedData(params));
    const forRouter = buildPermitTypedData({ ...params, spender: ROUTER });
    expect(await recoverTypedDataAddress({ ...forRouter, signature })).not.toBe(account.address);
  });

  it("security: the domain binds the chain id and the token", () => {
    const base = hashTypedData(buildPermitTypedData(params));
    expect(hashTypedData(buildPermitTypedData({ ...params, domain: { ...domain, chainId: 1 } }))).not.toBe(base);
    expect(hashTypedData(buildPermitTypedData({ ...params, domain: { ...domain, verifyingContract: INDEX } }))).not.toBe(base);
  });

  test.prop([address, address, uint256, uint256, uint256, fc.integer({ min: 1, max: 2 ** 31 }), address], { numRuns: 200 })(
    "the digest equals the EIP-2612 digest computed from the standard",
    (owner, spender, value, nonce, deadline, chainId, verifyingContract) => {
      const d = { name: "USD Coin", version: "2", chainId, verifyingContract };
      const message = { owner, spender, value, nonce, deadline };
      expect(hashTypedData(buildPermitTypedData({ domain: d, ...message }))).toBe(permitDigest(d, message));
    },
  );
});

describe("permitDomainFromEip712Domain", () => {
  it("maps the ERC-5267 tuple and converts the chain id to a number", () => {
    const result = ["0x0f", "USD Coin", "1", 31338n, USDC, `0x${"00".repeat(32)}`, []] as const;
    expect(permitDomainFromEip712Domain(result)).toEqual({ name: "USD Coin", version: "1", chainId: 31338, verifyingContract: USDC });
  });
});

describe("splitPermitSignature / joinPermitSignature", () => {
  it("splits a real signature into v 27/28, r and s", async () => {
    const signature = await account.signTypedData(
      buildPermitTypedData({ domain, owner: account.address, spender: INDEX, value: 1n, nonce: 0n, deadline: 1n }),
    );
    const split = splitPermitSignature(signature);
    expect([27, 28]).toContain(split.v);
    expect(split.r).toBe(signature.slice(0, 66));
    expect(split.s).toBe(`0x${signature.slice(66, 130)}`);
    expect(joinPermitSignature(split)).toBe(signature);
  });

  // Some wallets (Ledger, some smart accounts) return v as 0/1; ecrecover in the token needs 27/28.
  it.each([
    ["00", 27],
    ["01", 28],
  ] as const)("a trailing v byte 0x%s becomes v = %i", (vByte, v) => {
    const r = `0x${"11".repeat(32)}` as const;
    const s = `0x${"22".repeat(32)}` as const;
    expect(splitPermitSignature(`${r}${"22".repeat(32)}${vByte}`)).toEqual({ v, r, s });
  });

  test.prop([word, word, fc.constantFrom(27, 28)], { numRuns: 200 })("split(join(x)) equals x", (r, s, v) => {
    expect(splitPermitSignature(joinPermitSignature({ v, r, s }))).toEqual({ v, r, s });
  });

  test.prop([word, word, fc.constantFrom("1b", "1c")], { numRuns: 200 })("join(split(sig)) equals sig", (r, s, vByte) => {
    const signature = `${r}${s.slice(2)}${vByte}` as Hex;
    expect(joinPermitSignature(splitPermitSignature(signature))).toBe(signature);
  });

  // A caller branching on `instanceof SdkError` must catch every malformed signature: viem's
  // parseSignature throws a plain Error, and the Router takes v explicitly, so a 64-byte EIP-2098
  // compact signature (returned by some smart-contract wallets) is refused too.
  const r = "11".repeat(32);
  const s = "22".repeat(32);
  it.each([
    ["a non-hex string", "not a signature"],
    ["hex with non-hex characters", `0x${r}${s}zz`],
    ["an empty hex", "0x"],
    ["a 64-byte EIP-2098 compact signature", `0x${r}${s}`],
    ["a 66-byte signature", `0x${r}${s}1b00`],
    ["a v byte of 0x05", `0x${r}${s}05`],
    ["a v byte of 0x1a (26)", `0x${r}${s}1a`],
    ["a v byte of 0x1d (29)", `0x${r}${s}1d`],
  ] as const)("security: rejects %s with InvalidSignatureError", (_label, signature) => {
    let thrown: unknown;
    try {
      splitPermitSignature(signature as Hex);
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(InvalidSignatureError);
    expect(thrown).toBeInstanceOf(SdkError);
    expect(thrown).toMatchObject({ signature });
  });

  it("a v byte viem cannot parse keeps viem's error as cause", () => {
    let thrown: unknown;
    try {
      splitPermitSignature(`0x${r}${s}1d`);
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(InvalidSignatureError);
    expect((thrown as InvalidSignatureError).cause).toBeInstanceOf(Error);
  });
});
