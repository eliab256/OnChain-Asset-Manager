import { Link } from "react-router";
import { Address } from "../components/ui/Address";
import { Badge } from "../components/ui/Badge";
import { Button, ButtonLink } from "../components/ui/Button";
import { Banner } from "../components/ui/Banner";
import { Card, CardHeader } from "../components/ui/Card";
import { Change, UsdChange } from "../components/ui/Change";
import { EmptyState } from "../components/ui/EmptyState";
import { PageHeader } from "../components/ui/PageHeader";
import { ResponsiveTable, type Column } from "../components/ui/ResponsiveTable";
import { StatTile } from "../components/ui/StatTile";
import { AssetPair } from "../components/charts/AssetPair";
import { useOpenAllowances, usePendingTransfers, usePositions, useWalletGroup } from "../features/personal";
import { useI18n } from "../i18n/context";
import { useFormat } from "../lib/format";
import { DEMO_ACCOUNTS, pendingTransfersOf, sameAddress, type PendingTransfer, type Position } from "../mock/accounts";
import { useDemoState } from "../session/demo-state";
import { useSession } from "../session/context";

interface Row extends Position {
  value: number;
  /** P&L on the shares with a known cost. */
  pnl: number | null;
}

function walletName(address: string): string | null {
  return DEMO_ACCOUNTS.find((a) => sameAddress(a.address, address))?.label ?? null;
}

