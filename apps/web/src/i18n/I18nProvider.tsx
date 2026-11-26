import { useEffect, useMemo, useState, type ReactNode } from "react";
import { I18nContext, isLocale, type Locale } from "./context";
import { en } from "./locales/en";
import { es } from "./locales/es";
import { it } from "./locales/it";
import { readStorage, writeStorage } from "../lib/storage";

const DICTIONARIES = { en, es, it } as const;
const STORAGE_KEY = "oam.locale";

// English is the default; the choice is remembered per browser.
function initialLocale(): Locale {
  const stored = readStorage(STORAGE_KEY);
  return isLocale(stored) ? stored : "en";
}

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocale] = useState<Locale>(initialLocale);

  useEffect(() => {
    document.documentElement.lang = locale;
    writeStorage(STORAGE_KEY, locale);
  }, [locale]);

  const value = useMemo(() => ({ locale, setLocale, t: DICTIONARIES[locale] }), [locale]);
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}
