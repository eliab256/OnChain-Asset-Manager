import { useFormat } from "../../lib/format";

/** Two-segment bar for a two-asset index: brand for asset 0, amber for asset 1. Weights in basis points. */
export function WeightBar({ weights, labels, showLegend = true }: { weights: [number, number]; labels: [string, string]; showLegend?: boolean }) {
  const f = useFormat();
  return (
    <div>
      <div className="flex h-2 overflow-hidden rounded-full bg-navy-100" role="img" aria-label={`${labels[0]} ${f.bps(weights[0])}, ${labels[1]} ${f.bps(weights[1])}`}>
        <div className="bg-brand-600" style={{ width: `${weights[0] / 100}%` }} />
        <div className="bg-amber-500" style={{ width: `${weights[1] / 100}%` }} />
      </div>
      {showLegend && (
        <div className="mt-1.5 flex justify-between gap-3 text-xs whitespace-nowrap text-navy-500">
          <span className="flex items-center gap-1">
            <span className="size-2 rounded-full bg-brand-600" />
            {labels[0]} {f.bps(weights[0])}
          </span>
          <span className="flex items-center gap-1">
            {labels[1]} {f.bps(weights[1])}
            <span className="size-2 rounded-full bg-amber-500" />
          </span>
        </div>
      )}
    </div>
  );
}
