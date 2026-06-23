import type { Address, PublicClient, WalletClient, Hash } from "viem";
import type { RouterConfig } from "../../types.js";
import { RouterValidator } from "../../validation/validateRouterInputs.js";
import { RouterABI, IndexmanagerABI } from "../../abis/ContractsABIs.js";
import { erc20Abi } from "viem";

export class RouterSDK {
  private publicClient: PublicClient;
  private walletClient: WalletClient;
  private routerAddress: Address;
  private routerValidator: RouterValidator;
  private usdcAddress: Address;

  constructor(config: RouterConfig) {
    this.publicClient = config.publicClient;
    this.walletClient = config.walletClient;
    this.routerAddress = config.routerAddress;
    this.routerValidator = new RouterValidator(config);
    this.usdcAddress = config.usdcAddress;
  }

  async getMintPreview(
    indexAddress: Address,
    usdcAmount: bigint,
    maxTolerance: bigint,
  ): Promise<bigint> {
    const minMint = (await this.publicClient.readContract({
      address: this.routerAddress,
      abi: RouterABI,
      functionName: "getMinMintPreview",
      args: [indexAddress, usdcAmount, maxTolerance],
    })) as bigint;

    return minMint;
  }

  async getRedeemPreview(
    indexAddress: Address,
    sharesAmount: bigint,
    maxTolerance: bigint,
  ): Promise<bigint> {
    const minRedeem = (await this.publicClient.readContract({
      address: this.routerAddress,
      abi: RouterABI,
      functionName: "getMinRedeemPreview",
      args: [indexAddress, sharesAmount, maxTolerance],
    })) as bigint;

    return minRedeem;
  }

  async buyExactAmountOfShareFromMaxUsdcAndApprove(
    callerAddress: Address,
    indexAddress: Address,
    sharesAmount: bigint,
    tolerance: bigint,
  ): Promise<Hash> {
    const oneUsdc = BigInt(1000000);
    const previewResult = await this.getMintPreview(
      indexAddress,
      oneUsdc,
      tolerance,
    );

    const expectedUsdcAmount = (oneUsdc * sharesAmount) / previewResult;

    await this.routerValidator.validateRouterInputs(
      callerAddress,
      indexAddress,
      expectedUsdcAmount,
      tolerance,
      true,
    );

    const approveHash = await this.approve(
      callerAddress,
      indexAddress,
      this.usdcAddress,
      expectedUsdcAmount,
    );
    await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

    let request;
    let result;
    try {
      const simulation = await this.publicClient.simulateContract({
        address: this.routerAddress,
        abi: RouterABI,
        functionName: "buyExactUsdcAmountOfShares",
        args: [indexAddress, expectedUsdcAmount, tolerance], // 1 usdc
        account: callerAddress,
      });

      request = simulation.request;
      result = simulation.result;
    } catch (error) {
      throw new Error("Buy simulation failed", { cause: error });
    }

    if (result != sharesAmount) {
      throw new Error(
        "Buy simulation result is not equal to expected shares amount",
      );
    }

    const hash = await this.walletClient.writeContract(request);
    return hash;
  }

  async buyExactAmountOfShareFromMaxUsdc(
    callerAddress: Address,
    indexAddress: Address,
    sharesAmount: bigint,
    tolerance: bigint,
  ): Promise<Hash> {
    const oneUsdc = BigInt(1000000);
    const previewResult = await this.getMintPreview(
      indexAddress,
      oneUsdc,
      tolerance,
    );

    const expectedUsdcAmount = (oneUsdc * sharesAmount) / previewResult;

    await this.routerValidator.validateRouterInputs(
      callerAddress,
      indexAddress,
      expectedUsdcAmount,
      tolerance,
      true,
    );

    let request;
    let result;
    try {
      const simulation = await this.publicClient.simulateContract({
        address: this.routerAddress,
        abi: RouterABI,
        functionName: "buyExactUsdcAmountOfShares",
        args: [indexAddress, expectedUsdcAmount, tolerance], // 1 usdc
        account: callerAddress,
      });

      request = simulation.request;
      result = simulation.result;
    } catch (error) {
      throw new Error("Buy simulation failed", { cause: error });
    }

    if (result != sharesAmount) {
      throw new Error(
        "Buy simulation result is not equal to expected shares amount",
      );
    }

    const hash = await this.walletClient.writeContract(request);
    return hash;
  }

