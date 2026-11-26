import { ASSETS, type IndexInfo } from "../../mock/market";

/** Two overlapping coin badges with the tickers of an index. */
export function AssetPair({ index, size = "md" }: { index: IndexInfo; size?: "sm" | "md" | "lg" }) {
  const [a0, a1] = index.assets;
  const box = size === "lg" ? "size-12 text-[11px]" : size === "sm" ? "size-8 text-[8px]" : "size-10 text-[9px]";
  return (
    <span className="flex shrink-0 -space-x-1.5">
      <span className={`flex items-center justify-center rounded-full bg-brand-600 font-bold tracking-tighter text-white ring-2 ring-white ${box}`}>{ASSETS[a0].ticker}</span>
      <span className={`flex items-center justify-center rounded-full bg-amber-500 font-bold tracking-tighter text-navy-900 ring-2 ring-white ${box}`}>{ASSETS[a1].ticker}</span>
    </span>
  );
}
