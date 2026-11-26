import { cx } from "./cx";

interface TabsProps<T extends string> {
  items: { id: T; label: string }[];
  value: T;
  onChange: (id: T) => void;
  label: string;
}

/** Underlined tabs; they scroll horizontally on narrow screens. */
export function Tabs<T extends string>({ items, value, onChange, label }: TabsProps<T>) {
  return (
    <div role="tablist" aria-label={label} className="-mx-4 flex gap-1 overflow-x-auto border-b border-navy-100 px-4 sm:mx-0 sm:px-0">
      {items.map((item) => (
        <button
          key={item.id}
          type="button"
          role="tab"
          aria-selected={item.id === value}
          onClick={() => onChange(item.id)}
          className={cx(
            "-mb-px border-b-2 px-3 py-2.5 text-sm font-semibold whitespace-nowrap transition-colors",
            item.id === value ? "border-brand-600 text-brand-700" : "border-transparent text-navy-500 hover:text-navy-900",
          )}
        >
          {item.label}
        </button>
      ))}
    </div>
  );
}

interface SegmentedProps<T extends string> {
  items: { id: T; label: string }[];
  value: T;
  onChange: (id: T) => void;
  label: string;
  block?: boolean;
}

/** Pill-shaped segmented control for short choices (periods, buy/sell, slippage). */
export function Segmented<T extends string>({ items, value, onChange, label, block = false }: SegmentedProps<T>) {
  return (
    <div role="radiogroup" aria-label={label} className={cx("inline-flex rounded-lg bg-navy-100 p-1", block && "flex w-full")}>
      {items.map((item) => (
        <button
          key={item.id}
          type="button"
          role="radio"
          aria-checked={item.id === value}
          onClick={() => onChange(item.id)}
          className={cx(
            "rounded-md px-3 py-1.5 text-sm font-semibold transition-colors",
            block && "flex-1",
            item.id === value ? "bg-white text-navy-900 shadow-sm" : "text-navy-500 hover:text-navy-900",
          )}
        >
          {item.label}
        </button>
      ))}
    </div>
  );
}