  async buyExactUsdcAmountOfSharesAndApprove(
    callerAddress: Address,
    indexAddress: Address,
    usdcAmount: bigint,
    tolerance: bigint,
  ): Promise<Hash> {
    await this.routerValidator.validateRouterInputs(
      callerAddress,
      indexAddress,
      usdcAmount,
      tolerance,
      true,
    );

    const approveHash = await this.approve(
      callerAddress,
      indexAddress,
      this.usdcAddress,
      usdcAmount,
    );
    await this.publicClient.waitForTransactionReceipt({ hash: approveHash });

    let request;
    try {
      const simulation = await this.publicClient.simulateContract({
        address: this.routerAddress,
        abi: RouterABI,
        functionName: "buyExactUsdcAmountOfShares",
        args: [indexAddress, usdcAmount, tolerance],
        account: callerAddress,
      });
      request = simulation.request;
    } catch (error) {
      throw new Error("Buy simulation failed", { cause: error });
    }

    const hash = await this.walletClient.writeContract(request);
    return hash;
  }

  async buyExactUsdcAmountOfShares(
    callerAddress: Address,
    indexAddress: Address,
    usdcAmount: bigint,
    tolerance: bigint,
  ): Promise<Hash> {
    await this.routerValidator.validateRouterInputs(
      callerAddress,
      indexAddress,
      usdcAmount,
      tolerance,
      true,
    );

    let request;
    try {
      const simulation = await this.publicClient.simulateContract({
        address: this.routerAddress,
        abi: RouterABI,
        functionName: "buyExactUsdcAmountOfShares",
        args: [indexAddress, usdcAmount, tolerance],
        account: callerAddress,
      });
      request = simulation.request;
    } catch (error) {
      throw new Error("Buy simulation failed", { cause: error });
    }

    const hash = await this.walletClient.writeContract(request);
    return hash;
  }

  async sellExactAmountOfSharesForUsdc(
    callerAddress: Address,
    indexAddress: Address,
    sharesAmount: bigint,
    tolerance: bigint,
  ): Promise<Hash> {
    await this.routerValidator.validateRouterInputs(
      callerAddress,
      indexAddress,
      sharesAmount,
      tolerance,
      false,
    );

    let request;
    try {
      const simulation = await this.publicClient.simulateContract({
        address: this.routerAddress,
        abi: RouterABI,
        functionName: "sellExactAmountOfSharesForUsdc",
        args: [indexAddress, sharesAmount, tolerance],
        account: callerAddress,
      });
      request = simulation.request;
    } catch (error) {
      throw new Error("Sell simulation failed", { cause: error });
    }

    const hash = await this.walletClient.writeContract(request);
    return hash;
  }

  async sellMaxSharesForExactAmountOfUsdc(
    callerAddress: Address,
    indexAddress: Address,
    usdcAmount: bigint,
    tolerance: bigint,
  ): Promise<Hash> {
    const oneShare = BigInt(1e18);
    const previewResult = await this.getRedeemPreview(
      indexAddress,
      oneShare,
      tolerance,
    );

    const expectedSharesAmount = (oneShare * usdcAmount) / previewResult;

    await this.routerValidator.validateRouterInputs(
      callerAddress,
      indexAddress,
      expectedSharesAmount,
      tolerance,
      false,
    );

    let request;
    let result;
    try {
      const simulation = await this.publicClient.simulateContract({
        address: this.routerAddress,
        abi: RouterABI,
        functionName: "sellExactAmountOfSharesForUsdc",
        args: [indexAddress, expectedSharesAmount, tolerance],
        account: callerAddress,
      });
      request = simulation.request;
      result = simulation.result;
    } catch (error) {
      throw new Error("Sell simulation failed", { cause: error });
    }

    if (result != usdcAmount) {
      throw new Error(
        "Buy simulation result is not equal to expected shares amount",
      );
    }

    const hash = await this.walletClient.writeContract(request);
    return hash;
  }

  async buyWithPermit(
    callerAddress: Address,
    indexAddress: Address,
    usdcAmount: bigint,
    tolerance: bigint,
    deadline: bigint,
  ): Promise<Hash> {
    return "0x" as Hash;
  }

  async approve(
    callerAddress: Address,
    approved: Address,
    token: Address,
    amount: bigint,
  ): Promise<Hash> {
    const approveHash = await this.walletClient.writeContract({
      address: token,
      abi: erc20Abi,
      functionName: "approve",
      args: [approved, amount],
      account: callerAddress,
      chain: this.walletClient.chain,
    });

    return approveHash;
  }
}
