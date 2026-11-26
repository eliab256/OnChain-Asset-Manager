import type { ReactNode } from "react";
import { cx } from "./cx";

export interface Column<T> {
  key: string;
  header: ReactNode;
  cell: (row: T) => ReactNode;
  align?: "left" | "right";
  /** Hidden in the mobile card view (for example a column already used as the card title). */
  hideOnMobile?: boolean;
  /** Takes the whole card width on mobile (bars, long values). */
  mobileFull?: boolean;
}

interface Props<T> {
  columns: Column<T>[];
  rows: T[];
  rowKey: (row: T) => string;
  /** Title of each mobile card. */
  mobileTitle?: (row: T) => ReactNode;
  rowClassName?: (row: T) => string | undefined;
  onRowClick?: (row: T) => void;
  footer?: ReactNode;
}

/** A table from `md` up, a list of cards below it. */
export function ResponsiveTable<T>({ columns, rows, rowKey, mobileTitle, rowClassName, onRowClick, footer }: Props<T>) {
  return (
    <>
      <div className="hidden overflow-x-auto md:block">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-navy-100 text-xs tracking-wide text-navy-500 uppercase">
              {columns.map((c) => (
                <th key={c.key} className={cx("px-3 py-2.5 font-medium whitespace-nowrap", c.align === "right" ? "text-right" : "text-left")}>
                  {c.header}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr
                key={rowKey(row)}
                onClick={onRowClick ? () => onRowClick(row) : undefined}
                className={cx("border-b border-navy-100 last:border-0", onRowClick && "cursor-pointer hover:bg-navy-50", rowClassName?.(row))}
              >
                {columns.map((c) => (
                  <td key={c.key} className={cx("px-3 py-3 align-middle", c.align === "right" && "text-right tabular-nums")}>
                    {c.cell(row)}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
          {footer && <tfoot>{footer}</tfoot>}
        </table>
      </div>

      <ul className="flex flex-col gap-3 md:hidden">
        {rows.map((row) => (
          <li
            key={rowKey(row)}
            onClick={onRowClick ? () => onRowClick(row) : undefined}
            className={cx("rounded-xl border border-navy-100 bg-white p-4", onRowClick && "cursor-pointer active:bg-navy-50", rowClassName?.(row))}
          >
            {mobileTitle && <div className="mb-3">{mobileTitle(row)}</div>}
            <dl className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
              {columns
                .filter((c) => !c.hideOnMobile)
                .map((c) => (
                  <div key={c.key} className={cx("min-w-0", c.mobileFull && "col-span-2")}>
                    <dt className="text-xs text-navy-500">{c.header}</dt>
                    <dd className={cx("mt-0.5 tabular-nums", !c.mobileFull && "truncate")}>{c.cell(row)}</dd>
                  </div>
                ))}
            </dl>
          </li>
        ))}
      </ul>
    </>
  );
}
