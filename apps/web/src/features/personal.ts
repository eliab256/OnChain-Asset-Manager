// Personal data of the connected wallet, read from the mock and filtered by the local demo state.
import { useMemo } from "react";
import {
  allowancesOf,
  notificationsOf,
  pendingTransfersOf,
  positionsOf,
  walletGroup,
  type AppNotification,
} from "../mock/accounts";
import { useDemoState } from "../session/demo-state";
import { useSession } from "../session/context";

/** Wallets whose data the user may see: the whole linked group when signed in, else only the connected one. */
export function useWalletGroup() {
  const { address, signedIn } = useSession();
  return useMemo(() => (!address ? [] : signedIn ? walletGroup(address) : [{ address, linkedAt: 0 }]), [address, signedIn]);
}

export function usePositions() {
  const group = useWalletGroup();
  return useMemo(() => group.flatMap((w) => positionsOf(w.address)), [group]);
}

/** Allowances need no sign-in: they are chain data of the connected wallet only. */
export function useOpenAllowances() {
  const { address } = useSession();
  const { revokedAllowances } = useDemoState();
  return useMemo(
    () => (address ? allowancesOf(address).filter((a) => !revokedAllowances.has(a.id)) : []),
    [address, revokedAllowances],
  );
}

export function usePendingTransfers() {
  const group = useWalletGroup();
  const { declaredPrices } = useDemoState();
  return useMemo(
    () => pendingTransfersOf(group.map((w) => w.address)).filter((p) => !declaredPrices.has(p.id)),
    [group, declaredPrices],
  );
}

export function useNotifications(): { items: AppNotification[]; unread: number } {
  const { address, signedIn } = useSession();
  const { readNotifications, declaredPrices } = useDemoState();
  return useMemo(() => {
    if (!address || !signedIn) return { items: [], unread: 0 };
    const items = notificationsOf(address).map((n) => ({
      ...n,
      read: n.read || readNotifications.has(n.id) || (!!n.pendingId && declaredPrices.has(n.pendingId)),
    }));
    return { items, unread: items.filter((n) => !n.read).length };
  }, [address, signedIn, readNotifications, declaredPrices]);
}
