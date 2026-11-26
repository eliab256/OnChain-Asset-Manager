import { useState } from "react";
import { Address } from "../components/ui/Address";
import { Badge } from "../components/ui/Badge";
import { Banner } from "../components/ui/Banner";
import { Button } from "../components/ui/Button";
import { Card, CardHeader } from "../components/ui/Card";
import { EmptyState } from "../components/ui/EmptyState";
import { Icon } from "../components/ui/Icon";
import { PageHeader } from "../components/ui/PageHeader";
import { cx } from "../components/ui/cx";
import { useWalletGroup } from "../features/personal";
import { useI18n } from "../i18n/context";
import { useFormat } from "../lib/format";
import { DEMO_ACCOUNTS, sameAddress, type LinkedWallet } from "../mock/accounts";
import { MOCK_NOW } from "../mock/market";
import { useSession } from "../session/context";

const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;

export function LinkedWalletsPage() {
  const { t } = useI18n();
  const f = useFormat();
  const session = useSession();
  const group = useWalletGroup();
  // Local edits of the demo group: unlinked and newly linked wallets.
  const [removed, setRemoved] = useState<string[]>([]);
  const [added, setAdded] = useState<LinkedWallet[]>([]);
  const [candidate, setCandidate] = useState("");
  const [step, setStep] = useState<0 | 1 | 2 | 3>(0);

  if (!session.signedIn || !session.address) {
    return (
      <>
        <PageHeader title={t.wallets.title} subtitle={t.wallets.subtitle} />
        <EmptyState
          icon="link"
          title={t.wallets.signInRequired}
          action={
            session.address ? (
              <Button onClick={session.openSignIn}>{t.account.signIn}</Button>
            ) : (
              <Button onClick={session.openConnect}>{t.account.connect}</Button>
            )
          }
        />
      </>
    );
  }

  const wallets = [...group, ...added].filter((w) => !removed.some((r) => sameAddress(r, w.address)));
  const validAddress = ADDRESS_RE.test(candidate.trim());
  const duplicate = wallets.some((w) => sameAddress(w.address, candidate.trim()));
  const inputError = candidate.trim() !== "" && (!validAddress ? t.wallets.invalidAddress : duplicate ? t.wallets.alreadyLinked : null);

  const steps = [t.wallets.step1, t.wallets.step2, t.wallets.step3];

  const advance = () => {
    if (step === 2) {
      setAdded((a) => [...a, { address: candidate.trim(), linkedAt: MOCK_NOW }]);
      setStep(3);
    } else {
      setStep((s) => (s === 0 ? 1 : 2));
    }
  };

  const reset = () => {
    setCandidate("");
    setStep(0);
  };

  return (
    <>
      <PageHeader title={t.wallets.title} subtitle={t.wallets.subtitle} />

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_400px]">
        <div className="flex min-w-0 flex-col gap-6">
          <Card>
            <CardHeader title={t.wallets.group} />
            <ul className="divide-y divide-navy-100">
              {wallets.map((w) => {
                const current = sameAddress(w.address, session.address);
                const label = DEMO_ACCOUNTS.find((a) => sameAddress(a.address, w.address))?.label;
                return (
                  <li key={w.address} className="flex flex-wrap items-center gap-3 py-3">
                    <span className="flex size-9 items-center justify-center rounded-full bg-navy-100 text-navy-700">
                      <Icon name="wallet" className="size-4" />
                    </span>
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <Address address={w.address} name={label} />
                        {current && <Badge tone="brand">{t.wallets.current}</Badge>}
                      </div>
                      {wallets.length > 1 && (
                        <div className="mt-0.5 text-xs text-navy-500">
                          {t.wallets.linkedSince} {f.date(new Date(w.linkedAt))}
                        </div>
                      )}
                    </div>
                    {!current && (
                      <Button size="sm" variant="secondary" onClick={() => setRemoved((r) => [...r, w.address])}>
                        {t.wallets.unlink}
                      </Button>
                    )}
                  </li>
                );
              })}
            </ul>
          </Card>

          <Banner tone="navy" icon="shield" title={t.wallets.privacyNote} />

          <Card>
            <CardHeader title={t.wallets.sessions} subtitle={t.wallets.sessionsHint} />
            <Button variant="secondary" onClick={session.signOut}>
              <Icon name="logout" className="size-4" /> {t.account.signOutAll}
            </Button>
          </Card>
        </div>

        <Card className="h-fit">
          <CardHeader title={t.wallets.linkNew} subtitle={t.wallets.linkNewHint} />
          <label className="block">
            <span className="mb-1.5 block text-xs font-medium text-navy-500">{t.wallets.addressLabel}</span>
            <input
              value={candidate}
              onChange={(e) => {
                setCandidate(e.target.value);
                setStep(0);
              }}
              placeholder="0x…"
              disabled={step > 0 && step < 3}
              className={cx("w-full font-mono", inputError && "border-loss-600")}
            />
          </label>
          {inputError && <p className="mt-1.5 text-xs text-loss-600">{inputError}</p>}

          <ol className="mt-5 flex flex-col gap-3">
            {steps.map((label, i) => {
              const n = i + 1;
              const done = step > n || step === 3;
              const active = step === n;
              return (
                <li key={label} className="flex items-center gap-3 text-sm">
                  <span
                    className={cx(
                      "flex size-7 shrink-0 items-center justify-center rounded-full text-xs font-bold",
                      done ? "bg-brand-600 text-white" : active ? "bg-amber-500 text-navy-900" : "bg-navy-100 text-navy-500",
                    )}
                  >
                    {done ? <Icon name="check" className="size-4" /> : n}
                  </span>
                  <span className={cx(active ? "font-semibold text-navy-900" : "text-navy-500")}>{label}</span>
                </li>
              );
            })}
          </ol>

          <div className="mt-5">
            {step === 3 ? (
              <Button block variant="secondary" onClick={reset}>
                {t.wallets.linkNew}
              </Button>
            ) : step === 0 ? (
              <Button block disabled={!validAddress || duplicate} onClick={advance}>
                {t.wallets.start}
              </Button>
            ) : (
              <Button block onClick={advance}>
                <Icon name="signature" className="size-4" /> {t.wallets.signNow}
              </Button>
            )}
          </div>
        </Card>
      </div>
    </>
  );
}
