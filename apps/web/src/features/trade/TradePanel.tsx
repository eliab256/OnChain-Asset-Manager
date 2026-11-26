import { useState } from "react";
import { Button } from "../../components/ui/Button";
import { Card } from "../../components/ui/Card";
import { Icon } from "../../components/ui/Icon";
import { Segmented } from "../../components/ui/Tabs";
import { cx } from "../../components/ui/cx";
import { useI18n } from "../../i18n/context";
import { useFormat } from "../../lib/format";
import { positionsOf } from "../../mock/accounts";
import type { IndexInfo } from "../../mock/market";
import { useSession } from "../../session/context";

type Side = "buy" | "sell";
type Slippage = "0.5" | "1" | "2";

const DEMO_USDC_BALANCE = 25_000;

export function TradePanel({ index }: { index: IndexInfo }) {
  const { t } = useI18n();
  const f = useFormat();
  const session = useSession();
  const [side, setSide] = useState<Side>("buy");
  const [amount, setAmount] = useState("");
  const [slippage, setSlippage] = useState<Slippage>("1");
  const [permit, setPermit] = useState(true);
  const [notice, setNotice] = useState(false);

  const sharesOwned = session.address ? (positionsOf(session.address).find((p) => p.index.address === index.address)?.shares ?? 0) : 0;
  const balance = side === "buy" ? DEMO_USDC_BALANCE : sharesOwned;
  const inUnit = side === "buy" ? "USDC" : index.symbol;
  const outUnit = side === "buy" ? index.symbol : "USDC";

  const value = Number(amount.replace(",", "."));
  const valid = amount.trim() !== "" && Number.isFinite(value) && value > 0;
  // Swap cost estimate: 0.3% pool fee on the asset leg.
  const out = !valid ? 0 : side === "buy" ? (value / index.navPerShare) * 0.997 : value * index.navPerShare * 0.997;
  const min = out * (1 - Number(slippage) / 100);
  const insufficient = valid && !!session.address && value > balance;

  const steps =
    side === "buy"
      ? [permit ? t.trade.stepPermit("USDC") : t.trade.stepApprove("USDC"), t.trade.stepBuy]
      : [permit ? t.trade.stepPermit(index.symbol) : t.trade.stepApprove(index.symbol), t.trade.stepSell];

  const cta = !session.address
    ? t.trade.connectToTrade
    : !valid
      ? t.trade.enterAmount
      : insufficient
        ? t.trade.insufficient
        : side === "buy"
          ? t.trade.buy
          : t.trade.sell;

  const switchSide = (next: Side) => {
    setSide(next);
    setAmount("");
    setNotice(false);
  };

  return (
    <Card className="lg:sticky lg:top-24">
      <Segmented
        label={`${t.trade.buy} / ${t.trade.sell}`}
        block
        value={side}
        onChange={switchSide}
        items={[
          { id: "buy", label: t.trade.buy },
          { id: "sell", label: t.trade.sell },
        ]}
      />

      <div className="mt-5">
        <div className="mb-1.5 flex items-center justify-between text-xs text-navy-500">
          <span>{side === "buy" ? t.trade.youPay : t.trade.youSell}</span>
          {session.address && (
            <button type="button" className="font-semibold text-brand-600 hover:underline" onClick={() => setAmount(String(balance))}>
              {t.trade.balance(`${f.number(balance, 4)} ${inUnit}`)} · {t.common.max}
            </button>
          )}
        </div>
        <label className="relative block">
          <span className="sr-only">{side === "buy" ? t.trade.youPay : t.trade.youSell}</span>
          <input
            inputMode="decimal"
            value={amount}
            onChange={(e) => {
              setAmount(e.target.value);
              setNotice(false);
            }}
            placeholder="0.00"
            className={cx("w-full py-3 pr-24 text-xl font-semibold tabular-nums", insufficient && "border-loss-600")}
          />
          <span className="absolute top-1/2 right-4 -translate-y-1/2 text-sm font-semibold text-navy-500">{inUnit}</span>
        </label>
      </div>

      <div className="my-3 flex justify-center text-navy-300">
        <Icon name="chevronDown" />
      </div>

      <div className="rounded-xl bg-navy-50 p-4">
        <div className="text-xs text-navy-500">{t.trade.youReceive}</div>
        <div className="mt-1 flex items-baseline justify-between gap-2">
          <span className="text-xl font-semibold text-navy-900 tabular-nums">{f.number(out, side === "buy" ? 4 : 2)}</span>
          <span className="text-sm font-semibold text-navy-500">{outUnit}</span>
        </div>
        <div className="mt-2 flex justify-between text-xs text-navy-500">
          <span>{t.trade.minReceived}</span>
          <span className="tabular-nums">
            {f.number(min, side === "buy" ? 4 : 2)} {outUnit}
          </span>
        </div>
        <div className="mt-1 text-xs text-navy-500">{t.trade.rate("USDC", f.number(index.navPerShare, 4))}</div>
      </div>

      <div className="mt-4 flex items-center justify-between gap-3">
        <span className="text-sm text-navy-700">{t.trade.slippage}</span>
        <Segmented
          label={t.trade.slippage}
          value={slippage}
          onChange={setSlippage}
          items={[
            { id: "0.5", label: "0.5%" },
            { id: "1", label: "1%" },
            { id: "2", label: "2%" },
          ]}
        />
      </div>

      <label className="mt-4 flex cursor-pointer items-start gap-3">
        <input type="checkbox" checked={permit} onChange={(e) => setPermit(e.target.checked)} className="mt-0.5 size-4 accent-brand-600" />
        <span>
          <span className="block text-sm font-semibold text-navy-900">{t.trade.usePermit}</span>
          <span className="block text-xs text-navy-500">{t.trade.usePermitHint}</span>
        </span>
      </label>

      <div className="mt-4">
        <div className="mb-2 text-xs font-medium tracking-wide text-navy-500 uppercase">{t.trade.steps}</div>
        <ol className="flex flex-col gap-2">
          {steps.map((s, i) => (
            <li key={s} className="flex items-center gap-2 text-sm text-navy-700">
              <span className="flex size-5 items-center justify-center rounded-full bg-brand-100 text-[11px] font-bold text-brand-700">{i + 1}</span>
              {s}
            </li>
          ))}
        </ol>
      </div>

      <Button
        block
        size="lg"
        className="mt-5"
        disabled={!!session.address && (!valid || insufficient)}
        onClick={() => (session.address ? setNotice(true) : session.openConnect())}
      >
        {cta}
      </Button>
      {notice && <p className="mt-3 rounded-lg bg-amber-50 p-3 text-xs text-amber-700">{t.common.demoNotice}</p>}
      <p className="mt-3 text-xs text-navy-500">{t.trade.oracleNote}</p>
    </Card>
  );
}
