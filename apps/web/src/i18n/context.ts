import { createContext, useContext } from "react";
import type { Messages } from "./locales/en";

export const LOCALES = ["en", "es", "it"] as const;
export type Locale = (typeof LOCALES)[number];

export const LOCALE_LABELS: Record<Locale, string> = {
  en: "English",
  es: "Español",
  it: "Italiano",
};

// BCP 47 tag used by Intl for numbers and dates.
export const INTL_TAGS: Record<Locale, string> = {
  en: "en-US",
  es: "es-ES",
  it: "it-IT",
};

export interface I18nValue {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: Messages;
}

export const I18nContext = createContext<I18nValue | null>(null);

export function useI18n(): I18nValue {
  const value = useContext(I18nContext);
  if (!value) throw new Error("useI18n must be used inside <I18nProvider>");
  return value;
}

export function isLocale(value: unknown): value is Locale {
  return typeof value === "string" && (LOCALES as readonly string[]).includes(value);
}
