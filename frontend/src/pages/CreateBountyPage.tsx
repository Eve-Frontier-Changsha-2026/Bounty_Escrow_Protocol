import { useState, useReducer, useMemo, useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useDAppKit, useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react';
import { useQueryClient } from '@tanstack/react-query';
import type { SealCompatibleClient } from '@mysten/seal';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { Textarea } from '../components/ui/Textarea';
import { TransactionToast } from '../components/ui/TransactionToast';
import { CharacterSelect } from '../components/CharacterSelect';
import { SolarSystemSearch } from '../components/ui/SolarSystemSearch';
import { buildCreateBountyFull } from '../lib/ptb/create-full';
import { resolveCharacterItemId } from '../lib/resolve-character';
import { useCharacters } from '../hooks/useCharacters';
import { buildSetEncryptedDetails } from '../lib/ptb/set-encrypted-details';
import { sealEncrypt } from '../lib/seal';
import { suiToMist, mistToSui, bpsToPercent } from '../lib/format';
import {
  TaskType,
  TASK_TYPE_LABEL,
  TASK_TYPE_COLOR,
  TASK_TYPE_BG,
  LIMITS,
} from '../lib/constants';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';
import type { Toast, BountyCreatedEvent } from '../lib/types';

const INVALIDATE_KEYS = [['bountyList']];
const MAX_U64 = (1n << 64n) - 1n;
const RECOVERY_KEY = 'bounty_create_tx2_pending';

type CreateStep = 'form' | 'tx1' | 'encrypt' | 'tx2' | 'done';

interface Tx2Recovery {
  digest1: string;
  bountyId: string;
  timestamp: number;
}

function saveTx2Recovery(data: Omit<Tx2Recovery, 'timestamp'>) {
  localStorage.setItem(RECOVERY_KEY, JSON.stringify({ ...data, timestamp: Date.now() }));
}

function loadTx2Recovery(): Tx2Recovery | null {
  try {
    const raw = localStorage.getItem(RECOVERY_KEY);
    if (!raw) return null;
    const data = JSON.parse(raw) as Tx2Recovery;
    // Expire after 1 hour
    if (Date.now() - data.timestamp > 3_600_000) {
      localStorage.removeItem(RECOVERY_KEY);
      return null;
    }
    return data;
  } catch {
    localStorage.removeItem(RECOVERY_KEY);
    return null;
  }
}

function clearTx2Recovery() {
  localStorage.removeItem(RECOVERY_KEY);
}

const TASK_TYPES = [
  { value: TaskType.CUSTOM, desc: 'Manual proof + verifier review' },
  { value: TaskType.KILL, desc: 'Verify via on-chain Killmail' },
  { value: TaskType.DELIVERY, desc: 'Oracle-verified item delivery' },
  { value: TaskType.BUILD, desc: 'Oracle-verified structure build' },
  { value: TaskType.INTEL, desc: 'Seal-encrypted intelligence trade' },
] as const;

// ── Form reducer ──────────────────────────────────────────────
interface FormState {
  title: string;
  description: string;
  rewardSui: string;
  stakeSui: string;
  maxClaims: string;
  deadlineHours: string;
  gracePeriodHours: string;
  cleanupBps: string;
  verifierAddr: string;
  taskType: number;
  killSolarSystem: string;
  killLossType: string;
  killMinKills: string;
  selectedTargetCharId: string | null;
  deliveryItemTypeId: string;
  deliveryMinQuantity: string;
  deliveryTargetAssembly: string;
  buildAssemblyTypeId: string;
  buildSolarSystem: string;
  isEncrypted: boolean;
  encryptedText: string;
}

const INITIAL_FORM: FormState = {
  title: '',
  description: '',
  rewardSui: '',
  stakeSui: '',
  maxClaims: '1',
  deadlineHours: '24',
  gracePeriodHours: '24',
  cleanupBps: '100',
  verifierAddr: '',
  taskType: TaskType.CUSTOM,
  killSolarSystem: '',
  killLossType: '0',
  killMinKills: '1',
  selectedTargetCharId: null,
  deliveryItemTypeId: '',
  deliveryMinQuantity: '1',
  deliveryTargetAssembly: '',
  buildAssemblyTypeId: '',
  buildSolarSystem: '',
  isEncrypted: false,
  encryptedText: '',
};

type FormAction =
  | { type: 'field'; field: keyof FormState; value: FormState[keyof FormState] }
  | { type: 'reset' };

function formReducer(state: FormState, action: FormAction): FormState {
  switch (action.type) {
    case 'field':
      return { ...state, [action.field]: action.value };
    case 'reset':
      return INITIAL_FORM;
  }
}

export function CreateBountyPage() {
  const navigate = useNavigate();
  const account = useCurrentAccount();
  const dAppKit = useDAppKit();
  const client = useCurrentClient();
  const queryClient = useQueryClient();
  const [toast, setToast] = useState<Toast | null>(null);
  const [step, setStep] = useState<CreateStep>('form');
  const [recovery, setRecovery] = useState<Tx2Recovery | null>(() => loadTx2Recovery());
  const [form, dispatch] = useReducer(formReducer, INITIAL_FORM);
  const set = (field: keyof FormState, value: FormState[keyof FormState]) =>
    dispatch({ type: 'field', field, value });

  const { data: characters = [], isLoading: charactersLoading } = useCharacters();
  const navTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => () => clearTimeout(navTimerRef.current), []);

  const totalEscrow = useMemo(() => {
    try {
      const reward = suiToMist(form.rewardSui || '0');
      return reward * BigInt(form.maxClaims || '1');
    } catch {
      return 0n;
    }
  }, [form.rewardSui, form.maxClaims]);
  const escrowOverflow = totalEscrow > MAX_U64;

  const isValidSuiAddress = (addr: string) =>
    /^0x[0-9a-fA-F]{64}$/.test(addr);
  const verifierAddrError =
    form.verifierAddr && !isValidSuiAddress(form.verifierAddr)
      ? 'Invalid SUI address (must be 0x + 64 hex chars)'
      : '';

  const isPending = step !== 'form' && step !== 'done';

  // ---------------------------------------------------------------
  // Extract bountyId from TX1 digest via BountyCreated event
  // ---------------------------------------------------------------
  async function extractBountyId(digest: string): Promise<string> {
    const txBlock = await client.getTransactionBlock({
      digest,
      options: { showEvents: true },
    });
    const eventType = `${ORIGINAL_PACKAGE_ID}::bounty::BountyCreated`;
    const event = txBlock.events?.find((e) => e.type === eventType);
    if (!event) throw new Error('BountyCreated event not found in TX1');
    const parsed = event.parsedJson as BountyCreatedEvent;
    return parsed.bounty_id;
  }

  // ---------------------------------------------------------------
  // TX2 recovery handler
  // ---------------------------------------------------------------
  async function handleRetryTx2(rec: Tx2Recovery) {
    if (!form.encryptedText.trim()) {
      setToast({ type: 'error', message: 'Enter the encrypted details text below before retrying.' });
      return;
    }
    try {
      setStep('encrypt');
      const plaintext = new TextEncoder().encode(form.encryptedText);

      const { encryptedObject } = await sealEncrypt({
        suiClient: client as SealCompatibleClient,
        bountyId: rec.bountyId,
        plaintext,
      });

      setStep('tx2');
      const tx2 = buildSetEncryptedDetails({
        bountyId: rec.bountyId,
        encryptedPayload: encryptedObject,
      });

      const result2 = await dAppKit.signAndExecuteTransaction({ transaction: tx2 });
      if (result2.FailedTransaction) {
        throw new Error(result2.FailedTransaction.status.error?.message ?? 'TX2 failed');
      }
      await client.waitForTransaction({ digest: result2.Transaction.digest });

      clearTx2Recovery();
      setRecovery(null);
      for (const key of INVALIDATE_KEYS) {
        await queryClient.invalidateQueries({ queryKey: key });
      }
      setStep('done');
      setToast({ type: 'success', message: 'Encrypted details saved!', digest: result2.Transaction.digest });
      navTimerRef.current = setTimeout(() => navigate('/'), 2500);
    } catch (err) {
      setStep('form');
      setToast({
        type: 'error',
        message: `TX2 retry failed: ${err instanceof Error ? err.message : 'Unknown error'}`,
      });
    }
  }

  // ---------------------------------------------------------------
  // 2-step submit handler
  // ---------------------------------------------------------------
  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!account) return;

    try {
      const now = Date.now();

      // --- Front-end validation (block garbage before PTB) ---
      const deadlineHoursNum = parseFloat(form.deadlineHours);
      const graceHoursNum = parseFloat(form.gracePeriodHours);
      const maxClaimsNum = parseInt(form.maxClaims);
      const cleanupBpsNum = parseInt(form.cleanupBps);

      if (!form.rewardSui || isNaN(Number(form.rewardSui)) || Number(form.rewardSui) <= 0) {
        throw new Error('Reward must be a positive number');
      }
      if (isNaN(deadlineHoursNum) || deadlineHoursNum < 1) {
        throw new Error('Deadline must be at least 1 hour');
      }
      if (isNaN(graceHoursNum) || graceHoursNum < 1) {
        throw new Error('Grace period must be at least 1 hour');
      }
      if (isNaN(maxClaimsNum) || maxClaimsNum < 1 || maxClaimsNum > LIMITS.MAX_CLAIMS) {
        throw new Error(`Max claims must be 1–${LIMITS.MAX_CLAIMS}`);
      }
      if (isNaN(cleanupBpsNum) || cleanupBpsNum < 0 || cleanupBpsNum > LIMITS.MAX_CLEANUP_BPS) {
        throw new Error(`Cleanup reward must be 0–${LIMITS.MAX_CLEANUP_BPS} bps`);
      }

      const deadlineMs = BigInt(Math.floor(deadlineHoursNum * 3_600_000));
      const graceMs = BigInt(Math.floor(graceHoursNum * 3_600_000));

      // Validate verifier address if provided
      if (form.verifierAddr && !isValidSuiAddress(form.verifierAddr)) {
        throw new Error('Invalid verifier address');
      }

      // Validate u64 bounds before building PTB
      const rewardMist = suiToMist(form.rewardSui);
      if (rewardMist <= 0n) {
        throw new Error('Reward must be greater than zero');
      }
      const escrow = rewardMist * BigInt(maxClaimsNum);
      if (rewardMist > MAX_U64 || escrow > MAX_U64) {
        throw new Error('Total escrow exceeds maximum allowed amount');
      }

      // === TX1: Create + configure + share ===
      setStep('tx1');

      // Resolve target victim item_id if selected
      let resolvedVictimId: string | undefined;
      if (form.selectedTargetCharId) {
        resolvedVictimId = await resolveCharacterItemId(client, form.selectedTargetCharId);
      }

      const tx1 = buildCreateBountyFull({
        title: form.title,
        description: form.description,
        rewardAmount: suiToMist(form.rewardSui),
        requiredStake: suiToMist(form.stakeSui || '0'),
        maxClaims: parseInt(form.maxClaims),
        deadline: BigInt(now) + deadlineMs,
        gracePeriod: graceMs,
        cleanupRewardBps: parseInt(form.cleanupBps),
        verifierAddr: form.verifierAddr || account.address,
        taskType: form.taskType,
        killCriteria:
          form.taskType === TaskType.KILL
            ? {
                solarSystemId: form.killSolarSystem,
                lossType: parseInt(form.killLossType),
                minKills: parseInt(form.killMinKills),
              }
            : undefined,
        deliveryCriteria:
          form.taskType === TaskType.DELIVERY
            ? {
                itemTypeId: form.deliveryItemTypeId,
                minQuantity: parseInt(form.deliveryMinQuantity),
                targetAssemblyId: form.deliveryTargetAssembly,
              }
            : undefined,
        buildCriteria:
          form.taskType === TaskType.BUILD
            ? {
                assemblyTypeId: form.buildAssemblyTypeId,
                solarSystemId: form.buildSolarSystem,
              }
            : undefined,
        targetVictimId: resolvedVictimId,
        isEncrypted: form.isEncrypted,
        sender: account.address,
      });

      const result1 = await dAppKit.signAndExecuteTransaction({ transaction: tx1 });
      if (result1.FailedTransaction) {
        throw new Error(result1.FailedTransaction.status.error?.message ?? 'TX1 failed');
      }
      const digest1 = result1.Transaction.digest;
      await client.waitForTransaction({ digest: digest1 });

      // === TX2: Seal encrypt + set_encrypted_details (if encrypted) ===
      if (form.isEncrypted && form.encryptedText.trim()) {
        setStep('encrypt');

        const bountyId = await extractBountyId(digest1);

        // Persist for recovery in case TX2 fails (no plaintext — user re-enters)
        saveTx2Recovery({ digest1, bountyId });

        const plaintext = new TextEncoder().encode(form.encryptedText);

        const { encryptedObject } = await sealEncrypt({
          suiClient: client as SealCompatibleClient,
          bountyId,
          plaintext,
        });

        setStep('tx2');

        const tx2 = buildSetEncryptedDetails({
          bountyId,
          encryptedPayload: encryptedObject,
        });

        const result2 = await dAppKit.signAndExecuteTransaction({ transaction: tx2 });
        if (result2.FailedTransaction) {
          throw new Error(result2.FailedTransaction.status.error?.message ?? 'TX2 failed');
        }
        await client.waitForTransaction({ digest: result2.Transaction.digest });
        clearTx2Recovery();
      }

      // Invalidate queries
      for (const key of INVALIDATE_KEYS) {
        await queryClient.invalidateQueries({ queryKey: key });
      }

      setStep('done');
      setToast({ type: 'success', message: 'Bounty created!', digest: digest1 });
      navTimerRef.current = setTimeout(() => navigate('/'), 2500);
    } catch (err) {
      setStep('form');
      setToast({
        type: 'error',
        message: err instanceof Error ? err.message : 'Failed to create bounty',
      });
    }
  }

  // ---------------------------------------------------------------
  // Render
  // ---------------------------------------------------------------
  return (
    <WalletGuard>
      <div className="max-w-2xl mx-auto">
        <h1 className="font-heading text-2xl sm:text-3xl text-eve-text mb-1">CREATE BOUNTY</h1>
        <p className="text-eve-sub text-sm mb-8">Deploy a new bounty contract on the frontier</p>

        {/* ── TX2 Recovery Banner ── */}
        {recovery && step === 'form' && (
          <Panel className="mb-6 border-eve-warning/50 bg-eve-warning/5">
            <div className="space-y-3">
              <h2 className="font-heading text-sm text-eve-warning tracking-wider">
                PENDING ENCRYPTION
              </h2>
              <p className="text-xs text-eve-sub">
                A bounty was created but encrypted details were not saved.
                Bounty ID: <span className="text-eve-text font-mono">{recovery.bountyId.slice(0, 16)}...</span>
              </p>
              <Textarea
                label="Re-enter encrypted details"
                value={form.encryptedText}
                onChange={(e) => set('encryptedText', e.target.value)}
                placeholder="Re-enter the sensitive bounty details to encrypt..."
                maxLength={LIMITS.MAX_ENCRYPTED_DETAILS_SIZE}
                rows={3}
              />
              <div className="flex gap-2">
                <Button
                  type="button"
                  onClick={() => handleRetryTx2(recovery)}
                  disabled={isPending}
                  className="text-xs"
                >
                  RETRY TX2 — SET ENCRYPTED DETAILS
                </Button>
                <button
                  type="button"
                  onClick={() => { clearTx2Recovery(); setRecovery(null); }}
                  className="text-xs text-eve-sub hover:text-eve-text transition-colors px-3"
                >
                  Dismiss
                </button>
              </div>
            </div>
          </Panel>
        )}

        <form onSubmit={handleSubmit}>
          {/* ── MISSION DETAILS ── */}
          <Panel className="space-y-5 mb-6">
            <h2 className="font-heading text-sm text-eve-gold tracking-wider">MISSION DETAILS</h2>
            <Input
              label="Title"
              value={form.title}
              onChange={(e) => set('title', e.target.value)}
              placeholder="Enter bounty title"
              maxLength={LIMITS.MAX_TITLE}
              required
            />
            <Textarea
              label="Description"
              value={form.description}
              onChange={(e) => set('description', e.target.value)}
              placeholder="Describe the bounty requirements..."
              maxLength={LIMITS.MAX_DESCRIPTION}
              rows={4}
            />
          </Panel>

          {/* ── TASK TYPE ── */}
          <Panel className="space-y-4 mb-6 relative z-10">
            <h2 className="font-heading text-sm text-eve-gold tracking-wider">TASK TYPE</h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
              {TASK_TYPES.map((t) => {
                const selected = form.taskType === t.value;
                return (
                  <button
                    key={t.value}
                    type="button"
                    onClick={() => set('taskType', t.value)}
                    className={`text-left p-3 rounded-lg border transition-all cursor-pointer ${
                      selected
                        ? `${TASK_TYPE_BG[t.value]} border-current ring-1 ring-current/30`
                        : 'bg-eve-bg-2 border-eve-panel-border hover:border-eve-sub/50'
                    }`}
                  >
                    <span
                      className={`font-heading text-xs tracking-wider ${
                        selected ? TASK_TYPE_COLOR[t.value] : 'text-eve-sub'
                      }`}
                    >
                      {TASK_TYPE_LABEL[t.value]}
                    </span>
                    <p className="text-[10px] text-eve-sub/70 mt-1 leading-tight">{t.desc}</p>
                  </button>
                );
              })}
            </div>

            {/* ── KILL CRITERIA ── */}
            {form.taskType === TaskType.KILL && (
              <div className="space-y-4 pt-3 border-t border-eve-panel-border/50 overflow-visible">
                <h3 className="font-heading text-xs text-eve-danger tracking-wider">
                  KILL CRITERIA
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  <SolarSystemSearch
                    label="Solar System"
                    value={form.killSolarSystem}
                    onChange={(v: string) => set('killSolarSystem', v)}
                    hint="Where the kill must happen"
                  />
                  <Input
                    label="Loss Type"
                    type="number"
                    min="0"
                    max="2"
                    value={form.killLossType}
                    onChange={(e) => set('killLossType', e.target.value)}
                    hint="0=Ship, 1=Pod, 2=Any"
                  />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input
                    label="Min Kills"
                    type="number"
                    min="1"
                    value={form.killMinKills}
                    onChange={(e) => set('killMinKills', e.target.value)}
                    required
                  />
                  <CharacterSelect
                    label="Target Victim"
                    characters={characters}
                    loading={charactersLoading}
                    value={form.selectedTargetCharId}
                    onChange={(v: string | null) => set('selectedTargetCharId', v)}
                    hint="Optional — specific target to kill"
                  />
                </div>
              </div>
            )}

            {/* ── DELIVERY CRITERIA ── */}
            {form.taskType === TaskType.DELIVERY && (
              <div className="space-y-4 pt-3 border-t border-eve-panel-border/50">
                <h3 className="font-heading text-xs text-eve-cyan tracking-wider">
                  DELIVERY CRITERIA
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  <Input
                    label="Item Type ID"
                    value={form.deliveryItemTypeId}
                    onChange={(e) => set('deliveryItemTypeId', e.target.value)}
                    placeholder="e.g. 77302"
                    required
                  />
                  <Input
                    label="Min Quantity"
                    type="number"
                    min="1"
                    value={form.deliveryMinQuantity}
                    onChange={(e) => set('deliveryMinQuantity', e.target.value)}
                    required
                  />
                </div>
                <Input
                  label="Target Assembly (address)"
                  value={form.deliveryTargetAssembly}
                  onChange={(e) => set('deliveryTargetAssembly', e.target.value)}
                  placeholder="0x..."
                  required
                />
              </div>
            )}

            {/* ── BUILD CRITERIA ── */}
            {form.taskType === TaskType.BUILD && (
              <div className="space-y-4 pt-3 border-t border-eve-panel-border/50">
                <h3 className="font-heading text-xs text-eve-gold tracking-wider">
                  BUILD CRITERIA
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  <Input
                    label="Assembly Type ID"
                    value={form.buildAssemblyTypeId}
                    onChange={(e) => set('buildAssemblyTypeId', e.target.value)}
                    placeholder="e.g. 84556"
                    required
                  />
                  <SolarSystemSearch
                    label="Solar System"
                    value={form.buildSolarSystem}
                    onChange={(v: string) => set('buildSolarSystem', v)}
                    hint="Optional — where the structure must be built"
                  />
                </div>
              </div>
            )}

            {/* ── INTEL — no extra criteria, uses Seal ── */}
            {form.taskType === TaskType.INTEL && (
              <div className="pt-3 border-t border-eve-panel-border/50">
                <p className="text-xs text-eve-accent/80">
                  Intel bounties use Seal encryption. The hunter posts encrypted intel, and you
                  decrypt it after purchasing a viewer receipt.
                </p>
              </div>
            )}
          </Panel>

          {/* ── ENCRYPTION (v7) ── */}
          {form.taskType !== TaskType.CUSTOM && (
            <Panel className="space-y-4 mb-6">
              <div className="flex items-center gap-3">
                <h2 className="font-heading text-sm text-eve-gold tracking-wider">
                  ENCRYPTED DETAILS
                </h2>
                <label className="flex items-center gap-2 cursor-pointer ml-auto">
                  <input
                    type="checkbox"
                    checked={form.isEncrypted}
                    onChange={(e) => set('isEncrypted', e.target.checked)}
                    className="w-4 h-4 accent-eve-cyan rounded"
                  />
                  <span className="text-xs text-eve-sub">Enable Seal encryption</span>
                </label>
              </div>
              {form.isEncrypted && (
                <>
                  <Textarea
                    label="Private Details (encrypted on-chain)"
                    value={form.encryptedText}
                    onChange={(e) => set('encryptedText', e.target.value)}
                    placeholder="Enter sensitive bounty details that only receipt holders can decrypt..."
                    maxLength={LIMITS.MAX_ENCRYPTED_DETAILS_SIZE}
                    rows={4}
                  />
                  <p className="text-[10px] text-eve-sub/60">
                    {form.encryptedText.length} / {LIMITS.MAX_ENCRYPTED_DETAILS_SIZE} bytes — encrypted
                    via Seal (2-of-2 threshold). A second TX will be signed after bounty creation.
                  </p>
                </>
              )}
            </Panel>
          )}

          {/* ── ECONOMICS ── */}
          <Panel className="space-y-5 mb-6">
            <h2 className="font-heading text-sm text-eve-gold tracking-wider">ECONOMICS</h2>
            <div className="grid grid-cols-2 gap-4">
              <Input
                label="Reward (SUI)"
                type="number"
                step="0.001"
                min="0.001"
                value={form.rewardSui}
                onChange={(e) => set('rewardSui', e.target.value)}
                placeholder="1.0"
                required
              />
              <Input
                label="Required Stake (SUI)"
                type="number"
                step="0.001"
                min="0"
                value={form.stakeSui}
                onChange={(e) => set('stakeSui', e.target.value)}
                placeholder="0.5"
                hint="0 = no stake"
              />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <Input
                label="Max Claims"
                type="number"
                min="1"
                max={LIMITS.MAX_CLAIMS}
                value={form.maxClaims}
                onChange={(e) => set('maxClaims', e.target.value)}
                required
              />
              <Input
                label="Cleanup Reward (bps)"
                type="number"
                min="0"
                max={LIMITS.MAX_CLEANUP_BPS}
                value={form.cleanupBps}
                onChange={(e) => set('cleanupBps', e.target.value)}
                hint={`= ${bpsToPercent(parseInt(form.cleanupBps) || 0)}`}
              />
            </div>
            <div className="text-xs text-eve-sub">
              Total escrow required:{' '}
              <span className={`font-heading ${escrowOverflow ? 'text-eve-danger' : 'text-eve-gold'}`}>
                {escrowOverflow ? 'EXCEEDS MAX' : totalEscrow > 0n ? `${mistToSui(totalEscrow)} SUI` : '—'}
              </span>
            </div>
          </Panel>

          {/* ── TIMING ── */}
          <Panel className="space-y-5 mb-6">
            <h2 className="font-heading text-sm text-eve-gold tracking-wider">TIMING</h2>
            <div className="grid grid-cols-2 gap-4">
              <Input
                label="Deadline (hours from now)"
                type="number"
                step="0.5"
                min="1"
                value={form.deadlineHours}
                onChange={(e) => set('deadlineHours', e.target.value)}
                required
              />
              <Input
                label="Grace Period (hours)"
                type="number"
                step="0.5"
                min="1"
                value={form.gracePeriodHours}
                onChange={(e) => set('gracePeriodHours', e.target.value)}
                hint="Verification window after deadline"
                required
              />
            </div>
          </Panel>

          {/* ── VERIFIER ── */}
          <Panel className="space-y-5 mb-8">
            <h2 className="font-heading text-sm text-eve-gold tracking-wider">VERIFIER</h2>
            <Input
              label="Verifier Address"
              value={form.verifierAddr}
              onChange={(e) => set('verifierAddr', e.target.value)}
              placeholder={account?.address ?? 'Enter verifier address'}
              hint={verifierAddrError || 'Leave empty to use your own address'}
            />
            {verifierAddrError && (
              <p className="text-xs text-eve-danger">{verifierAddrError}</p>
            )}
          </Panel>

          {/* ── SUBMIT ── */}
          <Button type="submit" disabled={isPending || escrowOverflow || !!verifierAddrError} className="w-full">
            {step === 'tx1' && 'SIGNING TX1 — CREATE BOUNTY...'}
            {step === 'encrypt' && 'ENCRYPTING WITH SEAL...'}
            {step === 'tx2' && 'SIGNING TX2 — SET ENCRYPTED DETAILS...'}
            {step === 'done' && 'DEPLOYED!'}
            {step === 'form' && (form.isEncrypted ? 'DEPLOY BOUNTY (2 TXs)' : 'DEPLOY BOUNTY')}
          </Button>

          {isPending && (
            <div className="mt-3 text-center">
              <div className="inline-flex items-center gap-2 text-xs text-eve-sub">
                <span className="w-3 h-3 border-2 border-eve-cyan border-t-transparent rounded-full animate-spin" />
                {step === 'tx1' && 'Creating bounty on-chain...'}
                {step === 'encrypt' && 'Encrypting details via Seal key servers...'}
                {step === 'tx2' && 'Writing encrypted details on-chain...'}
              </div>
            </div>
          )}
        </form>
      </div>

      {toast && (
        <TransactionToast
          type={toast.type}
          message={toast.message}
          digest={toast.digest}
          onClose={() => setToast(null)}
        />
      )}
    </WalletGuard>
  );
}

export default CreateBountyPage;
