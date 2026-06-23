import type { Address, PublicClient, WalletClient, Hash } from "viem";
import type { IndexConfig } from "../../types.js";
import { IndexABI } from "../../abis/ContractsABIs.js";

// ── Return types ──────────────────────────────────────────────────────────────

export interface AssetsUsdValue {
  asset0UsdValue: bigint; // 18-decimal standard
  asset1UsdValue: bigint; // 18-decimal standard
  totalUsdValue: bigint; // 18-decimal standard
}

export interface AssetsWeights {
  weight0: bigint; // e.g. 600_000n = 60.00% (4 decimal places, MAX = 1_000_000)
  weight1: bigint;
}

export interface AssetsPendingWeights {
  pendingWeight0: bigint;
  pendingWeight1: bigint;
  executableAt: bigint; // unix timestamp (seconds)
}

export interface AssetsEffectiveWeights {
  effectiveWeight0: bigint;
  effectiveWeight1: bigint;
}

export interface AssetsReserves {
  reserve0: bigint; // token decimals of asset0
  reserve1: bigint; // token decimals of asset1
}

export interface AssetsReservesStd {
  reserve0Std: bigint; // 18-decimal standard
  reserve1Std: bigint; // 18-decimal standard
}

export interface AssetsAndUsdcDecimals {
  asset0Decimals: number;
  asset1Decimals: number;
  usdcDecimals: number;
}

export interface FeesInfo {
  feePercentage: number; // basis points with 4 dec precision, e.g. 10_000 = 1%
  totalFees: bigint; // accumulated fees in USDC token decimals
}

// ── indexSDK class ──────────────────────────────────────────────────────────────

export class IndexSDK {
  private publicClient: PublicClient;
  private indexAddress: Address;

  constructor(config: IndexConfig) {
    this.publicClient = config.publicClient;
    this.indexAddress = config.indexAddress;
  }

  async minMintPreview(
    usdcAmount: bigint,
    maxTolerance: bigint,
  ): Promise<bigint> {
    const minMint = (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "minMintPreview",
      args: [usdcAmount, maxTolerance],
    })) as bigint;

    return minMint;
  }

  async getRedeemPreview(
    sharesAmount: bigint,
    maxTolerance: bigint,
  ): Promise<bigint> {
    const minRedeem = (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "minRedeemPreview",
      args: [sharesAmount, maxTolerance],
    })) as bigint;

    return minRedeem;
  }

  async getLatestPrice(asset: Address): Promise<bigint> {
    return (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getLatestPrice",
      args: [asset],
    })) as bigint;
  }

  async getAssetsUsdValue(): Promise<AssetsUsdValue> {
    const [asset0UsdValue, asset1UsdValue, totalUsdValue] =
      (await this.publicClient.readContract({
        address: this.indexAddress,
        abi: IndexABI,
        functionName: "getAssetsUsdValue",
      })) as [bigint, bigint, bigint];

    return { asset0UsdValue, asset1UsdValue, totalUsdValue };
  }

  async getAssetsWeights(): Promise<AssetsWeights> {
    const [weight0, weight1] = (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getAssetsWeights",
    })) as [bigint, bigint];

    return { weight0, weight1 };
  }

  async getAssetsPendingWeights(): Promise<AssetsPendingWeights> {
    const [pendingWeight0, pendingWeight1, executableAt] =
      (await this.publicClient.readContract({
        address: this.indexAddress,
        abi: IndexABI,
        functionName: "getAssetsPendingWeights",
      })) as [bigint, bigint, bigint];

    return { pendingWeight0, pendingWeight1, executableAt };
  }

  async getAssetsEffectiveWeights(): Promise<AssetsEffectiveWeights> {
    const [effectiveWeight0, effectiveWeight1] =
      (await this.publicClient.readContract({
        address: this.indexAddress,
        abi: IndexABI,
        functionName: "getAssetsEffectiveWeights",
      })) as [bigint, bigint];

    return { effectiveWeight0, effectiveWeight1 };
  }

  async getAssetsReserves(): Promise<AssetsReserves> {
    const [reserve0, reserve1] = (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getAssetsReserves",
    })) as [bigint, bigint];

    return { reserve0, reserve1 };
  }

  async getAssetsReservesStdDecimals(): Promise<AssetsReservesStd> {
    const [reserve0Std, reserve1Std] = (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getAssetsReservesStdDecimals",
    })) as [bigint, bigint];

    return { reserve0Std, reserve1Std };
  }

  async getAsset0(): Promise<Address> {
    return (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getAsset0",
    })) as Address;
  }

  async getAsset1(): Promise<Address> {
    return (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getAsset1",
    })) as Address;
  }

  async getUsdc(): Promise<Address> {
    return (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getUsdc",
    })) as Address;
  }

  async getAsset0PriceFeed(): Promise<Address> {
    return (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getAsset0PriceFeed",
    })) as Address;
  }

  async getAsset1PriceFeed(): Promise<Address> {
    return (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getAsset1PriceFeed",
    })) as Address;
  }

  async getUsdcPriceFeed(): Promise<Address> {
    return (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getUsdcPriceFeed",
    })) as Address;
  }

  async getAssetsAndUsdcDecimals(): Promise<AssetsAndUsdcDecimals> {
    const [asset0Decimals, asset1Decimals, usdcDecimals] =
      (await this.publicClient.readContract({
        address: this.indexAddress,
        abi: IndexABI,
        functionName: "getAssetsAndUsdcDecimals",
      })) as [number, number, number];

    return { asset0Decimals, asset1Decimals, usdcDecimals };
  }

  async getFeesInfo(): Promise<FeesInfo> {
    const [feePercentage, totalFees] = (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getFeesInfo",
    })) as [number, bigint];

    return { feePercentage, totalFees };
  }

  async getInitializationStatus(): Promise<boolean> {
    return (await this.publicClient.readContract({
      address: this.indexAddress,
      abi: IndexABI,
      functionName: "getInitializationStatus",
    })) as boolean;
  }
}
