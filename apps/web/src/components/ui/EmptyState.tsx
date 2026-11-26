import type { ReactNode } from "react";
import { Icon, type IconName } from "./Icon";

export function EmptyState({ icon, title, body, action }: { icon: IconName; title: string; body?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center rounded-2xl border border-dashed border-navy-200 bg-white px-6 py-12 text-center">
      <span className="flex size-12 items-center justify-center rounded-full bg-brand-50 text-brand-600">
        <Icon name={icon} className="size-6" />
      </span>
      <h2 className="mt-4 text-lg font-semibold text-navy-900">{title}</h2>
      {body && <p className="mt-2 max-w-md text-sm text-navy-500">{body}</p>}
      {action && <div className="mt-6">{action}</div>}
    </div>
  );
}
