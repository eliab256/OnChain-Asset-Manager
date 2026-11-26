import type { ReactNode } from "react";
import { Icon, type IconName } from "./Icon";
import { cx } from "./cx";

const TONES = {
  amber: { box: "border-amber-200 bg-amber-50", icon: "text-amber-600" },
  brand: { box: "border-brand-200 bg-brand-50", icon: "text-brand-600" },
  navy: { box: "border-navy-200 bg-navy-50", icon: "text-navy-500" },
} as const;

interface BannerProps {
  tone?: keyof typeof TONES;
  icon?: IconName;
  title: ReactNode;
  children?: ReactNode;
  action?: ReactNode;
  className?: string;
}

export function Banner({ tone = "amber", icon = "warning", title, children, action, className }: BannerProps) {
  const t = TONES[tone];
  return (
    <div className={cx("flex flex-col gap-3 rounded-xl border p-4 sm:flex-row sm:items-center", t.box, className)}>
      <div className="flex flex-1 gap-3">
        <span className={cx("mt-0.5 shrink-0", t.icon)}>
          <Icon name={icon} />
        </span>
        <div className="min-w-0">
          <p className="text-sm font-semibold text-navy-900">{title}</p>
          {children && <div className="mt-1 text-sm text-navy-700">{children}</div>}
        </div>
      </div>
      {action && <div className="shrink-0 sm:ml-auto">{action}</div>}
    </div>
  );
}
