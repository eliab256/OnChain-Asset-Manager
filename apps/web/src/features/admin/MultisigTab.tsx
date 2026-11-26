import { useState } from "react";
import { Address } from "../../components/ui/Address";
import { Badge, type BadgeTone } from "../../components/ui/Badge";
import { Button } from "../../components/ui/Button";
import { Card, CardHeader } from "../../components/ui/Card";
import { Icon } from "../../components/ui/Icon";
import { Modal } from "../../components/ui/Modal";
import { cx } from "../../components/ui/cx";
import { useI18n } from "../../i18n/context";
import { useFormat, shortHex } from "../../lib/format";
import { DEMO_ACCOUNTS, MULTISIG_OWNERS, MULTISIG_THRESHOLD, sameAddress } from "../../mock/accounts";
import { CONTRACTS, MULTISIG_PROPOSALS, PROPOSAL_ACTIONS, type ContractName, type MultisigProposal, type ProposalStatus } from "../../mock/admin";
import { useSession } from "../../session/context";

const STATUS_TONE: Record<ProposalStatus, BadgeTone> = {
  PENDING: "amber",
  READY: "brand",
  EXECUTED: "navy",
  FAILED: "loss",
};

function ownerLabel(address: string) {
  return DEMO_ACCOUNTS.find((a) => sameAddress(a.address, address))?.label ?? null;
}

