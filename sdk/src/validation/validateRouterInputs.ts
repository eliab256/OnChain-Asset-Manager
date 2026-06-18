import type { Address, PublicClient } from "viem";
import type { RouterConfig } from "../types.js";

class RouterValidator {
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
  async validateTolerance(tolerance: bigint): Promise<void> {}

  validateAmount(amount: bigint) {
    if (amount <= 0n) {
      throw new Error("Amount must be greater than zero");
    }
  }

  async validateBalance(
    callerAddress: Address,
    amount: bigint,
    tokenAddress: Address,
  ): Promise<void> {}

  async validateIndexAddress(indexAddress: Address): Promise<void> {}

  private async validateRouterInputs(
    config: RouterConfig,
    callerAddress: Address,
    indexAddress: Address,
    amount: bigint,
    tolerance: bigint,
    isBuying: boolean,
  ): Promise<void> {}
}

async function validateRouterInputs(
  config: RouterConfig,
  callerAddress: Address,
  indexAddress: Address,
  amount: bigint,
  tolerance: bigint,
  isBuying: boolean,
): Promise<void> {}

async function validateTolerance(
  routerAddress: Address,
  tolerance: bigint,
): Promise<void> {}

function validateAmount(amount: BigInt) {}

async function validateBalance(
  routerAddress: Address,
  callerAddress: Address,
  amount: bigint,
  tokenAddress: Address,
): Promise<void> {}

async function validateIndexAddress(
  indexAddress: Address,
  indexManagerAddress: Address,
): Promise<void> {}
