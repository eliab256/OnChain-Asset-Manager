import { useI18n } from "../../i18n/context";

export function Footer() {
  const { t } = useI18n();
  return (
    <footer className="mt-16 border-t border-navy-100 bg-white">
      <div className="mx-auto flex max-w-7xl flex-col gap-2 px-4 py-6 text-xs text-navy-500 sm:flex-row sm:justify-between sm:px-6">
        <p>{t.footer.disclaimer}</p>
        <p>
          {t.footer.prices} · {t.common.demoData}
        </p>
      </div>
    </footer>
  );
}
