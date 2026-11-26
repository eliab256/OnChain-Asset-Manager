// Demo accounts (anvil default keys 0-5) and the personal data each one would see.
import { INDEXES, MOCK_NOW, type IndexInfo } from "./market";

export interface DemoAccount {
  address: string;
  label: string;
  role: "owner" | "investor";
}

export const MULTISIG_OWNERS = [
  "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
] as const;

export const MULTISIG_THRESHOLD = 2;

export const DEMO_ACCOUNTS: DemoAccount[] = [
  { address: MULTISIG_OWNERS[0], label: "Owner 1", role: "owner" },
  { address: MULTISIG_OWNERS[1], label: "Owner 2", role: "owner" },
  { address: MULTISIG_OWNERS[2], label: "Owner 3", role: "owner" },
  { address: "0x90F79bf6EB2c4f870365E785982E1f101E93b906", label: "Investor A", role: "investor" },
  { address: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65", label: "Investor B", role: "investor" },
];

export function sameAddress(a: string | null | undefined, b: string | null | undefined): boolean {
  return !!a && !!b && a.toLowerCase() === b.toLowerCase();
}

export function isMultisigOwner(address: string | null): boolean {
  return MULTISIG_OWNERS.some((o) => sameAddress(o, address));
}

const DAY = 86_400_000;

// Groups of linked wallets (WalletGroup / WalletLink in the DB).
export interface LinkedWallet {
  address: string;
  linkedAt: number;
}

const GROUPS: LinkedWallet[][] = [
  [
    { address: "0x90F79bf6EB2c4f870365E785982E1f101E93b906", linkedAt: MOCK_NOW - 64 * DAY },
    { address: "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc", linkedAt: MOCK_NOW - 64 * DAY },
    { address: "0x976EA74026E726554dB657fA54763abd0C3a0aa9", linkedAt: MOCK_NOW - 12 * DAY },
  ],
];

export function walletGroup(address: string): LinkedWallet[] {
  const group = GROUPS.find((g) => g.some((w) => sameAddress(w.address, address)));
  return group ?? [{ address, linkedAt: MOCK_NOW }];
}

export interface Position {
  wallet: string;
  index: IndexInfo;
  shares: number;
  /** USDC spent for the shares with a known cost; null when nothing is known. */
  cost: number | null;
  /** Shares received from another person whose price was not declared yet. */
  unknownCostShares: number;
}

function idx(n: number): IndexInfo {
  const i = INDEXES[n];
  if (!i) throw new Error(`mock index ${n} missing`);
  return i;
}

const POSITIONS: Record<string, Omit<Position, "wallet">[]> = {
  "0x90f79bf6eb2c4f870365e785982e1f101e93b906": [
    { index: idx(0), shares: 42.5, cost: 8_290, unknownCostShares: 0 },
    { index: idx(1), shares: 18, cost: 2_380, unknownCostShares: 4 },
  ],
  "0x9965507d1a55bcc2695c58ba16fb37d819b0a4dc": [{ index: idx(2), shares: 30.2, cost: 6_190, unknownCostShares: 0 }],
  "0x976ea74026e726554db657fa54763abd0c3a0aa9": [{ index: idx(0), shares: 6, cost: 1_368, unknownCostShares: 0 }],
  "0x15d34aaf54267db7d7c367839aaf71a00a2c6a65": [
    { index: idx(0), shares: 12, cost: 2_460, unknownCostShares: 0 },
    { index: idx(2), shares: 9.5, cost: null, unknownCostShares: 9.5 },
  ],
  "0x70997970c51812dc3a010c7d01b50e0d17dc79c8": [{ index: idx(0), shares: 120, cost: 22_800, unknownCostShares: 0 }],
};

export function positionsOf(wallet: string): Position[] {
  return (POSITIONS[wallet.toLowerCase()] ?? []).map((p) => ({ ...p, wallet }));
}

export interface Allowance {
  id: string;
  index: IndexInfo;
  spender: string;
  spenderName: string | null;
  /** null = type(uint256).max */
  amount: number | null;
  approvedAt: number;
  tx: string;
}

const ALLOWANCES: Record<string, Allowance[]> = {
  "0x90f79bf6eb2c4f870365e785982e1f101e93b906": [
    {
      id: "a1",
      index: idx(0),
      spender: "0x000000000022D473030F116dDEE9F6B43aC78BA3",
      spenderName: "Permit2",
      amount: null,
      approvedAt: MOCK_NOW - 41 * DAY,
      tx: "0x3fa8c1d29e70",
    },
    {
      id: "a2",
      index: idx(1),
      spender: "0x1111111254EEB25477B68fb85Ed929f73A960582",
      spenderName: "1inch Router",
      amount: 10,
      approvedAt: MOCK_NOW - 9 * DAY,
      tx: "0x8c02e7fb14a5",
    },
    {
      id: "a3",
      index: idx(0),
      spender: "0x4b1F6E0b2c13dA3f4E24C2a7Ef1C1d6A0B9f12e7",
      spenderName: null,
      amount: null,
      approvedAt: MOCK_NOW - 3 * DAY,
      tx: "0xe41b9a70c3d2",
    },
  ],
  "0x15d34aaf54267db7d7c367839aaf71a00a2c6a65": [
    {
      id: "b1",
      index: idx(2),
      spender: "0x1111111254EEB25477B68fb85Ed929f73A960582",
      spenderName: "1inch Router",
      amount: 5,
      approvedAt: MOCK_NOW - 20 * DAY,
      tx: "0x0d9e3b71a6f4",
    },
  ],
};

export function allowancesOf(wallet: string): Allowance[] {
  return ALLOWANCES[wallet.toLowerCase()] ?? [];
}

export interface PendingTransfer {
  id: string;
  wallet: string;
  from: string;
  index: IndexInfo;
  shares: number;
  receivedAt: number;
  tx: string;
}

const PENDING: PendingTransfer[] = [
  {
    id: "p1",
    wallet: "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
    from: "0xBcd4042DE499D14e55001CcbB24a551F3b954096",
    index: idx(1),
    shares: 4,
    receivedAt: MOCK_NOW - 2 * DAY,
    tx: "0x71c3e0ad9b52",
  },
  {
    id: "p2",
    wallet: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65",
    from: "0x71bE63f3384f5fb98995898A86B02Fb2426c5788",
    index: idx(2),
    shares: 9.5,
    receivedAt: MOCK_NOW - 6 * 3_600_000,
    tx: "0xa0e4f17c28d3",
  },
];

export function pendingTransfersOf(wallets: string[]): PendingTransfer[] {
  return PENDING.filter((p) => wallets.some((w) => sameAddress(w, p.wallet)));
}

export type NotificationType =
  | "SHARES_RECEIVED"
  | "TRADE_CONFIRMED"
  | "REBALANCE"
  | "WEIGHTS_PROPOSED"
  | "UPGRADE_SCHEDULED"
  | "PRICE_FEED_PROPOSED";

export interface AppNotification {
  id: string;
  type: NotificationType;
  /** Index symbol, or the upgraded contract for UPGRADE_SCHEDULED. */
  subject: string;
  shares: number;
  t: number;
  read: boolean;
  /** For SHARES_RECEIVED: the transfer waiting for a price. */
  pendingId?: string;
  link?: string;
}

export function notificationsOf(wallet: string): AppNotification[] {
  const owner = isMultisigOwner(wallet);
  const base: AppNotification[] = [
    { id: "n2", type: "REBALANCE", subject: "BTCETH", shares: 0, t: MOCK_NOW - 19 * 3_600_000, read: false, link: `/index/${idx(0).address}` },
    { id: "n3", type: "TRADE_CONFIRMED", subject: "BTCETH", shares: 12.4, t: MOCK_NOW - 3 * DAY, read: true, link: "/portfolio" },
    { id: "n4", type: "WEIGHTS_PROPOSED", subject: "LINKCOMP", shares: 0, t: MOCK_NOW - 4 * DAY, read: true, link: `/index/${idx(1).address}` },
  ];
  const pending = PENDING.filter((p) => walletGroup(wallet).some((w) => sameAddress(w.address, p.wallet))).map(
    (p): AppNotification => ({
      id: `n-${p.id}`,
      type: "SHARES_RECEIVED",
      subject: p.index.symbol,
      shares: p.shares,
      t: p.receivedAt,
      read: false,
      pendingId: p.id,
    }),
  );
  const admin: AppNotification[] = owner
    ? [
        { id: "n5", type: "UPGRADE_SCHEDULED", subject: "SwapManager", shares: 0, t: MOCK_NOW - 1 * DAY, read: false, link: "/admin?tab=timelock" },
        { id: "n6", type: "PRICE_FEED_PROPOSED", subject: "COMP", shares: 0, t: MOCK_NOW - 2 * DAY, read: false, link: "/admin?tab=feeds" },
      ]
    : [];
  return [...pending, ...admin, ...base].sort((a, b) => b.t - a.t);
}

export function findPendingTransfer(id: string | null): PendingTransfer | undefined {
  return id ? PENDING.find((p) => p.id === id) : undefined;
}
