import type { ReactNode } from "react";
import { NotFoundPage } from "../../pages/NotFoundPage";
import { useSession } from "../../session/context";

/**
 * Renders the admin area only for a signed-in MultiSig owner. Anyone else gets the
 * ordinary 404, so the page does not reveal that it exists.
 *
 * This hides UI only: the real protection is on-chain (only the MultiSig holds the roles,
 * and confirmations need an owner's EIP-712 signature) and in the API session checks.
 */
export function RequireMultisigOwner({ children }: { children: ReactNode }) {
  const { isAdmin } = useSession();
  return isAdmin ? <>{children}</> : <NotFoundPage />;
}
