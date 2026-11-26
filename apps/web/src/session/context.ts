import { createContext, useContext } from "react";

export type ChainKey = "anvil" | "fork";

export const CHAINS: Record<ChainKey, { id: number }> = {
  anvil: { id: 31337 },
  fork: { id: 31338 },
};

/**
 * Demo wallet session. Stands in for wagmi (connection) and SIWE (sign-in) until phase 6
 * wires the real providers: `address` is the connected account, `signedIn` the SIWE session.
 */
export interface SessionValue {
  address: string | null;
  signedIn: boolean;
  chain: ChainKey;
  /** Signed in with one of the MultiSig owners: the only case where the admin page exists. */
  isAdmin: boolean;
  connect: (address: string) => void;
  disconnect: () => void;
  signIn: () => void;
  signOut: () => void;
  setChain: (chain: ChainKey) => void;
  /** Opens the demo "connect wallet" dialog. */
  openConnect: () => void;
  /** Opens the SIWE sign-in dialog. */
  openSignIn: () => void;
}

export const SessionContext = createContext<SessionValue | null>(null);

export function useSession(): SessionValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("useSession must be used inside <SessionProvider>");
  return value;
}