export function MultisigTab() {
  const { t } = useI18n();
  const f = useFormat();
  const { address } = useSession();
  const [selectedId, setSelectedId] = useState<number | null>(MULTISIG_PROPOSALS[0]?.id ?? null);
  // Local demo state: signatures added, signatures submitted on-chain, executions.
  const [extraSigners, setExtraSigners] = useState<Record<number, string[]>>({});
  const [submitted, setSubmitted] = useState<number[]>([]);
  const [executed, setExecuted] = useState<number[]>([]);
  const [formOpen, setFormOpen] = useState(false);

  const view = (p: MultisigProposal) => {
    const signers = [...p.signers, ...(extraSigners[p.id] ?? [])];
    const onChain = p.status !== "PENDING" || submitted.includes(p.id);
    const status: ProposalStatus = executed.includes(p.id)
      ? "EXECUTED"
      : p.status === "PENDING" && onChain && signers.length >= MULTISIG_THRESHOLD
        ? "READY"
        : p.status;
    return { ...p, signers, onChain, status };
  };

  const proposals = MULTISIG_PROPOSALS.map(view);
  const selected = proposals.find((p) => p.id === selectedId) ?? null;

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader
          title={t.admin.owners}
          subtitle={t.admin.threshold(MULTISIG_THRESHOLD, MULTISIG_OWNERS.length)}
          actions={
            <Button size="sm" onClick={() => setFormOpen(true)}>
              <Icon name="plus" className="size-4" /> {t.admin.newProposal}
            </Button>
          }
        />
        <ul className="grid gap-3 sm:grid-cols-3">
          {MULTISIG_OWNERS.map((o) => (
            <li key={o} className={cx("rounded-xl border p-3", sameAddress(o, address) ? "border-brand-600 bg-brand-50" : "border-navy-100")}>
              <div className="flex items-center justify-between gap-2">
                <Address address={o} name={ownerLabel(o)} />
                {sameAddress(o, address) && <Badge tone="brand">{t.common.you}</Badge>}
              </div>
            </li>
          ))}
        </ul>
      </Card>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
        <Card padded={false} className="h-fit overflow-hidden">
          <div className="border-b border-navy-100 px-4 py-3 font-semibold sm:px-6">{t.admin.proposals}</div>
          <ul className="divide-y divide-navy-100">
            {proposals.map((p) => (
              <li key={p.id}>
                <button
                  type="button"
                  onClick={() => setSelectedId(p.id)}
                  className={cx("flex w-full flex-col gap-1.5 px-4 py-3 text-left sm:px-6", p.id === selectedId ? "bg-brand-50" : "hover:bg-navy-50")}
                >
                  <span className="flex items-center justify-between gap-2">
                    <span className="font-mono text-xs text-navy-500">#{p.id}</span>
                    <Badge tone={STATUS_TONE[p.status]}>{t.admin.proposalStatus[p.status]}</Badge>
                  </span>
                  <span className="font-semibold text-navy-900">
                    {p.target}.{p.fn}
                  </span>
                  <span className="flex items-center justify-between text-xs text-navy-500">
                    <span>{f.dateTime(new Date(p.createdAt))}</span>
                    <span>
                      {t.admin.confirmations}: {Math.min(p.signers.length, MULTISIG_OWNERS.length)}/{MULTISIG_THRESHOLD}
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </Card>

        {selected ? (
          <ProposalDetail
            proposal={selected}
            address={address}
            onSign={() => address && setExtraSigners((s) => ({ ...s, [selected.id]: [...(s[selected.id] ?? []), address] }))}
            onSubmit={() => setSubmitted((s) => [...s, selected.id])}
            onExecute={() => setExecuted((s) => [...s, selected.id])}
          />
        ) : (
          <Card>
            <p className="text-sm text-navy-500">{t.admin.selectProposal}</p>
          </Card>
        )}
      </div>

      <NewProposalDialog open={formOpen} onClose={() => setFormOpen(false)} />
    </div>
  );
}

interface DetailProps {
  proposal: MultisigProposal & { onChain: boolean };
  address: string | null;
  onSign: () => void;
  onSubmit: () => void;
  onExecute: () => void;
}

function ProposalDetail({ proposal: p, address, onSign, onSubmit, onExecute }: DetailProps) {
  const { t } = useI18n();
  const signed = p.signers.some((s) => sameAddress(s, address));
  const missing = Math.max(0, MULTISIG_THRESHOLD - p.signers.length);
  const done = p.status === "EXECUTED";

  // Rule from front-end-ideas.md: Execute is enabled only when the eth_call simulation passes.
  const blocker = missing > 0 ? t.admin.needMoreSignatures(missing) : p.simulationError ? t.admin.simulationFailed(p.simulationError) : null;

  return (
    <Card className="min-w-0">
      <CardHeader
        title={
          <span className="flex flex-wrap items-center gap-2">
            #{p.id} {p.target}.{p.fn}
            <Badge tone={STATUS_TONE[p.status]}>{t.admin.proposalStatus[p.status]}</Badge>
          </span>
        }
        subtitle={<Address address={CONTRACTS[p.target]} />}
      />

      <h3 className="mb-2 text-xs font-medium tracking-wide text-navy-500 uppercase">{t.admin.decodedCall}</h3>
      <div className="overflow-x-auto rounded-xl border border-navy-100">
        <table className="w-full text-sm">
          <tbody>
            {p.args.map((a) => (
              <tr key={a.name} className="border-b border-navy-100 last:border-0">
                <td className="px-3 py-2 whitespace-nowrap text-navy-500">
                  {a.name} <span className="text-xs text-navy-300">{a.type}</span>
                </td>
                <td className="px-3 py-2 font-mono text-xs break-all text-navy-900">{a.value}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <dl className="mt-4 grid gap-3 text-sm">
        <div>
          <dt className="text-xs font-medium tracking-wide text-navy-500 uppercase">{t.admin.rawCalldata}</dt>
          <dd className="mt-1 rounded-lg bg-navy-50 p-2 font-mono text-xs break-all text-navy-700">{shortHex(p.calldata, 24)}</dd>
        </div>
        <div>
          <dt className="text-xs font-medium tracking-wide text-navy-500 uppercase">{t.admin.digest}</dt>
          <dd className="mt-1 flex flex-wrap items-center gap-2">
            <span className="font-mono text-xs break-all text-navy-700">{shortHex(p.digest, 16)}</span>
            <Badge tone="brand">
              <Icon name="check" className="size-3" /> {t.admin.digestMatches}
            </Badge>
          </dd>
        </div>
      </dl>

      <h3 className="mt-5 mb-2 text-xs font-medium tracking-wide text-navy-500 uppercase">
        {t.admin.signatures} ({p.signers.length}/{MULTISIG_THRESHOLD})
      </h3>
      {p.signers.length === 0 ? (
        <p className="text-sm text-navy-500">{t.admin.noSignatures}</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {p.signers.map((s) => (
            <li key={s} className="flex items-center gap-2 text-sm">
              <Icon name="signature" className="size-4 text-brand-600" />
              <Address address={s} name={ownerLabel(s)} copy={false} />
            </li>
          ))}
        </ul>
      )}

      {!done && (
        <div className="mt-6 flex flex-col gap-3 border-t border-navy-100 pt-5">
          <div className="flex flex-col gap-2 sm:flex-row">
            <Button variant="secondary" disabled={signed} onClick={onSign}>
              <Icon name="signature" className="size-4" /> {signed ? t.admin.alreadySigned : t.admin.signProposal}
            </Button>
            {!p.onChain && (
              <Button variant="secondary" disabled={missing > 0} onClick={onSubmit}>
                {t.admin.submitSignatures}
              </Button>
            )}
            <Button disabled={!!blocker || !p.onChain} onClick={onExecute} className="sm:ml-auto">
              {t.admin.execute}
            </Button>
          </div>
          <p className={cx("rounded-lg p-3 text-xs", blocker ? "bg-amber-50 text-amber-700" : "bg-brand-50 text-brand-700")}>
            {blocker ?? t.admin.simulationOk}
          </p>
        </div>
      )}
    </Card>
  );
}

function NewProposalDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t } = useI18n();
  const targets = (Object.keys(PROPOSAL_ACTIONS) as ContractName[]).filter((c) => PROPOSAL_ACTIONS[c].length > 0);
  const [target, setTarget] = useState<ContractName>("IndexManager");
  const [fn, setFn] = useState(PROPOSAL_ACTIONS.IndexManager[0]?.fn ?? "");
  const [args, setArgs] = useState("");
  const [notice, setNotice] = useState(false);

  const action = PROPOSAL_ACTIONS[target].find((a) => a.fn === fn);
  const values = args.split("\n");

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={t.admin.newProposal}
      footer={
        <>
          <Button variant="secondary" onClick={onClose}>
            {t.common.cancel}
          </Button>
          <Button onClick={() => setNotice(true)}>{t.admin.form.create}</Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <label className="block">
          <span className="mb-1.5 block text-xs font-medium text-navy-500">{t.admin.form.target}</span>
          <select
            className="w-full"
            value={target}
            onChange={(e) => {
              const next = targets.find((c) => c === e.target.value) ?? "IndexManager";
              setTarget(next);
              setFn(PROPOSAL_ACTIONS[next][0]?.fn ?? "");
            }}
          >
            {targets.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-medium text-navy-500">{t.admin.form.action}</span>
          <select className="w-full" value={fn} onChange={(e) => setFn(e.target.value)}>
            {PROPOSAL_ACTIONS[target].map((a) => (
              <option key={a.fn} value={a.fn}>
                {a.fn}({a.args.join(", ")})
              </option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-1.5 block text-xs font-medium text-navy-500">{t.admin.form.args}</span>
          <textarea rows={4} className="w-full font-mono" value={args} onChange={(e) => setArgs(e.target.value)} />
          <span className="mt-1 block text-xs text-navy-500">{t.admin.form.argsHint}</span>
        </label>
        {action && (
          <div>
            <div className="mb-1.5 text-xs font-medium text-navy-500">{t.admin.form.preview}</div>
            <pre className="overflow-x-auto rounded-lg bg-navy-900 p-3 text-xs text-navy-100">
              {`${target}.${action.fn}(\n${action.args.map((a, i) => `  ${a} = ${values[i]?.trim() || "…"}`).join(",\n")}\n)`}
            </pre>
          </div>
        )}
        {notice && <p className="rounded-lg bg-amber-50 p-3 text-xs text-amber-700">{t.common.demoNotice}</p>}
      </div>
    </Modal>
  );
}
