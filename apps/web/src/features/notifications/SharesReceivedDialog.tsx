import { useState } from "react";
import { Address } from "../../components/ui/Address";
import { Button } from "../../components/ui/Button";
import { Modal } from "../../components/ui/Modal";
import { Segmented } from "../../components/ui/Tabs";
import { useI18n } from "../../i18n/context";
import { useFormat } from "../../lib/format";
import { findPendingTransfer, type PendingTransfer } from "../../mock/accounts";
import { useDemoState } from "../../session/demo-state";

// Pop-up shown on a SHARES_RECEIVED notification: the user declares what they paid.
export function SharesReceivedDialog() {
  const { priceDialog, closePriceDialog } = useDemoState();
  const transfer = findPendingTransfer(priceDialog);
  if (!transfer) return null;
  // Keyed so the form resets for each transfer.
  return <PriceForm key={transfer.id} transfer={transfer} onClose={closePriceDialog} />;
}

function PriceForm({ transfer, onClose }: { transfer: PendingTransfer; onClose: () => void }) {
  const { t } = useI18n();
  const f = useFormat();
  const { declarePrice, markRead } = useDemoState();
  const [mode, setMode] = useState<"perShare" | "total">("perShare");
  const [value, setValue] = useState("");

  const amount = Number(value.replace(",", "."));
  const valid = value.trim() !== "" && Number.isFinite(amount) && amount > 0;
  const perShare = valid ? (mode === "perShare" ? amount : amount / transfer.shares) : 0;

  const save = () => {
    declarePrice(transfer.id, perShare);
    markRead([`n-${transfer.id}`]);
    onClose();
  };

  return (
    <Modal
      open
      onClose={onClose}
      title={t.priceModal.title}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            {t.priceModal.later}
          </Button>
          <Button onClick={save} disabled={!valid}>
            {t.priceModal.save}
          </Button>
        </>
      }
    >
      <p className="text-sm text-navy-700">{t.priceModal.body}</p>
      <dl className="mt-4 grid grid-cols-1 gap-3 rounded-xl bg-navy-50 p-4 text-sm sm:grid-cols-3">
        <div>
          <dt className="text-xs text-navy-500">{t.priceModal.sender}</dt>
          <dd className="mt-0.5">
            <Address address={transfer.from} />
          </dd>
        </div>
        <div>
          <dt className="text-xs text-navy-500">{t.priceModal.index}</dt>
          <dd className="mt-0.5 font-semibold">{transfer.index.symbol}</dd>
        </div>
        <div>
          <dt className="text-xs text-navy-500">{t.priceModal.shares}</dt>
          <dd className="mt-0.5 font-semibold tabular-nums">{f.number(transfer.shares, 4)}</dd>
        </div>
      </dl>

      <div className="mt-5 flex flex-col gap-3">
        <Segmented
          label={t.priceModal.mode}
          block
          value={mode}
          onChange={setMode}
          items={[
            { id: "perShare", label: t.priceModal.perShare },
            { id: "total", label: t.priceModal.totalPaid },
          ]}
        />
        <label className="relative block">
          <span className="sr-only">{mode === "perShare" ? t.priceModal.perShare : t.priceModal.totalPaid}</span>
          <input
            inputMode="decimal"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="0.00"
            className="w-full py-3 pr-16 text-lg tabular-nums"
          />
          <span className="absolute top-1/2 right-4 -translate-y-1/2 text-sm font-semibold text-navy-500">USDC</span>
        </label>
        {valid && mode === "total" && <p className="text-sm text-navy-500">{t.priceModal.resulting(f.usd(perShare))}</p>}
      </div>
    </Modal>
  );
}
