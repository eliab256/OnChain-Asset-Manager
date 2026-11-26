import { useId, useMemo, useState, type PointerEvent } from "react";
import { useFormat } from "../../lib/format";
import type { PricePoint } from "../../mock/market";

export interface Series {
  id: string;
  label: string;
  points: PricePoint[];
  /** Stroke colour class, e.g. "stroke-brand-600". */
  stroke: string;
  /** Matching dot colour for legend and tooltip, e.g. "bg-brand-600". */
  dot: string;
  /** Fills the area under the line (first series only looks good). */
  area?: boolean;
}

interface Props {
  series: Series[];
  formatValue: (v: number) => string;
  height?: string;
  /** Shows a dashed line at this value (for example 100 for rebased series). */
  baseline?: number;
}

const W = 1000;
const H = 300;
const PAD = 12;

/**
 * Responsive SVG line chart. The SVG stretches to the container; axis labels and the
 * tooltip are HTML, so text never gets distorted.
 */
export function LineChart({ series, formatValue, height = "h-64 sm:h-80", baseline }: Props) {
  const f = useFormat();
  const gradientId = useId();
  const [hover, setHover] = useState<number | null>(null);

  const { min, max, length, times } = useMemo(() => {
    const values = series.flatMap((s) => s.points.map((p) => p.v));
    if (baseline !== undefined) values.push(baseline);
    const lo = Math.min(...values);
    const hi = Math.max(...values);
    const pad = (hi - lo) * 0.08 || 1;
    const first = series[0]?.points ?? [];
    return { min: lo - pad, max: hi + pad, length: first.length, times: first.map((p) => p.t) };
  }, [series, baseline]);

  const x = (i: number) => (length <= 1 ? 0 : (i / (length - 1)) * W);
  const y = (v: number) => PAD + (1 - (v - min) / (max - min)) * (H - 2 * PAD);

  const paths = series.map((s) => s.points.map((p, i) => `${i === 0 ? "M" : "L"}${x(i).toFixed(1)},${y(p.v).toFixed(1)}`).join(""));

  const ticks = [0, 1, 2, 3].map((k) => min + ((max - min) * (k + 0.5)) / 4);
  const dateTicks = length > 1 ? [0, 1, 2, 3].map((k) => Math.round((k / 3) * (length - 1))) : [];

  const onMove = (e: PointerEvent<HTMLDivElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    const ratio = Math.min(1, Math.max(0, (e.clientX - rect.left) / rect.width));
    setHover(Math.round(ratio * (length - 1)));
  };

  const hoverLeft = hover === null ? 0 : (x(hover) / W) * 100;

  return (
    <div>
      {series.length > 1 && (
        <ul className="mb-3 flex flex-wrap gap-4 text-sm">
          {series.map((s) => (
            <li key={s.id} className="flex items-center gap-2 text-navy-700">
              <span className={`size-2.5 rounded-full ${s.dot}`} />
              {s.label}
            </li>
          ))}
        </ul>
      )}
      <div className={`relative ${height}`}>
        <div className="pointer-events-none absolute inset-0">
          {ticks.map((v) => (
            <div key={v} className="absolute right-0 left-0 border-t border-navy-100" style={{ top: `${(y(v) / H) * 100}%` }}>
              <span className="absolute -top-2 right-0 text-[11px] leading-none text-navy-500 tabular-nums">{formatValue(v)}</span>
            </div>
          ))}
        </div>
        <div className="absolute inset-y-0 right-16 left-0 touch-none" onPointerMove={onMove} onPointerLeave={() => setHover(null)} onPointerDown={onMove}>
          <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none" className="size-full overflow-visible">
            <defs>
              <linearGradient id={gradientId} x1="0" x2="0" y1="0" y2="1">
                <stop offset="0%" style={{ stopColor: "var(--color-brand-600)" }} stopOpacity="0.18" />
                <stop offset="100%" style={{ stopColor: "var(--color-brand-600)" }} stopOpacity="0" />
              </linearGradient>
            </defs>
            {baseline !== undefined && (
              <line x1={0} x2={W} y1={y(baseline)} y2={y(baseline)} className="stroke-navy-300" strokeDasharray="6 6" vectorEffect="non-scaling-stroke" />
            )}
            {series.map((s, i) =>
              s.area ? <path key={`${s.id}-area`} d={`${paths[i] ?? ""}L${W},${H}L0,${H}Z`} fill={`url(#${gradientId})`} /> : null,
            )}
            {series.map((s, i) => (
              <path key={s.id} d={paths[i]} fill="none" className={s.stroke} strokeWidth={2} vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
            ))}
          </svg>
          {hover !== null && (
            <>
              <div className="pointer-events-none absolute top-0 bottom-0 w-px bg-navy-300" style={{ left: `${hoverLeft}%` }} />
              <div
                className="pointer-events-none absolute top-2 z-10 min-w-36 rounded-lg bg-navy-900 px-3 py-2 text-xs text-white shadow-lg"
                style={hoverLeft > 60 ? { right: `${100 - hoverLeft}%`, marginRight: 8 } : { left: `${hoverLeft}%`, marginLeft: 8 }}
              >
                <div className="mb-1 text-navy-300">{f.date(new Date(times[hover] ?? 0))}</div>
                {series.map((s) => (
                  <div key={s.id} className="flex items-center justify-between gap-3">
                    <span className="flex items-center gap-1.5">
                      <span className={`size-2 rounded-full ${s.dot}`} />
                      {s.label}
                    </span>
                    <span className="font-semibold tabular-nums">{formatValue(s.points[hover]?.v ?? 0)}</span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      </div>
      <div className="relative mt-2 mr-16 h-4 text-[11px] text-navy-500">
        {dateTicks.map((i, k) => (
          <span
            key={i}
            className="absolute"
            style={k === 0 ? { left: 0 } : k === dateTicks.length - 1 ? { right: 0 } : { left: `${(x(i) / W) * 100}%`, transform: "translateX(-50%)" }}
          >
            {f.shortDate(new Date(times[i] ?? 0))}
          </span>
        ))}
      </div>
    </div>
  );
}
