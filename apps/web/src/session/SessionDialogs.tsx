import { Address } from "../components/ui/Address";
import { Badge } from "../components/ui/Badge";
import { Button } from "../components/ui/Button";
import { Icon } from "../components/ui/Icon";
import { Modal } from "../components/ui/Modal";
import { cx } from "../components/ui/cx";
import { useI18n } from "../i18n/context";
import { sameAddress, type DemoAccount } from "../mock/accounts";

interface ConnectProps {
  open: boolean;
  onClose: () => void;
  accounts: DemoAccount[];
  current: string | null;
  onPick: (address: string) => void;
}

// Stand-in for the RainbowKit connect modal.
export function ConnectDialog({ open, onClose, accounts, current, onPick }: ConnectProps) {
  const { t } = useI18n();
  return (
    <Modal open={open} onClose={onClose} title={t.account.chooseDemoWallet}>
      <p className="mb-4 text-sm text-navy-500">{t.account.chooseDemoWalletHint}</p>
      <ul className="flex flex-col gap-2">
        {accounts.map((a) => (
          <li key={a.address}>
            <button
              type="button"
              onClick={() => onPick(a.address)}
              className={cx(
                "flex w-full items-center gap-3 rounded-xl border p-3 text-left transition-colors hover:border-brand-600",
                sameAddress(a.address, current) ? "border-brand-600 bg-brand-50" : "border-navy-100",
              )}
            >
              <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-navy-900 text-white">
                <Icon name={a.role === "owner" ? "shield" : "wallet"} className="size-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block font-semibold text-navy-900">{a.label}</span>
                <Address address={a.address} copy={false} />
              </span>
              <Badge tone={a.role === "owner" ? "amber" : "navy"}>{a.role === "owner" ? t.account.multisigOwner : t.account.investor}</Badge>
            </button>
          </li>
        ))}
      </ul>
    </Modal>
  );
}

interface SignInProps {
  open: boolean;
  onClose: () => void;
  address: string | null;
  chainId: number;
  onSign: () => void;
}

// Stand-in for the SIWE (EIP-4361) message shown by RainbowKitAuthenticationProvider.
export function SignInDialog({ open, onClose, address, chainId, onSign }: SignInProps) {
  const { t } = useI18n();
  const rows: [string, string][] = [
    [t.account.siweDomain, window.location.host],
    [t.account.siweAddress, address ?? "-"],
    [t.account.siweChain, String(chainId)],
    [t.account.siweExpires, t.account.siweExpiresValue],
  ];
  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t.account.siweTitle}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            {t.common.cancel}
          </Button>
          <Button onClick={onSign} disabled={!address}>
            <Icon name="signature" className="size-4" />
            {t.account.signMessage}
          </Button>
        </>
      }
    >
      <p className="mb-4 text-sm text-navy-700">{t.account.siweBody}</p>
      <dl className="divide-y divide-navy-100 rounded-xl border border-navy-100 bg-navy-50 text-sm">
        {rows.map(([k, v]) => (
          <div key={k} className="flex justify-between gap-4 px-4 py-2.5">
            <dt className="text-navy-500">{k}</dt>
            <dd className="truncate font-mono text-xs text-navy-900">{v}</dd>
          </div>
        ))}
      </dl>
    </Modal>
  );
}
