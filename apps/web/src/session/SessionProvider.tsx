import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { DEMO_ACCOUNTS, isMultisigOwner, sameAddress, walletGroup } from "../mock/accounts";
import { readStorage, writeStorage } from "../lib/storage";
import { CHAINS, SessionContext, type ChainKey, type SessionValue } from "./context";
import { ConnectDialog, SignInDialog } from "./SessionDialogs";

const KEY = "oam.demo-session";

interface Stored {
  address: string | null;
  /** Wallet that signed the SIWE message; the session covers its whole wallet group. */
  sessionAddress: string | null;
  chain: ChainKey;
}

function load(): Stored {
  const fallback: Stored = { address: null, sessionAddress: null, chain: "anvil" };
  const raw = readStorage(KEY);
  if (!raw) return fallback;
  try {
    const parsed = JSON.parse(raw) as Partial<Stored>;
    return {
      address: typeof parsed.address === "string" ? parsed.address : null,
      sessionAddress: typeof parsed.sessionAddress === "string" ? parsed.sessionAddress : null,
      chain: parsed.chain === "fork" ? "fork" : "anvil",
    };
  } catch {
    return fallback;
  }
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<Stored>(load);
  const [dialog, setDialog] = useState<"connect" | "signIn" | null>(null);

  useEffect(() => {
    writeStorage(KEY, JSON.stringify(state));
  }, [state]);

  const { address, sessionAddress, chain } = state;

  // A session stays valid while the connected wallet is in the group of the wallet that signed.
  const signedIn =
    !!address && !!sessionAddress && walletGroup(sessionAddress).some((w) => sameAddress(w.address, address));

  const connect = useCallback((next: string) => {
    setState((s) => ({ ...s, address: next }));
    setDialog(null);
  }, []);
  const disconnect = useCallback(() => setState((s) => ({ ...s, address: null })), []);
  const signIn = useCallback(() => {
    setState((s) => ({ ...s, sessionAddress: s.address }));
    setDialog(null);
  }, []);
  const signOut = useCallback(() => setState((s) => ({ ...s, sessionAddress: null })), []);
  const setChain = useCallback((next: ChainKey) => setState((s) => ({ ...s, chain: next })), []);
  const openConnect = useCallback(() => setDialog("connect"), []);
  const openSignIn = useCallback(() => setDialog("signIn"), []);
  const closeDialog = useCallback(() => setDialog(null), []);

  const value = useMemo<SessionValue>(
    () => ({
      address,
      signedIn,
      chain,
      isAdmin: signedIn && isMultisigOwner(address),
      connect,
      disconnect,
      signIn,
      signOut,
      setChain,
      openConnect,
      openSignIn,
    }),
    [address, signedIn, chain, connect, disconnect, signIn, signOut, setChain, openConnect, openSignIn],
  );

  return (
    <SessionContext.Provider value={value}>
      {children}
      <ConnectDialog open={dialog === "connect"} onClose={closeDialog} accounts={DEMO_ACCOUNTS} current={address} onPick={connect} />
      <SignInDialog
        open={dialog === "signIn"}
        onClose={closeDialog}
        address={address}
        chainId={CHAINS[chain].id}
        onSign={signIn}
      />
    </SessionContext.Provider>
  );
}
