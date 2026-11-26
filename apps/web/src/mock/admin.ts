// Demo data for the admin page: MultiSig proposals, weight proposals, timelock and price feeds.
import { MOCK_NOW } from "./market";
import { MULTISIG_OWNERS } from "./accounts";

const DAY = 86_400_000;
const H = 3_600_000;

export const CONTRACTS = {
  IndexManager: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9",
  PriceFeedManager: "0x9A676e781A523b5d0C0e43731313A708CB607508",
  SwapManager: "0x0B306BF915C4d645ff596e518fAf3F9669b97016",
  Router: "0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1",
  TimelockController: "0x68B1D87F95878fE05B998F19b66F4baba5De1aed",
  MultiSigWallet: "0x3Aa5ebB10DC797CAC828524e59A333d0A371443c",
} as const;

export type ContractName = keyof typeof CONTRACTS;

export interface DecodedArg {
  name: string;
  type: string;
  value: string;
}

export type ProposalStatus = "PENDING" | "READY" | "EXECUTED" | "FAILED";

export interface MultisigProposal {
  id: number;
  target: ContractName;
  fn: string;
  args: DecodedArg[];
  value: string;
  calldata: string;
  digest: string;
  signers: string[];
  status: ProposalStatus;
  createdAt: number;
  /** Decoded revert of the last eth_call simulation, null when it passes. */
  simulationError: string | null;
}

