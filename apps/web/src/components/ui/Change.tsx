import { useFormat } from "../../lib/format";
import { cx } from "./cx";

/** Signed percentage: brand blue for gains, red for losses (the only use of red). */
export function Change({ value, className }: { value: number; className?: string }) {
  const f = useFormat();
  const tone = value > 0 ? "text-brand-600" : value < 0 ? "text-loss-600" : "text-navy-500";
  return <span className={cx("font-semibold tabular-nums", tone, className)}>{f.pct(value)}</span>;
}

/** Signed USD amount with the same colours. */
export function UsdChange({ value, className }: { value: number; className?: string }) {
  const f = useFormat();
  const tone = value > 0 ? "text-brand-600" : value < 0 ? "text-loss-600" : "text-navy-500";
  const sign = value > 0 ? "+" : "";
  return <span className={cx("font-semibold tabular-nums", tone, className)}>{sign + f.usd(value)}</span>;
}
