import { useCallback, useRef, useState } from "react";
import { Link } from "react-router";
import { useOpenAllowances } from "../../features/personal";
import { useI18n } from "../../i18n/context";
import { shortAddress } from "../../lib/format";
import { DEMO_ACCOUNTS, isMultisigOwner, sameAddress } from "../../mock/accounts";
import { useSession } from "../../session/context";
import { Address } from "../ui/Address";
import { Badge } from "../ui/Badge";
import { Button } from "../ui/Button";
import { Icon } from "../ui/Icon";
import { useDismiss } from "./useDismiss";

export function AccountMenu() {
  const { t } = useI18n();
  const session = useSession();
  const allowances = useOpenAllowances();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const close = useCallback(() => setOpen(false), []);
  useDismiss(ref, open, close);

  if (!session.address) {
    return (
      <Button size="sm" onClick={session.openConnect} className="h-9">
        <Icon name="wallet" className="size-4" />
        <span className="hidden sm:inline">{t.account.connect}</span>
      </Button>
    );
  }

  const label = DEMO_ACCOUNTS.find((a) => sameAddress(a.address, session.address))?.label;
  const owner = isMultisigOwner(session.address);
  const itemClass = "flex items-center gap-3 px-4 py-2.5 text-sm text-navy-700 hover:bg-navy-50";

  return (
    <div ref={ref} className="relative flex items-center gap-2">
      {!session.signedIn && (
        <Button size="sm" variant="warning" onClick={session.openSignIn} className="hidden h-9 sm:inline-flex">
          {t.account.signIn}
        </Button>
      )}
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        className="relative flex h-9 items-center gap-2 rounded-lg border border-navy-700 bg-navy-800 px-2.5 text-sm font-semibold text-white hover:border-brand-500"
      >
        <span className={`size-2 rounded-full ${session.signedIn ? "bg-brand-500" : "bg-amber-500"}`} />
        <span className="font-mono text-xs">{shortAddress(session.address)}</span>
        <Icon name="chevronDown" className="size-4 text-navy-300" />
        {allowances.length > 0 && (
          <span
            className="absolute -top-1.5 -right-1.5 flex size-4 items-center justify-center rounded-full bg-amber-500 text-[10px] font-bold text-navy-900"
            title={t.account.openAllowances(allowances.length)}
          >
            {allowances.length}
          </span>
        )}
      </button>

      {open && (
        <div className="fixed inset-x-4 top-16 z-40 overflow-hidden rounded-2xl border border-navy-100 bg-white text-navy-900 shadow-xl sm:absolute sm:inset-x-auto sm:top-12 sm:right-0 sm:w-80">
          <div className="border-b border-navy-100 p-4">
            <div className="text-xs text-navy-500">{session.signedIn ? t.account.signedInAs : t.account.connectedNotSignedIn}</div>
            <div className="mt-1 flex flex-wrap items-center gap-2">
              <Address address={session.address} name={label} />
              {owner && <Badge tone="amber">{t.account.multisigOwner}</Badge>}
            </div>
            {!session.signedIn && (
              <Button
                block
                size="sm"
                className="mt-3"
                onClick={() => {
                  close();
                  session.openSignIn();
                }}
              >
                {t.account.signIn}
              </Button>
            )}
          </div>
          <nav className="py-1">
            <Link to="/portfolio" onClick={close} className={itemClass}>
              <Icon name="wallet" className="size-4" /> {t.nav.portfolio}
            </Link>
            <Link to="/portfolio/allowances" onClick={close} className={itemClass}>
              <Icon name="shield" className="size-4" /> {t.allowances.title}
              {allowances.length > 0 && (
                <Badge tone="amber" className="ml-auto">
                  {allowances.length}
                </Badge>
              )}
            </Link>
            <Link to="/wallets" onClick={close} className={itemClass}>
              <Icon name="link" className="size-4" /> {t.nav.wallets}
            </Link>
            <Link to="/notifications" onClick={close} className={itemClass}>
              <Icon name="bell" className="size-4" /> {t.nav.notifications}
            </Link>
          </nav>
          <div className="border-t border-navy-100 py-1">
            <button type="button" onClick={session.openConnect} className={`${itemClass} w-full`}>
              <Icon name="wallet" className="size-4" /> {t.account.chooseDemoWallet}
            </button>
            {session.signedIn && (
              <button
                type="button"
                onClick={() => {
                  close();
                  session.signOut();
                }}
                className={`${itemClass} w-full`}
              >
                <Icon name="logout" className="size-4" /> {t.account.signOut}
              </button>
            )}
            <button
              type="button"
              onClick={() => {
                close();
                session.disconnect();
              }}
              className={`${itemClass} w-full`}
            >
              <Icon name="close" className="size-4" /> {t.account.disconnect}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
