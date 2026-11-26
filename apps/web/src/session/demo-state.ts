import { createContext, useContext } from "react";

/** Local-only demo actions: what the API and the chain would persist in the real app. */
export interface DemoStateValue {
  readNotifications: ReadonlySet<string>;
  markRead: (ids: string[]) => void;
  revokedAllowances: ReadonlySet<string>;
  revokeAllowances: (ids: string[]) => void;
  declaredPrices: ReadonlyMap<string, number>;
  declarePrice: (pendingId: string, pricePerShare: number) => void;
  /** Pending transfer shown in the "shares received" dialog, or null. */
  priceDialog: string | null;
  openPriceDialog: (pendingId: string) => void;
  closePriceDialog: () => void;
}

export const DemoStateContext = createContext<DemoStateValue | null>(null);

export function useDemoState(): DemoStateValue {
  const value = useContext(DemoStateContext);
  if (!value) throw new Error("useDemoState must be used inside <DemoStateProvider>");
  return value;
}
