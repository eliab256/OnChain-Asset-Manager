import { useState } from "react";
import { useI18n } from "../../i18n/context";
import { shortAddress } from "../../lib/format";
import { Icon } from "./Icon";
import { cx } from "./cx";

/** Shortened address in monospace, with an optional name and a copy button. */
export function Address({ address, name, copy = true, className }: { address: string; name?: string | null; copy?: boolean; className?: string }) {
  const { t } = useI18n();
  const [copied, setCopied] = useState(false);

  const onCopy = () => {
    navigator.clipboard
      .writeText(address)
      .then(() => {
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1500);
      })
      .catch(() => undefined);
  };

  return (
    <span className={cx("inline-flex min-w-0 items-center gap-1.5", className)} title={address}>
      {name && <span className="truncate font-medium text-navy-900">{name}</span>}
      <span className={cx("font-mono text-xs", name ? "text-navy-500" : "text-navy-700")}>{shortAddress(address)}</span>
      {copy && (
        <button
          type="button"
          onClick={onCopy}
          className="rounded p-0.5 text-navy-300 hover:text-brand-600"
          aria-label={copied ? t.common.copied : t.common.copy}
        >
          <Icon name={copied ? "check" : "copy"} className="size-3.5" />
        </button>
      )}
    </span>
  );
}
