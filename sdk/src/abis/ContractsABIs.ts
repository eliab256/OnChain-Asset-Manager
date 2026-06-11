import IndexJson from "../../../out/Index.sol/Index.json" with { type: "json" };
import IndexmanagerJson from "../../../out/IndexManager.sol/IndexManager.json" with { type: "json" };
import RouterJson from "../../../out/Router.sol/Router.json" with { type: "json" };
import SwapManagerJson from "../../../out/SwapManager.sol/SwapManager.json" with { type: "json" };
import MultiSigWalletJson from "../../../out/MultiSigWallet.sol/MultiSigWallet.json" with { type: "json" };

export const IndexABI = IndexJson.abi;
export const IndexmanagerABI = IndexmanagerJson.abi;
export const RouterABI = RouterJson.abi;
export const SwapManagerABI = SwapManagerJson.abi;
export const MultiSigWalletABI = MultiSigWalletJson.abi;
