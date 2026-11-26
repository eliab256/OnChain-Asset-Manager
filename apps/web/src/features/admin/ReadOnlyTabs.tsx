import { WeightBar } from "../../components/charts/WeightBar";
import { Address } from "../../components/ui/Address";
import { Badge, type BadgeTone } from "../../components/ui/Badge";
import { Banner } from "../../components/ui/Banner";
import { Card } from "../../components/ui/Card";
import { ResponsiveTable, type Column } from "../../components/ui/ResponsiveTable";
import { useI18n } from "../../i18n/context";
import { useFormat } from "../../lib/format";
import {
  FEED_REPLACEMENTS,
  TIMELOCK_OPERATIONS,
  WEIGHT_PROPOSALS,
  type FeedReplacement,
  type FeedStatus,
  type TimelockOperation,
  type TimelockStatus,
  type WeightProposal,
  type WeightStatus,
} from "../../mock/admin";
import { ASSETS, INDEXES } from "../../mock/market";

const WEIGHT_TONE: Record<WeightStatus, BadgeTone> = {
  PENDING: "amber",
  EXECUTABLE: "brand",
  EXECUTED: "navy",
  CANCELLED: "outline",
  EXPIRED: "outline",
  OVERWRITTEN: "outline",
};

function tickers(symbol: string): [string, string] {
  const index = INDEXES.find((i) => i.symbol === symbol);
  return index ? [ASSETS[index.assets[0]].ticker, ASSETS[index.assets[1]].ticker] : ["A", "B"];
}

export function WeightsTab() {
  const { t } = useI18n();
  const f = useFormat();
  const w = t.admin.weights;
  const columns: Column<WeightProposal>[] = [
    { key: "index", header: w.index, hideOnMobile: true, cell: (p) => <span className="font-semibold">{p.indexSymbol}</span> },
    { key: "current", header: w.currentWeights, mobileFull: true, cell: (p) => <div className="min-w-32"><WeightBar weights={p.current} labels={tickers(p.indexSymbol)} /></div> },
    { key: "proposed", header: w.proposedWeights, mobileFull: true, cell: (p) => <div className="min-w-32"><WeightBar weights={p.proposed} labels={tickers(p.indexSymbol)} /></div> },
    { key: "proposedAt", header: w.proposedAt, cell: (p) => f.date(new Date(p.proposedAt)) },
    { key: "executableAt", header: w.executableAt, cell: (p) => f.dateTime(new Date(p.executableAt)) },
    { key: "status", header: t.common.status, align: "right", cell: (p) => <Badge tone={WEIGHT_TONE[p.status]}>{w.status[p.status]}</Badge> },
  ];
  return (
    <div className="flex flex-col gap-4">
      <Banner tone="navy" icon="shield" title={w.title}>
        {w.readOnly}
      </Banner>
      <Card>
        <ResponsiveTable columns={columns} rows={WEIGHT_PROPOSALS} rowKey={(p) => p.id} mobileTitle={(p) => <span className="font-semibold">{p.indexSymbol}</span>} />
      </Card>
    </div>
  );
}

const TIMELOCK_TONE: Record<TimelockStatus, BadgeTone> = { WAITING: "amber", READY: "brand", DONE: "navy", CANCELLED: "outline" };

export function TimelockTab() {
  const { t } = useI18n();
  const f = useFormat();
  const tl = t.admin.timelock;
  const columns: Column<TimelockOperation>[] = [
    { key: "id", header: tl.operation, cell: (o) => <span className="font-mono text-xs">{o.id}</span> },
    { key: "target", header: t.admin.target, hideOnMobile: true, cell: (o) => <span className="font-semibold">{o.target}</span> },
    { key: "call", header: t.admin.call, mobileFull: true, cell: (o) => <span className="font-mono text-xs break-all">{o.call}</span> },
    {
      key: "predecessor",
      header: tl.predecessor,
      cell: (o) =>
        o.predecessor ? (
          <span className="flex flex-col gap-1">
            <span className="font-mono text-xs">{o.predecessor}</span>
            {!o.predecessorDone && <Badge tone="amber">{tl.predecessorPending}</Badge>}
          </span>
        ) : (
          <span className="text-navy-300">{t.common.none}</span>
        ),
    },
    { key: "readyAt", header: tl.readyAt, cell: (o) => f.dateTime(new Date(o.readyAt)) },
    { key: "status", header: t.common.status, align: "right", cell: (o) => <Badge tone={TIMELOCK_TONE[o.status]}>{tl.status[o.status]}</Badge> },
  ];
  return (
    <div className="flex flex-col gap-4">
      <Banner tone="navy" icon="shield" title={tl.title}>
        {tl.readOnly}
      </Banner>
      <Card>
        <ResponsiveTable columns={columns} rows={TIMELOCK_OPERATIONS} rowKey={(o) => o.id} mobileTitle={(o) => <span className="font-semibold">{o.target}</span>} />
      </Card>
    </div>
  );
}

const FEED_TONE: Record<FeedStatus, BadgeTone> = { WAITING: "amber", OPEN: "brand", EXECUTED: "navy", EXPIRED: "outline" };

export function FeedsTab() {
  const { t } = useI18n();
  const f = useFormat();
  const fd = t.admin.feeds;
  const columns: Column<FeedReplacement>[] = [
    { key: "asset", header: fd.asset, hideOnMobile: true, cell: (r) => <span className="font-semibold">{r.asset}</span> },
    { key: "current", header: fd.currentFeed, cell: (r) => <Address address={r.currentFeed} copy={false} /> },
    { key: "proposed", header: fd.proposedFeed, cell: (r) => <Address address={r.proposedFeed} /> },
    { key: "delay", header: fd.maxDelay, cell: (r) => `${f.number(r.maxDelay / 60, 0)} min` },
    {
      key: "window",
      header: fd.window,
      mobileFull: true,
      cell: (r) => (
        <span className="text-xs">
          {f.dateTime(new Date(r.executableAt))} → {f.dateTime(new Date(r.windowEnd))}
        </span>
      ),
    },
    { key: "status", header: t.common.status, align: "right", cell: (r) => <Badge tone={FEED_TONE[r.status]}>{fd.status[r.status]}</Badge> },
  ];
  return (
    <div className="flex flex-col gap-4">
      <Banner tone="navy" icon="globe" title={fd.title}>
        {fd.hint}
      </Banner>
      <Card>
        <ResponsiveTable columns={columns} rows={FEED_REPLACEMENTS} rowKey={(r) => r.id} mobileTitle={(r) => <span className="font-semibold">{r.asset}</span>} />
      </Card>
    </div>
  );
}
