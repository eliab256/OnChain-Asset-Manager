import { useCallback, useRef, useState } from "react";
import { Link, useNavigate } from "react-router";
import { NotificationItem } from "../../features/notifications/NotificationItem";
import { useNotifications } from "../../features/personal";
import { useI18n } from "../../i18n/context";
import { useDemoState } from "../../session/demo-state";
import { Icon } from "../ui/Icon";
import { useDismiss } from "./useDismiss";

export function NotificationBell() {
  const { t } = useI18n();
  const { items, unread } = useNotifications();
  const { markRead } = useDemoState();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const close = useCallback(() => setOpen(false), []);
  useDismiss(ref, open, close);

  return (
    <div ref={ref} className="relative">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        className="relative rounded-lg p-2 text-navy-200 hover:bg-navy-800 hover:text-white"
        aria-label={`${t.nav.notifications}${unread ? ` (${t.notifications.unread(unread)})` : ""}`}
        aria-expanded={open}
      >
        <Icon name="bell" />
        {unread > 0 && (
          <span className="absolute top-1 right-1 flex min-w-4 items-center justify-center rounded-full bg-amber-500 px-1 text-[10px] font-bold text-navy-900">
            {unread}
          </span>
        )}
      </button>
      {open && (
        <div className="fixed inset-x-4 top-16 z-40 overflow-hidden rounded-2xl border border-navy-100 bg-white text-navy-900 shadow-xl sm:absolute sm:inset-x-auto sm:top-12 sm:right-0 sm:w-96">
          <div className="flex items-center justify-between border-b border-navy-100 px-4 py-3">
            <span className="font-semibold">{t.nav.notifications}</span>
            {unread > 0 && (
              <button type="button" onClick={() => markRead(items.map((n) => n.id))} className="text-xs font-semibold text-brand-600 hover:underline">
                {t.notifications.markAllRead}
              </button>
            )}
          </div>
          <ul className="max-h-96 divide-y divide-navy-100 overflow-y-auto">
            {items.length === 0 && <li className="px-4 py-6 text-center text-sm text-navy-500">{t.notifications.empty}</li>}
            {items.slice(0, 5).map((n) => (
              <li key={n.id}>
                <NotificationItem
                  notification={n}
                  compact
                  onNavigate={(to) => {
                    close();
                    void navigate(to);
                  }}
                  onAction={close}
                />
              </li>
            ))}
          </ul>
          <Link to="/notifications" onClick={close} className="block border-t border-navy-100 px-4 py-3 text-center text-sm font-semibold text-brand-600 hover:bg-navy-50">
            {t.notifications.viewAll}
          </Link>
        </div>
      )}
    </div>
  );
}
