import { LOCALES, LOCALE_LABELS, isLocale, useI18n } from "../../i18n/context";
import { useSession } from "../../session/context";
import { cx } from "../ui/cx";

const DARK = "border-navy-700 bg-navy-800 text-white focus:border-brand-500";

export function LanguageSelect({ className, dark = true }: { className?: string; dark?: boolean }) {
  const { locale, setLocale, t } = useI18n();
  return (
    <label className={cx("block", className)}>
      <span className="sr-only">{t.nav.language}</span>
      <select
        value={locale}
        onChange={(e) => {
          if (isLocale(e.target.value)) setLocale(e.target.value);
        }}
        className={cx("w-full py-1.5 text-sm", dark && DARK)}
      >
        {LOCALES.map((l) => (
          <option key={l} value={l}>
            {LOCALE_LABELS[l]}
          </option>
        ))}
      </select>
    </label>
  );
}

export function ChainSelect({ className, dark = true }: { className?: string; dark?: boolean }) {
  const { chain, setChain } = useSession();
  const { t } = useI18n();
  return (
    <label className={cx("block", className)}>
      <span className="sr-only">{t.nav.network}</span>
      <select
        value={chain}
        onChange={(e) => setChain(e.target.value === "fork" ? "fork" : "anvil")}
        className={cx("w-full py-1.5 text-sm", dark && DARK)}
      >
        <option value="anvil">{t.chains.anvil} · 31337</option>
        <option value="fork">{t.chains.fork} · 31338</option>
      </select>
    </label>
  );
}
