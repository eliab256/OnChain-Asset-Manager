import { fc, test } from "@fast-check/vitest";
import { bytesToHex, decodeFunctionData, encodeFunctionData, erc20Abi, getAddress, maxUint256 } from "viem";
import { describe, expect, it } from "vitest";
import { permitTokenAbi } from "../abis/fragments.js";
import { SdkError, ValueOutOfRangeError } from "../errors.js";
import { Erc20Manager } from "./Erc20Manager.js";

const USDC = getAddress("0x5FbDB2315678afecb367f032d93F642f64180aa3");
const INDEX = getAddress("0x2d2DF19A06b90e886EDcf42f0D9bB0147076084d");
const ROUTER = getAddress("0x53839913417ebc7171723489F29B9B54F49b4EEA");
const USER = getAddress("0x70997970C51812dc3A010C7d01b50e0d17dc79C8");

const address = fc.uint8Array({ minLength: 20, maxLength: 20 }).map((bytes) => getAddress(bytesToHex(bytes)));
const uint256 = fc.bigInt({ min: 0n, max: 2n ** 256n - 1n });

describe("approveCallParameters", () => {
  it("calls approve(spender, amount) on the token with no value", () => {
    const call = Erc20Manager.approveCallParameters({ token: USDC, spender: INDEX, amount: 100_000_000n });
    expect(call.to).toBe(USDC);
    expect(call.value).toBe(0n);
    expect(decodeFunctionData({ abi: erc20Abi, data: call.calldata })).toEqual({
      functionName: "approve",
      args: [INDEX, 100_000_000n],
    });
  });

  // The Index pulls the USDC in mintShares; an approve to the Router would leave the buy reverting
  // with ERC20InsufficientAllowance. The builder must encode exactly the spender it was given.
  it("security: the spender in the calldata is the one passed (Index), never the token or another address", () => {
    const call = Erc20Manager.approveCallParameters({ token: USDC, spender: INDEX, amount: 1n });
    const [spender] = decodeFunctionData({ abi: erc20Abi, data: call.calldata }).args as readonly [string, bigint];
    expect(spender).toBe(INDEX);
    expect(spender).not.toBe(ROUTER);
    expect(call.to).not.toBe(INDEX);
  });

  it("an amount of 0 encodes a revoke", () => {
    const call = Erc20Manager.approveCallParameters({ token: USDC, spender: INDEX, amount: 0n });
    expect(decodeFunctionData({ abi: erc20Abi, data: call.calldata }).args).toEqual([INDEX, 0n]);
  });

  it("an amount of maxUint256 (unlimited approval) is encoded", () => {
    const call = Erc20Manager.approveCallParameters({ token: USDC, spender: INDEX, amount: maxUint256 });
    expect(decodeFunctionData({ abi: erc20Abi, data: call.calldata }).args).toEqual([INDEX, maxUint256]);
  });

  // Without the bound viem throws IntegerOutOfRangeError, which is not an SdkError.
  it.each([-1n, -(2n ** 255n), maxUint256 + 1n, 2n ** 300n])("security: amount %s outside uint256 -> ValueOutOfRangeError", (amount) => {
    let thrown: unknown;
    try {
      Erc20Manager.approveCallParameters({ token: USDC, spender: INDEX, amount });
    } catch (err) {
      thrown = err;
    }
    expect(thrown).toBeInstanceOf(ValueOutOfRangeError);
    expect(thrown).toBeInstanceOf(SdkError);
    expect(thrown).toMatchObject({ operation: "approve", field: "amount", value: amount, max: maxUint256 });
  });

  test.prop([address, address, uint256], { numRuns: 200 })("decoded calldata equals the inputs", (token, spender, amount) => {
    const call = Erc20Manager.approveCallParameters({ token, spender, amount });
    expect(call.to).toBe(token);
    expect(decodeFunctionData({ abi: erc20Abi, data: call.calldata }).args).toEqual([spender, amount]);
  });
});

describe("read descriptors", () => {
  it("balanceOfRead(owner)", () => {
    expect(Erc20Manager.balanceOfRead({ token: USDC, owner: USER })).toEqual({
      address: USDC,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [USER],
    });
  });

  // allowance(owner, spender): swapping them would read the Index's allowance to the user.
  it("security: allowanceRead keeps the (owner, spender) order", () => {
    expect(Erc20Manager.allowanceRead({ token: USDC, owner: USER, spender: INDEX })).toEqual({
      address: USDC,
      abi: erc20Abi,
      functionName: "allowance",
      args: [USER, INDEX],
    });
  });

  it("noncesRead, eip712DomainRead and versionRead use the permit fragments", () => {
    expect(Erc20Manager.noncesRead({ token: USDC, owner: USER })).toEqual({
      address: USDC,
      abi: permitTokenAbi,
      functionName: "nonces",
      args: [USER],
    });
    expect(Erc20Manager.eip712DomainRead(USDC)).toEqual({ address: USDC, abi: permitTokenAbi, functionName: "eip712Domain" });
    expect(Erc20Manager.versionRead(USDC)).toEqual({ address: USDC, abi: permitTokenAbi, functionName: "version" });
  });

  it("nameRead uses the ERC20 ABI", () => {
    expect(Erc20Manager.nameRead(USDC)).toEqual({ address: USDC, abi: erc20Abi, functionName: "name" });
  });

  it("every descriptor encodes", () => {
    const reads = [
      Erc20Manager.balanceOfRead({ token: USDC, owner: USER }),
      Erc20Manager.allowanceRead({ token: USDC, owner: USER, spender: INDEX }),
      Erc20Manager.noncesRead({ token: USDC, owner: USER }),
      Erc20Manager.eip712DomainRead(USDC),
      Erc20Manager.nameRead(USDC),
      Erc20Manager.versionRead(USDC),
    ];
    for (const read of reads) expect(() => encodeFunctionData(read as Parameters<typeof encodeFunctionData>[0])).not.toThrow();
  });
});
