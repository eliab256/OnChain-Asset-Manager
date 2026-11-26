import { Button } from "../../components/ui/Button";
import { Icon, type IconName } from "../../components/ui/Icon";
import { cx } from "../../components/ui/cx";
import { useI18n } from "../../i18n/context";
import { useFormat } from "../../lib/format";
import type { AppNotification, NotificationType } from "../../mock/accounts";
import { useDemoState } from "../../session/demo-state";

const ICONS: Record<NotificationType, IconName> = {
  SHARES_RECEIVED: "wallet",
  TRADE_CONFIRMED: "check",
  REBALANCE: "compare",
  WEIGHTS_PROPOSED: "compare",
  UPGRADE_SCHEDULED: "shield",
  PRICE_FEED_PROPOSED: "globe",
};

interface Props {
  notification: AppNotification;
  compact?: boolean;
  onNavigate: (to: string) => void;
  /** Called after an inline action (for example opening the price dialog). */
  onAction?: () => void;
}

export function NotificationItem({ notification: n, compact = false, onNavigate, onAction }: Props) {
  const { t } = useI18n();
  const f = useFormat();
  const { markRead, openPriceDialog } = useDemoState();
  const needsAction = n.type === "SHARES_RECEIVED" && !n.read && !!n.pendingId;

  const open = () => {
    markRead([n.id]);
    if (n.link) onNavigate(n.link);
  };

  return (
    <div className={cx("flex gap-3 px-4 py-3", !n.read && "bg-brand-50/60")}>
      <span
        className={cx(
          "mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-full",
          needsAction ? "bg-amber-100 text-amber-700" : "bg-navy-100 text-navy-700",
        )}
      >
        <Icon name={ICONS[n.type]} className="size-4" />
      </span>
      <div className="min-w-0 flex-1">
        <button type="button" onClick={open} className="block w-full text-left" disabled={!n.link}>
          <div className="flex items-start justify-between gap-2">
            <span className="text-sm font-semibold text-navy-900">{t.notifications.types[n.type]}</span>
            {!n.read && <span className="mt-1.5 size-2 shrink-0 rounded-full bg-brand-600" aria-hidden="true" />}
          </div>
          <p className={cx("text-sm text-navy-700", compact && "line-clamp-2")}>
            {t.notifications.bodies[n.type](f.number(n.shares, 4), n.subject)}
          </p>
          <p className="mt-1 text-xs text-navy-500">{f.dateTime(new Date(n.t))}</p>
        </button>
        {needsAction && n.pendingId && (
          <Button
            size="sm"
            variant="warning"
            className="mt-2"
            onClick={() => {
              openPriceDialog(n.pendingId ?? "");
              onAction?.();
            }}
          >
            {t.portfolio.setPrice}
          </Button>
        )}
      </div>
    </div>
  );
}
