import { useCallback, useMemo, useState, type ReactNode } from "react";
import { SharesReceivedDialog } from "../features/notifications/SharesReceivedDialog";
import { DemoStateContext, type DemoStateValue } from "./demo-state";

export function DemoStateProvider({ children }: { children: ReactNode }) {
  const [readNotifications, setRead] = useState<ReadonlySet<string>>(() => new Set());
  const [revokedAllowances, setRevoked] = useState<ReadonlySet<string>>(() => new Set());
  const [declaredPrices, setDeclared] = useState<ReadonlyMap<string, number>>(() => new Map());
  const [priceDialog, setPriceDialog] = useState<string | null>(null);

  const markRead = useCallback((ids: string[]) => setRead((s) => new Set([...s, ...ids])), []);
  const revokeAllowances = useCallback((ids: string[]) => setRevoked((s) => new Set([...s, ...ids])), []);
  const declarePrice = useCallback((id: string, price: number) => setDeclared((m) => new Map(m).set(id, price)), []);
  const openPriceDialog = useCallback((id: string) => setPriceDialog(id), []);
  const closePriceDialog = useCallback(() => setPriceDialog(null), []);

  const value = useMemo<DemoStateValue>(
    () => ({
      readNotifications,
      markRead,
      revokedAllowances,
      revokeAllowances,
      declaredPrices,
      declarePrice,
      priceDialog,
      openPriceDialog,
      closePriceDialog,
    }),
    [readNotifications, markRead, revokedAllowances, revokeAllowances, declaredPrices, declarePrice, priceDialog, openPriceDialog, closePriceDialog],
  );

  return (
    <DemoStateContext.Provider value={value}>
      {children}
      <SharesReceivedDialog />
    </DemoStateContext.Provider>
  );
}