export const MULTISIG_PROPOSALS: MultisigProposal[] = [
  {
    id: 14,
    target: "IndexManager",
    fn: "proposeWeights",
    args: [
      { name: "index", type: "address", value: "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707" },
      { name: "weight0", type: "uint16", value: "5500" },
      { name: "weight1", type: "uint16", value: "4500" },
    ],
    value: "0",
    calldata:
      "0x8f3a1c2e0000000000000000000000005fc8d32690cc91d4c39d9d3abcbd16989f875707000000000000000000000000000000000000000000000000000000000000157c0000000000000000000000000000000000000000000000000000000000001194",
    digest: "0x4e2a91c7d03b58f6a1e09d27c4b83f5e6a10d92c7b3e48f1a05d6c29e7b14a83",
    signers: [MULTISIG_OWNERS[1]],
    status: "PENDING",
    createdAt: MOCK_NOW - 5 * H,
    simulationError: null,
  },
  {
    id: 13,
    target: "TimelockController",
    fn: "schedule",
    args: [
      { name: "target", type: "address", value: CONTRACTS.SwapManager },
      { name: "value", type: "uint256", value: "0" },
      { name: "data", type: "bytes", value: "upgradeToAndCall(0x2279B7A0…ebd6, 0x)" },
      { name: "predecessor", type: "bytes32", value: "0x0000…0000" },
      { name: "salt", type: "bytes32", value: "0x7377…6170" },
      { name: "delay", type: "uint256", value: "172800" },
    ],
    value: "0",
    calldata:
      "0x01d5062a0000000000000000000000000b306bf915c4d645ff596e518faf3f9669b970160000000000000000000000000000000000000000000000000000000000000000",
    digest: "0x9c1f07e3a2b4d58c61f7e09a3d2b14c8e5f60a7d93b2c1e48f05a6d7c3b29e10",
    signers: [MULTISIG_OWNERS[0], MULTISIG_OWNERS[2]],
    status: "READY",
    createdAt: MOCK_NOW - 1 * DAY,
    simulationError: null,
  },
  {
    id: 12,
    target: "IndexManager",
    fn: "executePriceFeedUpdate",
    args: [{ name: "asset", type: "address", value: "0xc00e94Cb662C3520282E6f5717214004A7f26888" }],
    value: "0",
    calldata: "0x5a2c9f1e000000000000000000000000c00e94cb662c3520282e6f5717214004a7f26888",
    digest: "0x2d8b4f61e0a93c7d51b2e84f07a3c6d9e1b50f28a4c73d96e0b1f5a28c4d7e39",
    signers: [MULTISIG_OWNERS[0], MULTISIG_OWNERS[1]],
    status: "FAILED",
    createdAt: MOCK_NOW - 2 * DAY,
    simulationError: "PriceFeedManager__UpdateNotExecutableYet(1764330000)",
  },
  {
    id: 11,
    target: "IndexManager",
    fn: "createIndex",
    args: [
      { name: "asset0", type: "address", value: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" },
      { name: "asset1", type: "address", value: "0x514910771AF9Ca656af840dff83E8264EcF986CA" },
      { name: "name", type: "string", value: "Ether Chainlink Index" },
      { name: "symbol", type: "string", value: "ETHLINK" },
    ],
    value: "0",
    calldata: "0x3e8b1f0a000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
    digest: "0x61a0e3f9c2b74d85e1f3a06c9d27b4e58f13a6c0d92e7b41f50a8c3d6e29b7f4",
    signers: [MULTISIG_OWNERS[0], MULTISIG_OWNERS[1]],
    status: "EXECUTED",
    createdAt: MOCK_NOW - 30 * DAY,
    simulationError: null,
  },
];

/** Actions an owner can propose, grouped by target. Arguments follow the function signature. */
export const PROPOSAL_ACTIONS: Record<ContractName, { fn: string; args: string[] }[]> = {
  IndexManager: [
    { fn: "createIndex", args: ["address asset0", "address asset1", "string name", "string symbol"] },
    { fn: "initializeIndex", args: ["address index", "uint256 usdcAmount"] },
    { fn: "proposeWeights", args: ["address index", "uint16 weight0", "uint16 weight1"] },
    { fn: "cancelWeights", args: ["address index"] },
    { fn: "proposePriceFeed", args: ["address asset", "address feed", "uint256 maxDelay"] },
    { fn: "grantRole", args: ["bytes32 role", "address account"] },
    { fn: "revokeRole", args: ["bytes32 role", "address account"] },
  ],
  TimelockController: [
    { fn: "schedule", args: ["address target", "uint256 value", "bytes data", "bytes32 predecessor", "bytes32 salt", "uint256 delay"] },
    { fn: "execute", args: ["address target", "uint256 value", "bytes data", "bytes32 predecessor", "bytes32 salt"] },
    { fn: "cancel", args: ["bytes32 id"] },
  ],
  PriceFeedManager: [],
  SwapManager: [],
  Router: [],
  MultiSigWallet: [],
};

export type WeightStatus = "PENDING" | "EXECUTABLE" | "EXECUTED" | "CANCELLED" | "EXPIRED" | "OVERWRITTEN";

export interface WeightProposal {
  id: string;
  indexSymbol: string;
  current: [number, number];
  proposed: [number, number];
  proposedAt: number;
  executableAt: number;
  status: WeightStatus;
}

export const WEIGHT_PROPOSALS: WeightProposal[] = [
  { id: "w4", indexSymbol: "LINKCOMP", current: [5_000, 5_000], proposed: [5_500, 4_500], proposedAt: MOCK_NOW - 4 * DAY, executableAt: MOCK_NOW - 1 * DAY, status: "EXECUTABLE" },
  { id: "w3", indexSymbol: "BTCETH", current: [6_000, 4_000], proposed: [6_500, 3_500], proposedAt: MOCK_NOW - 1 * DAY, executableAt: MOCK_NOW + 2 * DAY, status: "PENDING" },
  { id: "w2", indexSymbol: "BTCETH", current: [5_000, 5_000], proposed: [6_000, 4_000], proposedAt: MOCK_NOW - 40 * DAY, executableAt: MOCK_NOW - 37 * DAY, status: "EXECUTED" },
  { id: "w1", indexSymbol: "ETHLINK", current: [7_000, 3_000], proposed: [6_000, 4_000], proposedAt: MOCK_NOW - 22 * DAY, executableAt: MOCK_NOW - 19 * DAY, status: "CANCELLED" },
];

export type TimelockStatus = "WAITING" | "READY" | "DONE" | "CANCELLED";

export interface TimelockOperation {
  id: string;
  target: ContractName;
  call: string;
  predecessor: string | null;
  predecessorDone: boolean;
  readyAt: number;
  status: TimelockStatus;
}

export const TIMELOCK_OPERATIONS: TimelockOperation[] = [
  { id: "0x7a3f…c210", target: "SwapManager", call: "upgradeToAndCall(0x2279B7A0…ebd6, 0x)", predecessor: null, predecessorDone: true, readyAt: MOCK_NOW + 1 * DAY, status: "WAITING" },
  { id: "0x19be…04d7", target: "Router", call: "upgradeToAndCall(0x8464135c…6f92, 0x)", predecessor: "0x7a3f…c210", predecessorDone: false, readyAt: MOCK_NOW - 2 * H, status: "READY" },
  { id: "0xe540…9a1b", target: "PriceFeedManager", call: "upgradeToAndCall(0x71C95911…98bA, 0x)", predecessor: null, predecessorDone: true, readyAt: MOCK_NOW - 18 * DAY, status: "DONE" },
];

export type FeedStatus = "WAITING" | "OPEN" | "EXECUTED" | "EXPIRED";

export interface FeedReplacement {
  id: string;
  asset: string;
  currentFeed: string;
  proposedFeed: string;
  maxDelay: number;
  executableAt: number;
  windowEnd: number;
  status: FeedStatus;
}

export const FEED_REPLACEMENTS: FeedReplacement[] = [
  { id: "f3", asset: "COMP", currentFeed: "0xdbd020CAeF83eFd542f4De03e3cF0C28A4428bd5", proposedFeed: "0x1B39Ee86Ec5979ba5C322b826B3ECb8C79991699", maxDelay: 3_600, executableAt: MOCK_NOW + 1 * DAY, windowEnd: MOCK_NOW + 4 * DAY, status: "WAITING" },
  { id: "f2", asset: "LINK", currentFeed: "0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c", proposedFeed: "0x76B1E4B3a8C36a4a2E1C1f8E84E4fA1c90a7d3E2", maxDelay: 3_600, executableAt: MOCK_NOW - 1 * DAY, windowEnd: MOCK_NOW + 2 * DAY, status: "OPEN" },
  { id: "f1", asset: "WETH", currentFeed: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419", proposedFeed: "0x9a1C7E8d2F05b3A1c6E4d7F80b2A9e3C5d1F6a40", maxDelay: 3_600, executableAt: MOCK_NOW - 12 * DAY, windowEnd: MOCK_NOW - 9 * DAY, status: "EXPIRED" },
];
