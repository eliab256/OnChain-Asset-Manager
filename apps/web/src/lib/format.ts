import { useMemo } from "react";
import { INTL_TAGS, useI18n, type Locale } from "../i18n/context";

export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

export function shortHex(hex: string, keep = 10): string {
  return hex.length <= keep * 2 + 1 ? hex : `${hex.slice(0, keep + 2)}…${hex.slice(-keep)}`;
}

function makeFormatters(locale: Locale) {
  const tag = INTL_TAGS[locale];
  const usd = new Intl.NumberFormat(tag, { style: "currency", currency: "USD", maximumFractionDigits: 2 });
  const usdCompact = new Intl.NumberFormat(tag, {
    style: "currency",
    currency: "USD",
    notation: "compact",
    maximumFractionDigits: 2,
  });
  const date = new Intl.DateTimeFormat(tag, { dateStyle: "medium" });
  const dateTime = new Intl.DateTimeFormat(tag, { dateStyle: "medium", timeStyle: "short" });
  const shortDate = new Intl.DateTimeFormat(tag, { day: "numeric", month: "short" });

  return {
    usd: (v: number) => usd.format(v),
    usdCompact: (v: number) => usdCompact.format(v),
    number: (v: number, digits = 2) =>
      new Intl.NumberFormat(tag, { maximumFractionDigits: digits, minimumFractionDigits: 0 }).format(v),
    fixed: (v: number, digits = 2) =>
      new Intl.NumberFormat(tag, { maximumFractionDigits: digits, minimumFractionDigits: digits }).format(v),
    /** `v` is a fraction: 0.0123 → "+1.23%". */
    pct: (v: number, signed = true) =>
      new Intl.NumberFormat(tag, {
        style: "percent",
        maximumFractionDigits: 2,
        minimumFractionDigits: 2,
        signDisplay: signed ? "exceptZero" : "auto",
      }).format(v),
    /** Basis points → "60%". */
    bps: (v: number) => new Intl.NumberFormat(tag, { style: "percent", maximumFractionDigits: 2 }).format(v / 10_000),
    date: (d: Date) => date.format(d),
    dateTime: (d: Date) => dateTime.format(d),
    shortDate: (d: Date) => shortDate.format(d),
  };
}

export type Formatters = ReturnType<typeof makeFormatters>;

export function useFormat(): Formatters {
  const { locale } = useI18n();
  return useMemo(() => makeFormatters(locale), [locale]);
}
