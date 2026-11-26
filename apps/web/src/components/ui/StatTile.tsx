import type { ReactNode } from "react";

export function StatTile({ label, value, hint }: { label: string; value: ReactNode; hint?: ReactNode }) {
  return (
    <div className="rounded-xl border border-navy-100 bg-white p-4">
      <div className="text-xs font-medium tracking-wide text-navy-500 uppercase">{label}</div>
      <div className="mt-1 text-xl font-semibold text-navy-900 tabular-nums sm:text-2xl">{value}</div>
      {hint && <div className="mt-1 text-xs text-navy-500">{hint}</div>}
    </div>
  );
}
