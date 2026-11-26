import { useSearchParams } from "react-router";
import { Badge } from "../components/ui/Badge";
import { PageHeader } from "../components/ui/PageHeader";
import { Tabs } from "../components/ui/Tabs";
import { MultisigTab } from "../features/admin/MultisigTab";
import { FeedsTab, TimelockTab, WeightsTab } from "../features/admin/ReadOnlyTabs";
import { useI18n } from "../i18n/context";

const TABS = ["multisig", "weights", "timelock", "feeds"] as const;
type Tab = (typeof TABS)[number];

function isTab(value: string | null): value is Tab {
  return TABS.some((t) => t === value);
}

// Mounted only inside <RequireMultisigOwner>.
export function AdminPage() {
  const { t } = useI18n();
  const [params, setParams] = useSearchParams();
  const raw = params.get("tab");
  const tab: Tab = isTab(raw) ? raw : "multisig";

  return (
    <>
      <PageHeader title={t.admin.title} subtitle={t.admin.subtitle} actions={<Badge tone="amber">{t.account.multisigOwner}</Badge>} />
      <div className="mb-6">
        <Tabs
          label={t.admin.title}
          value={tab}
          onChange={(next) => setParams({ tab: next }, { replace: true })}
          items={TABS.map((id) => ({ id, label: t.admin.tabs[id] }))}
        />
      </div>
      {tab === "multisig" && <MultisigTab />}
      {tab === "weights" && <WeightsTab />}
      {tab === "timelock" && <TimelockTab />}
      {tab === "feeds" && <FeedsTab />}
    </>
  );
}
