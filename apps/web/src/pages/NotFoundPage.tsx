import { ButtonLink } from "../components/ui/Button";
import { EmptyState } from "../components/ui/EmptyState";
import { useI18n } from "../i18n/context";

export function NotFoundPage() {
  const { t } = useI18n();
  return (
    <div className="mx-auto max-w-xl py-10">
      <EmptyState icon="search" title={t.notFound.title} body={t.notFound.body} action={<ButtonLink to="/">{t.notFound.home}</ButtonLink>} />
    </div>
  );
}
