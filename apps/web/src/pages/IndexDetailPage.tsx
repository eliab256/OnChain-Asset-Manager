import { useState } from "react";
import { Link, useParams } from "react-router";
import { AssetPair } from "../components/charts/AssetPair";
import { LineChart } from "../components/charts/LineChart";
import { WeightBar } from "../components/charts/WeightBar";
import { Address } from "../components/ui/Address";
import { Badge } from "../components/ui/Badge";
import { ButtonLink } from "../components/ui/Button";
import { Card, CardHeader } from "../components/ui/Card";
import { Change } from "../components/ui/Change";
import { Icon } from "../components/ui/Icon";
import { ResponsiveTable, type Column } from "../components/ui/ResponsiveTable";
import { StatTile } from "../components/ui/StatTile";
import { Segmented } from "../components/ui/Tabs";
import { TradePanel } from "../features/trade/TradePanel";
import { useI18n } from "../i18n/context";
import { useFormat } from "../lib/format";
import { PERIODS, slicePeriod, type Period } from "../lib/periods";
import { ASSETS, findIndex, latestPrice, pairLabel, type Activity } from "../mock/market";
import { NotFoundPage } from "./NotFoundPage";

export function IndexDetailPage() {
  const { address } = useParams();
  const index = findIndex(address);
  const { t } = useI18n();
  const f = useFormat();
  const [period, setPeriod] = useState<Period>("90d");

  if (!index) return <NotFoundPage />;

  const points = slicePeriod(index.history, period);
  const first = points[0]?.v ?? index.navPerShare;
  const periodChange = index.navPerShare / first - 1;

  const activityColumns: Column<Activity>[] = [
    {
      key: "type",
      header: t.common.details,
      cell: (a) => <Badge tone={a.type === "MINT" ? "brand" : a.type === "REDEEM" ? "navy" : "amber"}>{t.indexDetail.activityTypes[a.type]}</Badge>,
    },
    { key: "account", header: t.indexDetail.account, cell: (a) => <Address address={a.account} copy={false} /> },
    { key: "amount", header: t.indexDetail.amount, align: "right", cell: (a) => f.usd(a.usd) },
    { key: "time", header: t.indexDetail.time, align: "right", cell: (a) => <span className="text-navy-500">{f.dateTime(new Date(a.t))}</span> },
  ];

  return (
    <>
      <Link to="/" className="mb-4 inline-flex items-center gap-1 text-sm font-semibold text-navy-500 hover:text-brand-600">
        <Icon name="chevronRight" className="size-4 rotate-180" /> {t.nav.indexes}
      </Link>

      <header className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-4">
          <AssetPair index={index} size="lg" />
          <div className="min-w-0">
            <h1 className="text-2xl font-bold tracking-tight text-navy-900 sm:text-3xl">{index.name}</h1>
            <div className="mt-1 flex flex-wrap items-center gap-2 text-sm text-navy-500">
              <span>{index.symbol}</span>·<span>{pairLabel(index)}</span>·<Address address={index.address} />
            </div>
          </div>
        </div>
        <ButtonLink to={`/compare?index=${index.address}&asset=${index.assets[0]}`} variant="secondary">
          <Icon name="compare" className="size-4" /> {t.indexDetail.compareWith}
        </ButtonLink>
      </header>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_380px]">
        <div className="flex min-w-0 flex-col gap-6">
          <div className="grid grid-cols-2 gap-3 xl:grid-cols-4">
            <StatTile label={t.indexDetail.nav} value={f.usd(index.navPerShare)} hint={<Change value={index.change24h} />} />
            <StatTile label={t.indexDetail.tvl} value={f.usdCompact(index.tvl)} hint={`${f.number(index.supply, 0)} shares`} />
            <StatTile label={t.indexDetail.holders} value={f.number(index.holders, 0)} />
            <StatTile label={t.indexDetail.fees} value={f.bps(index.feeBps)} hint={t.indexDetail.feesValue(f.bps(index.feeBps))} />
          </div>

          <Card>
            <CardHeader
              title={t.indexDetail.history}
              subtitle={<Change value={periodChange} />}
              actions={
                <Segmented
                  label={t.compare.period}
                  value={period}
                  onChange={setPeriod}
                  items={PERIODS.map((p) => ({ id: p, label: t.compare.periods[p] }))}
                />
              }
            />
            <LineChart
              series={[{ id: "nav", label: t.indexDetail.nav, points, stroke: "stroke-brand-600", dot: "bg-brand-600", area: true }]}
              formatValue={(v) => f.usd(v)}
            />
          </Card>

          <Card>
            <CardHeader title={t.indexDetail.composition} subtitle={`${t.indexDetail.lastRebalance}: ${f.dateTime(new Date(index.lastRebalance))}`} />
            <div className="flex flex-col gap-4">
              <div>
                <div className="mb-1.5 text-xs font-medium text-navy-500">{t.indexDetail.target}</div>
                <WeightBar weights={index.targetWeights} labels={[ASSETS[index.assets[0]].ticker, ASSETS[index.assets[1]].ticker]} />
              </div>
              <div>
                <div className="mb-1.5 text-xs font-medium text-navy-500">{t.indexDetail.current}</div>
                <WeightBar weights={index.currentWeights} labels={[ASSETS[index.assets[0]].ticker, ASSETS[index.assets[1]].ticker]} />
              </div>
            </div>
            <div className="mt-6 grid gap-3 sm:grid-cols-2">
              {index.assets.map((symbol, i) => {
                const asset = ASSETS[symbol];
                const drift = ((index.currentWeights[i] ?? 0) - (index.targetWeights[i] ?? 0)) / 10_000;
                return (
                  <div key={symbol} className="rounded-xl border border-navy-100 p-4">
                    <div className="flex items-center gap-2">
                      <span className={`size-2.5 rounded-full ${i === 0 ? "bg-brand-600" : "bg-amber-500"}`} />
                      <span className="font-semibold">{asset.ticker}</span>
                      <span className="text-sm text-navy-500">{asset.name}</span>
                    </div>
                    <dl className="mt-3 grid grid-cols-2 gap-2 text-sm">
                      <dt className="text-navy-500">{t.indexDetail.price}</dt>
                      <dd className="text-right tabular-nums">{f.usd(latestPrice(symbol))}</dd>
                      <dt className="text-navy-500">{t.indexDetail.reserve}</dt>
                      <dd className="text-right tabular-nums">{f.number(index.reserves[i] ?? 0, 4)}</dd>
                      <dt className="text-navy-500">{t.indexDetail.drift}</dt>
                      <dd className={`text-right tabular-nums ${Math.abs(drift) > 0.01 ? "text-amber-700" : "text-navy-700"}`}>{f.pct(drift)}</dd>
                    </dl>
                  </div>
                );
              })}
            </div>
          </Card>

          <Card>
            <CardHeader title={t.indexDetail.activity} />
            <ResponsiveTable columns={activityColumns} rows={index.activity} rowKey={(a) => a.tx} />
          </Card>
        </div>

        <aside className="min-w-0">
          <TradePanel index={index} />
        </aside>
      </div>
    </>
  );
}
