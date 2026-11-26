import { useNavigate } from "react-router";
import { Button } from "../components/ui/Button";
import { Card } from "../components/ui/Card";
import { EmptyState } from "../components/ui/EmptyState";
import { PageHeader } from "../components/ui/PageHeader";
import { NotificationItem } from "../features/notifications/NotificationItem";
import { useNotifications } from "../features/personal";
import { useI18n } from "../i18n/context";
import { useDemoState } from "../session/demo-state";
import { useSession } from "../session/context";

export function NotificationsPage() {
  const { t } = useI18n();
  const session = useSession();
  const navigate = useNavigate();
  const { items, unread } = useNotifications();
  const { markRead } = useDemoState();

  if (!session.signedIn) {
    return (
      <>
        <PageHeader title={t.notifications.title} />
        <EmptyState
          icon="bell"
          title={t.notifications.signInRequired}
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

  return (
    <>
      <PageHeader
        title={t.notifications.title}
        subtitle={unread > 0 ? t.notifications.unread(unread) : undefined}
        actions={
          unread > 0 && (
            <Button variant="secondary" onClick={() => markRead(items.map((n) => n.id))}>
              {t.notifications.markAllRead}
            </Button>
          )
        }
      />
      {items.length === 0 ? (
        <EmptyState icon="bell" title={t.notifications.empty} />
      ) : (
        <Card padded={false} className="overflow-hidden">
          <ul className="divide-y divide-navy-100">
            {items.map((n) => (
              <li key={n.id}>
                <NotificationItem notification={n} onNavigate={(to) => void navigate(to)} />
              </li>
            ))}
          </ul>
        </Card>
      )}
    </>
  );
}
