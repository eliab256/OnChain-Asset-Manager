import { Link } from "react-router";
import { Address } from "../components/ui/Address";
import { Badge } from "../components/ui/Badge";
import { Banner } from "../components/ui/Banner";
import { Button } from "../components/ui/Button";
import { Card } from "../components/ui/Card";
import { EmptyState } from "../components/ui/EmptyState";
import { Icon } from "../components/ui/Icon";
import { PageHeader } from "../components/ui/PageHeader";
import { ResponsiveTable, type Column } from "../components/ui/ResponsiveTable";
import { useOpenAllowances } from "../features/personal";
import { useI18n } from "../i18n/context";
import { useFormat } from "../lib/format";
import type { Allowance } from "../mock/accounts";
import { useDemoState } from "../session/demo-state";
import { useSession } from "../session/context";

export function AllowancesPage() {
  const { t } = useI18n();
  const f = useFormat();
  const session = useSession();
  const allowances = useOpenAllowances();
  const { revokeAllowances } = useDemoState();

  const back = (
    <Link to="/portfolio" className="mb-4 inline-flex items-center gap-1 text-sm font-semibold text-navy-500 hover:text-brand-600">
      <Icon name="chevronRight" className="size-4 rotate-180" /> {t.nav.portfolio}
    </Link>
  );

  if (!session.address) {
    return (
      <>
        {back}
        <PageHeader title={t.allowances.title} subtitle={t.allowances.subtitle} />
        <EmptyState icon="shield" title={t.allowances.connectFirst} action={<Button onClick={session.openConnect}>{t.account.connect}</Button>} />
      </>
    );
  }

  const unlimited = allowances.filter((a) => a.amount === null).length;

  const columns: Column<Allowance>[] = [
    { key: "index", header: t.allowances.index, hideOnMobile: true, cell: (a) => <span className="font-semibold">{a.index.symbol}</span> },
    { key: "spender", header: t.allowances.spender, cell: (a) => <Address address={a.spender} name={a.spenderName} /> },
    {
      key: "amount",
      header: t.allowances.amount,
      cell: (a) =>
        a.amount === null ? (
          <Badge tone="amber">
            <Icon name="warning" className="size-3" /> {t.common.unlimited}
          </Badge>
        ) : (
          <span className="tabular-nums">
            {f.number(a.amount, 4)} {a.index.symbol}
          </span>
        ),
    },
    {
      key: "date",
      header: t.allowances.lastApproval,
      cell: (a) => (
        <span className="inline-flex items-center gap-2 text-navy-500">
          {f.date(new Date(a.approvedAt))}
          <a href={`#tx-${a.tx}`} className="inline-flex items-center gap-1 text-xs font-semibold text-brand-600 hover:underline">
            {t.common.viewTx} <Icon name="external" className="size-3" />
          </a>
        </span>
      ),
    },
    {
      key: "action",
      header: t.common.actions,
      align: "right",
      cell: (a) => (
        <Button size="sm" variant="secondary" onClick={() => revokeAllowances([a.id])}>
          {t.allowances.revoke}
        </Button>
      ),
    },
  ];

  return (
    <>
      {back}
      <PageHeader
        title={t.allowances.title}
        subtitle={t.allowances.subtitle}
        actions={
          allowances.length > 1 && (
            <Button variant="warning" onClick={() => revokeAllowances(allowances.map((a) => a.id))}>
              {t.allowances.revokeAll}
            </Button>
          )
        }
      />

      {allowances.length === 0 ? (
        <EmptyState icon="check" title={t.allowances.empty} />
      ) : (
        <div className="flex flex-col gap-4">
          {unlimited > 0 && <Banner title={t.allowances.unlimitedWarning}>{t.allowances.revokeAllBatch}</Banner>}
          <Card>
            <ResponsiveTable
              columns={columns}
              rows={allowances}
              rowKey={(a) => a.id}
              mobileTitle={(a) => <span className="font-semibold">{a.index.name}</span>}
              rowClassName={(a) => (a.amount === null ? "bg-amber-50/70" : undefined)}
            />
          </Card>
        </div>
      )}
    </>
  );
}
