import type { PricePoint } from "../mock/market";

export const PERIODS = ["7d", "30d", "90d", "1y"] as const;
export type Period = (typeof PERIODS)[number];

const DAYS: Record<Period, number> = { "7d": 7, "30d": 30, "90d": 90, "1y": 365 };

export function isPeriod(value: unknown): value is Period {
  return typeof value === "string" && (PERIODS as readonly string[]).includes(value);
}

/** Last `period` days of a daily series (one point more, so 7d has 7 daily changes). */
export function slicePeriod(points: PricePoint[], period: Period): PricePoint[] {
  return points.slice(-(DAYS[period] + 1));
}
