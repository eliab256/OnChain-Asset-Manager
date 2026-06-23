import type { Address, PublicClient } from "viem";
import type { RouterConfig } from "../types.js";
import { RouterABI, IndexmanagerABI } from "../abis/ContractsABIs.js";
import { erc20Abi } from "viem";

export class RouterValidator {
  private publicClient: PublicClient;
  private routerAddress: Address;
  private indexManagerAddress: Address;
  private usdcAddress: Address;

  constructor(config: RouterConfig) {
    this.publicClient = config.publicClient;
    this.routerAddress = config.routerAddress;
    this.indexManagerAddress = config.indexManagerAddress;
    this.usdcAddress = config.usdcAddress;
  }

  async validateTolerance(tolerance: bigint): Promise<void> {
    const maxTolerance = (await this.publicClient.readContract({
      address: this.routerAddress,
      abi: RouterABI,
      functionName: "getMaxTolerance",
      args: [],
    })) as bigint;

    if (tolerance <= 0n || tolerance >= maxTolerance) {
      throw new Error("Tolerance is invalid.");
    }
  }

  validateAmount(amount: bigint) {
    if (amount <= 0n) {
      throw new Error("Amount must be greater than zero.");
    }
  }

  async validateBalance(
    callerAddress: Address,
    amount: bigint,
    tokenAddress: Address,
  ): Promise<void> {
    const balance = await this.publicClient.readContract({
      address: tokenAddress,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [callerAddress],
    });

    if (amount > balance) {
      throw new Error("Not Enough balance to complete this operation.");
    }
  }

  async validateIndexAddress(indexAddress: Address): Promise<void> {
    const isInitialized = (await this.publicClient.readContract({
      address: this.indexManagerAddress,
      abi: IndexmanagerABI,
      functionName: "checkIsIndexInitialized",
      args: [indexAddress],
    })) as boolean;

    if (!isInitialized) {
      throw new Error("This index is not initialized yet.");
    }
  }

  async validateRouterInputs(
    callerAddress: Address,
    indexAddress: Address,
    amount: bigint,
    tolerance: bigint,
    isBuying: boolean,
  ): Promise<void> {
    const tokenAddress = isBuying ? this.usdcAddress : indexAddress;

    const results = await Promise.allSettled([
      Promise.resolve(this.validateAmount(amount)),
      this.validateBalance(callerAddress, amount, tokenAddress),
      this.validateTolerance(tolerance),
      this.validateIndexAddress(indexAddress),
    ]);

    const errors = results
      .filter((r) => r.status === "rejected")
      .map((r) => (r as PromiseRejectedResult).reason);

    if (errors.length > 0) {
      throw new Error(errors.map((e) => e.message).join("; "));
    }
  }
}
