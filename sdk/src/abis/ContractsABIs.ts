import IndexJson from "../../../out/Index.sol/Index.json" with { type: "json" };
import IndexmanagerJson from "../../../out/IndexManager.sol/IndexManager.json" with { type: "json" };
import RouterJson from "../../../out/Router.sol/Router.json" with { type: "json" };
import SwapManagerJson from "../../../out/SwapManager.sol/SwapManager.json" with { type: "json" };
import MultiSigWalletJson from "../../../out/MultiSigWallet.sol/MultiSigWallet.json" with { type: "json" };
import type { Abi } from "viem";

export const IndexABI = IndexJson.abi as Abi;
export const IndexmanagerABI = IndexmanagerJson.abi as Abi;
export const RouterABI = RouterJson.abi as Abi;
export const SwapManagerABI = SwapManagerJson.abi as Abi;
export const MultiSigWalletABI = MultiSigWalletJson.abi as Abi;
