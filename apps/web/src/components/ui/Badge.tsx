import type { ReactNode } from "react";
import { cx } from "./cx";

export type BadgeTone = "brand" | "amber" | "navy" | "loss" | "outline" | "solid";

const TONES: Record<BadgeTone, string> = {
  brand: "bg-brand-100 text-brand-700",
  amber: "bg-amber-100 text-amber-700",
  navy: "bg-navy-100 text-navy-700",
  loss: "bg-loss-100 text-loss-700",
  outline: "border border-navy-200 text-navy-500",
  solid: "bg-brand-600 text-white",
};

export function Badge({ tone = "navy", children, className }: { tone?: BadgeTone; children: ReactNode; className?: string }) {
  return (
    <span className={cx("inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-semibold whitespace-nowrap", TONES[tone], className)}>
      {children}
    </span>
  );
}
