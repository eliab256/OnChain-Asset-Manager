import { useEffect, useId, useRef, type ReactNode } from "react";
import { useI18n } from "../../i18n/context";
import { Icon } from "./Icon";

interface ModalProps {
  open: boolean;
  onClose: () => void;
  title: ReactNode;
  children: ReactNode;
  footer?: ReactNode;
}

/** Dialog centred on desktop, a bottom sheet on phones. Escape and the backdrop close it. */
export function Modal({ open, onClose, title, children, footer }: ModalProps) {
  const { t } = useI18n();
  const titleId = useId();
  const panel = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    document.addEventListener("keydown", onKey);
    panel.current?.focus();
    return () => {
      document.body.style.overflow = previous;
      document.removeEventListener("keydown", onKey);
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-4">
      <div className="absolute inset-0 bg-navy-950/60" onClick={onClose} aria-hidden="true" />
      <div
        ref={panel}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className="relative flex max-h-[90vh] w-full flex-col rounded-t-2xl bg-white shadow-xl outline-none sm:max-w-lg sm:rounded-2xl"
      >
        <div className="flex items-center justify-between gap-4 border-b border-navy-100 px-5 py-4">
          <h2 id={titleId} className="text-lg font-semibold text-navy-900">
            {title}
          </h2>
          <button type="button" onClick={onClose} className="rounded-lg p-1 text-navy-500 hover:bg-navy-100" aria-label={t.common.close}>
            <Icon name="close" />
          </button>
        </div>
        <div className="overflow-y-auto px-5 py-4">{children}</div>
        {footer && <div className="flex flex-col-reverse gap-2 border-t border-navy-100 px-5 py-4 sm:flex-row sm:justify-end">{footer}</div>}
      </div>
    </div>
  );
}