export function PortfolioPage() {
  const { t } = useI18n();
  const f = useFormat();
  const session = useSession();
  const group = useWalletGroup();
  const positions = usePositions();
  const allowances = useOpenAllowances();
  const pending = usePendingTransfers();
  const { declaredPrices, openPriceDialog } = useDemoState();

  if (!session.address) {
    return (
      <>
        <PageHeader title={t.portfolio.title} subtitle={t.portfolio.subtitle} />
        <EmptyState
          icon="wallet"
          title={t.portfolio.connectTitle}
          body={t.portfolio.connectBody}
          action={<Button onClick={session.openConnect}>{t.account.connect}</Button>}
        />
      </>
    );
  }

  // A declared price turns the received shares into shares with a known cost.
  const transfers = pendingTransfersOf(group.map((w) => w.address));
  const rows: Row[] = positions.map((p) => {
    let declaredCost = 0;
    let declaredShares = 0;
    for (const tr of transfers) {
      const price = declaredPrices.get(tr.id);
      if (price !== undefined && sameAddress(tr.wallet, p.wallet) && tr.index.address === p.index.address) {
        declaredCost += price * tr.shares;
        declaredShares += tr.shares;
      }
    }
    const unknown = Math.max(0, p.unknownCostShares - declaredShares);
    const cost = p.cost === null && declaredShares === 0 ? null : (p.cost ?? 0) + declaredCost;
    const value = p.shares * p.index.navPerShare;
    const knownValue = (p.shares - unknown) * p.index.navPerShare;
    return { ...p, unknownCostShares: unknown, cost, value, pnl: cost === null ? null : knownValue - cost };
  });

  const totalValue = rows.reduce((s, r) => s + r.value, 0);
  const totalCost = rows.reduce((s, r) => s + (r.cost ?? 0), 0);
  const totalPnl = rows.reduce((s, r) => s + (r.pnl ?? 0), 0);
  const partial = rows.some((r) => r.unknownCostShares > 0);
  const hidden = <span className="text-navy-300">{t.portfolio.hidden}</span>;

  const columns: Column<Row>[] = [
    {
      key: "index",
      header: t.portfolio.index,
      hideOnMobile: true,
      cell: (r) => (
        <Link to={`/index/${r.index.address}`} className="flex items-center gap-2 font-semibold text-navy-900 hover:text-brand-600">
          <AssetPair index={r.index} size="sm" />
          {r.index.symbol}
        </Link>
      ),
    },
    { key: "wallet", header: t.portfolio.wallet, cell: (r) => <Address address={r.wallet} name={walletName(r.wallet)} copy={false} /> },
    { key: "shares", header: t.portfolio.shares, align: "right", cell: (r) => f.number(r.shares, 4) },
    { key: "value", header: t.portfolio.value, align: "right", cell: (r) => <span className="font-semibold">{f.usd(r.value)}</span> },
    { key: "cost", header: t.portfolio.cost, align: "right", cell: (r) => (!session.signedIn ? hidden : r.cost === null ? "-" : f.usd(r.cost)) },
    {
      key: "pnl",
      header: t.portfolio.pnl,
      align: "right",
      cell: (r) =>
        !session.signedIn ? (
          hidden
        ) : (
          <span className="inline-flex flex-col items-end gap-1">
            {r.pnl === null ? "-" : <UsdChange value={r.pnl} />}
            {r.unknownCostShares > 0 && (
              <Badge tone="amber" className="cursor-help">
                <span title={t.portfolio.partialPnlHint(f.number(r.unknownCostShares, 4))}>{t.portfolio.partialPnl}</span>
              </Badge>
            )}
          </span>
        ),
    },
  ];

  const byWallet = group.map((w) => {
    const own = rows.filter((r) => sameAddress(r.wallet, w.address));
    return {
      address: w.address,
      value: own.reduce((s, r) => s + r.value, 0),
      pnl: own.reduce((s, r) => s + (r.pnl ?? 0), 0),
      partial: own.some((r) => r.unknownCostShares > 0),
    };
  });

  const pendingColumns: Column<PendingTransfer>[] = [
    { key: "index", header: t.portfolio.index, cell: (p) => <span className="font-semibold">{p.index.symbol}</span> },
    { key: "from", header: t.portfolio.from, cell: (p) => <Address address={p.from} copy={false} /> },
    { key: "to", header: t.portfolio.wallet, cell: (p) => <Address address={p.wallet} name={walletName(p.wallet)} copy={false} /> },
    { key: "shares", header: t.portfolio.shares, align: "right", cell: (p) => f.number(p.shares, 4) },
    { key: "received", header: t.portfolio.received, align: "right", cell: (p) => f.date(new Date(p.receivedAt)) },
    {
      key: "action",
      header: t.common.actions,
      align: "right",
      cell: (p) => (
        <Button size="sm" variant="warning" onClick={() => openPriceDialog(p.id)}>
          {t.portfolio.setPrice}
        </Button>
      ),
    },
  ];

  return (
    <>
      <PageHeader title={t.portfolio.title} subtitle={t.portfolio.subtitle} />

      <div className="mb-6 flex flex-col gap-3">
        {allowances.length > 0 && (
          <Banner
            title={t.portfolio.allowanceBanner(allowances.length)}
            action={
              <ButtonLink to="/portfolio/allowances" variant="warning" size="sm">
                {t.portfolio.reviewAllowances}
              </ButtonLink>
            }
          >
            {t.portfolio.allowanceBannerHint}
          </Banner>
        )}
        {!session.signedIn && (
          <Banner
            tone="brand"
            icon="signature"
            title={t.portfolio.signInTitle}
            action={
              <Button size="sm" onClick={session.openSignIn}>
                {t.account.signIn}
              </Button>
            }
          >
            {t.portfolio.signInBody}
          </Banner>
        )}
      </div>

      <div className="mb-6 grid grid-cols-2 gap-3 sm:grid-cols-3">
        <div className="col-span-2 sm:col-span-1">
          <StatTile label={t.portfolio.totalValue} value={f.usd(totalValue)} />
        </div>
        <StatTile label={t.portfolio.totalCost} value={session.signedIn ? f.usd(totalCost) : hidden} />
        <StatTile
          label={t.portfolio.pnl}
          value={session.signedIn ? <UsdChange value={totalPnl} /> : hidden}
          hint={
            session.signedIn && (
              <span className="flex flex-wrap items-center gap-2">
                {totalCost > 0 && <Change value={totalPnl / totalCost} />}
                {partial && <Badge tone="amber">{t.portfolio.partialPnl}</Badge>}
              </span>
            )
          }
        />
      </div>

      {rows.length === 0 ? (
        <EmptyState icon="wallet" title={t.portfolio.noPositions} action={<ButtonLink to="/">{t.portfolio.browseIndexes}</ButtonLink>} />
      ) : (
        <div className="flex flex-col gap-6">
          <Card>
            <CardHeader title={t.portfolio.positions} />
            <ResponsiveTable
              columns={columns}
              rows={rows}
              rowKey={(r) => `${r.wallet}-${r.index.address}`}
              mobileTitle={(r) => (
                <Link to={`/index/${r.index.address}`} className="flex items-center gap-2 font-semibold">
                  <AssetPair index={r.index} size="sm" /> {r.index.name}
                </Link>
              )}
            />
          </Card>

          {session.signedIn && group.length > 1 && (
            <Card>
              <CardHeader title={t.portfolio.wallet} subtitle={t.wallets.subtitle} />
              <ul className="divide-y divide-navy-100">
                {byWallet.map((w) => (
                  <li key={w.address} className="flex flex-wrap items-center justify-between gap-2 py-3">
                    <Address address={w.address} name={walletName(w.address)} />
                    <span className="flex items-center gap-4 text-sm tabular-nums">
                      <span>{f.usd(w.value)}</span>
                      <UsdChange value={w.pnl} className="min-w-20 text-right" />
                    </span>
                  </li>
                ))}
                <li className="flex flex-wrap items-center justify-between gap-2 py-3 font-semibold">
                  <span className="flex items-center gap-2">
                    {t.portfolio.groupTotal}
                    {partial && <Badge tone="amber">{t.portfolio.partialPnl}</Badge>}
                  </span>
                  <span className="flex items-center gap-4 text-sm tabular-nums">
                    <span>{f.usd(totalValue)}</span>
                    <UsdChange value={totalPnl} className="min-w-20 text-right" />
                  </span>
                </li>
              </ul>
            </Card>
          )}

          {session.signedIn && pending.length > 0 && (
            <Card>
              <CardHeader title={t.portfolio.pendingPrices} subtitle={t.portfolio.pendingPricesHint} />
              <ResponsiveTable columns={pendingColumns} rows={pending} rowKey={(p) => p.id} />
            </Card>
          )}
        </div>
      )}
    </>
  );
}
