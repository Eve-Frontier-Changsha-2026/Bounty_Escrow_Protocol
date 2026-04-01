import { useState, useMemo } from 'react';
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

type CreateStep = 'form' | 'tx1' | 'encrypt' | 'tx2' | 'done';

const TASK_TYPES = [
  { value: TaskType.CUSTOM, desc: 'Manual proof + verifier review' },
  { value: TaskType.KILL, desc: 'Verify via on-chain Killmail' },
  { value: TaskType.DELIVERY, desc: 'Oracle-verified item delivery' },
  { value: TaskType.BUILD, desc: 'Oracle-verified structure build' },
  { value: TaskType.INTEL, desc: 'Seal-encrypted intelligence trade' },
] as const;

export function CreateBountyPage() {
  const navigate = useNavigate();
  const account = useCurrentAccount();
  const dAppKit = useDAppKit();
  const client = useCurrentClient();
  const queryClient = useQueryClient();
  const [toast, setToast] = useState<Toast | null>(null);
  const [step, setStep] = useState<CreateStep>('form');

  // --- Core fields ---
  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [rewardSui, setRewardSui] = useState('');
  const [stakeSui, setStakeSui] = useState('');
  const [maxClaims, setMaxClaims] = useState('1');
  const [deadlineHours, setDeadlineHours] = useState('24');
  const [gracePeriodHours, setGracePeriodHours] = useState('24');
  const [cleanupBps, setCleanupBps] = useState('100');
  const [verifierAddr, setVerifierAddr] = useState('');

  // --- Task type ---
  const [taskType, setTaskType] = useState<number>(TaskType.CUSTOM);

  // Kill criteria
  const [killSolarSystem, setKillSolarSystem] = useState('');
  const [killLossType, setKillLossType] = useState('0');
  const [killMinKills, setKillMinKills] = useState('1');
  // Character data for target victim picker
  const { data: characters = [], isLoading: charactersLoading } = useCharacters();
  const [selectedTargetCharId, setSelectedTargetCharId] = useState<string | null>(null);

  // Delivery criteria
  const [deliveryItemTypeId, setDeliveryItemTypeId] = useState('');
  const [deliveryMinQuantity, setDeliveryMinQuantity] = useState('1');
  const [deliveryTargetAssembly, setDeliveryTargetAssembly] = useState('');

  // Build criteria
  const [buildAssemblyTypeId, setBuildAssemblyTypeId] = useState('');
  const [buildSolarSystem, setBuildSolarSystem] = useState('');

  // --- Encryption (v7) ---
  const [isEncrypted, setIsEncrypted] = useState(false);
  const [encryptedText, setEncryptedText] = useState('');

  const totalEscrow = useMemo(() => {
    try {
      const reward = suiToMist(rewardSui || '0');
      return reward * BigInt(maxClaims || '1');
    } catch {
      return 0n;
    }
  }, [rewardSui, maxClaims]);
  const escrowOverflow = totalEscrow > MAX_U64;

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
  // 2-step submit handler
  // ---------------------------------------------------------------
  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!account) return;

    try {
      const now = Date.now();
      const deadlineMs = BigInt(Math.floor(parseFloat(deadlineHours) * 3_600_000));
      const graceMs = BigInt(Math.floor(parseFloat(gracePeriodHours) * 3_600_000));

      // Validate u64 bounds before building PTB
      const rewardMist = suiToMist(rewardSui);
      const escrow = rewardMist * BigInt(parseInt(maxClaims));
      if (rewardMist > MAX_U64 || escrow > MAX_U64) {
        throw new Error('Total escrow exceeds maximum allowed amount');
      }

      // === TX1: Create + configure + share ===
      setStep('tx1');

      // Resolve target victim item_id if selected
      let resolvedVictimId: string | undefined;
      if (selectedTargetCharId) {
        resolvedVictimId = await resolveCharacterItemId(client, selectedTargetCharId);
      }

      const tx1 = buildCreateBountyFull({
        title,
        description,
        rewardAmount: suiToMist(rewardSui),
        requiredStake: suiToMist(stakeSui || '0'),
        maxClaims: parseInt(maxClaims),
        deadline: BigInt(now) + deadlineMs,
        gracePeriod: graceMs,
        cleanupRewardBps: parseInt(cleanupBps),
        verifierAddr: verifierAddr || account.address,
        taskType,
        killCriteria:
          taskType === TaskType.KILL
            ? {
                solarSystemId: killSolarSystem,
                lossType: parseInt(killLossType),
                minKills: parseInt(killMinKills),
              }
            : undefined,
        deliveryCriteria:
          taskType === TaskType.DELIVERY
            ? {
                itemTypeId: deliveryItemTypeId,
                minQuantity: parseInt(deliveryMinQuantity),
                targetAssemblyId: deliveryTargetAssembly,
              }
            : undefined,
        buildCriteria:
          taskType === TaskType.BUILD
            ? {
                assemblyTypeId: buildAssemblyTypeId,
                solarSystemId: buildSolarSystem,
              }
            : undefined,
        targetVictimId: resolvedVictimId,
        isEncrypted,
        sender: account.address,
      });

      const result1 = await dAppKit.signAndExecuteTransaction({ transaction: tx1 });
      if (result1.FailedTransaction) {
        throw new Error(result1.FailedTransaction.status.error?.message ?? 'TX1 failed');
      }
      const digest1 = result1.Transaction.digest;
      await client.waitForTransaction({ digest: digest1 });

      // === TX2: Seal encrypt + set_encrypted_details (if encrypted) ===
      if (isEncrypted && encryptedText.trim()) {
        setStep('encrypt');

        const bountyId = await extractBountyId(digest1);
        const plaintext = new TextEncoder().encode(encryptedText);

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
      }

      // Invalidate queries
      for (const key of INVALIDATE_KEYS) {
        await queryClient.invalidateQueries({ queryKey: key });
      }

      setStep('done');
      setToast({ type: 'success', message: 'Bounty created!', digest: digest1 });
      setTimeout(() => navigate('/'), 2500);
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

        <form onSubmit={handleSubmit}>
          {/* ── MISSION DETAILS ── */}
          <Panel className="space-y-5 mb-6">
            <h2 className="font-heading text-sm text-eve-gold tracking-wider">MISSION DETAILS</h2>
            <Input
              label="Title"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="Enter bounty title"
              maxLength={LIMITS.MAX_TITLE}
              required
            />
            <Textarea
              label="Description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
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
                const selected = taskType === t.value;
                return (
                  <button
                    key={t.value}
                    type="button"
                    onClick={() => setTaskType(t.value)}
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
            {taskType === TaskType.KILL && (
              <div className="space-y-4 pt-3 border-t border-eve-panel-border/50 overflow-visible">
                <h3 className="font-heading text-xs text-eve-danger tracking-wider">
                  KILL CRITERIA
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  <SolarSystemSearch
                    label="Solar System"
                    value={killSolarSystem}
                    onChange={setKillSolarSystem}
                    hint="Where the kill must happen"
                  />
                  <Input
                    label="Loss Type"
                    type="number"
                    min="0"
                    max="2"
                    value={killLossType}
                    onChange={(e) => setKillLossType(e.target.value)}
                    hint="0=Ship, 1=Pod, 2=Any"
                  />
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <Input
                    label="Min Kills"
                    type="number"
                    min="1"
                    value={killMinKills}
                    onChange={(e) => setKillMinKills(e.target.value)}
                    required
                  />
                  <CharacterSelect
                    label="Target Victim"
                    characters={characters}
                    loading={charactersLoading}
                    value={selectedTargetCharId}
                    onChange={setSelectedTargetCharId}
                    hint="Optional — specific target to kill"
                  />
                </div>
              </div>
            )}

            {/* ── DELIVERY CRITERIA ── */}
            {taskType === TaskType.DELIVERY && (
              <div className="space-y-4 pt-3 border-t border-eve-panel-border/50">
                <h3 className="font-heading text-xs text-eve-cyan tracking-wider">
                  DELIVERY CRITERIA
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  <Input
                    label="Item Type ID"
                    value={deliveryItemTypeId}
                    onChange={(e) => setDeliveryItemTypeId(e.target.value)}
                    placeholder="e.g. 77302"
                    required
                  />
                  <Input
                    label="Min Quantity"
                    type="number"
                    min="1"
                    value={deliveryMinQuantity}
                    onChange={(e) => setDeliveryMinQuantity(e.target.value)}
                    required
                  />
                </div>
                <Input
                  label="Target Assembly (address)"
                  value={deliveryTargetAssembly}
                  onChange={(e) => setDeliveryTargetAssembly(e.target.value)}
                  placeholder="0x..."
                  required
                />
              </div>
            )}

            {/* ── BUILD CRITERIA ── */}
            {taskType === TaskType.BUILD && (
              <div className="space-y-4 pt-3 border-t border-eve-panel-border/50">
                <h3 className="font-heading text-xs text-eve-gold tracking-wider">
                  BUILD CRITERIA
                </h3>
                <div className="grid grid-cols-2 gap-4">
                  <Input
                    label="Assembly Type ID"
                    value={buildAssemblyTypeId}
                    onChange={(e) => setBuildAssemblyTypeId(e.target.value)}
                    placeholder="e.g. 84556"
                    required
                  />
                  <SolarSystemSearch
                    label="Solar System"
                    value={buildSolarSystem}
                    onChange={setBuildSolarSystem}
                    hint="Optional — where the structure must be built"
                  />
                </div>
              </div>
            )}

            {/* ── INTEL — no extra criteria, uses Seal ── */}
            {taskType === TaskType.INTEL && (
              <div className="pt-3 border-t border-eve-panel-border/50">
                <p className="text-xs text-eve-accent/80">
                  Intel bounties use Seal encryption. The hunter posts encrypted intel, and you
                  decrypt it after purchasing a viewer receipt.
                </p>
              </div>
            )}
          </Panel>

          {/* ── ENCRYPTION (v7) ── */}
          {taskType !== TaskType.CUSTOM && (
            <Panel className="space-y-4 mb-6">
              <div className="flex items-center gap-3">
                <h2 className="font-heading text-sm text-eve-gold tracking-wider">
                  ENCRYPTED DETAILS
                </h2>
                <label className="flex items-center gap-2 cursor-pointer ml-auto">
                  <input
                    type="checkbox"
                    checked={isEncrypted}
                    onChange={(e) => setIsEncrypted(e.target.checked)}
                    className="w-4 h-4 accent-eve-cyan rounded"
                  />
                  <span className="text-xs text-eve-sub">Enable Seal encryption</span>
                </label>
              </div>
              {isEncrypted && (
                <>
                  <Textarea
                    label="Private Details (encrypted on-chain)"
                    value={encryptedText}
                    onChange={(e) => setEncryptedText(e.target.value)}
                    placeholder="Enter sensitive bounty details that only receipt holders can decrypt..."
                    maxLength={LIMITS.MAX_ENCRYPTED_DETAILS_SIZE}
                    rows={4}
                  />
                  <p className="text-[10px] text-eve-sub/60">
                    {encryptedText.length} / {LIMITS.MAX_ENCRYPTED_DETAILS_SIZE} bytes — encrypted
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
                value={rewardSui}
                onChange={(e) => setRewardSui(e.target.value)}
                placeholder="1.0"
                required
              />
              <Input
                label="Required Stake (SUI)"
                type="number"
                step="0.001"
                min="0"
                value={stakeSui}
                onChange={(e) => setStakeSui(e.target.value)}
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
                value={maxClaims}
                onChange={(e) => setMaxClaims(e.target.value)}
                required
              />
              <Input
                label="Cleanup Reward (bps)"
                type="number"
                min="0"
                max={LIMITS.MAX_CLEANUP_BPS}
                value={cleanupBps}
                onChange={(e) => setCleanupBps(e.target.value)}
                hint={`= ${bpsToPercent(parseInt(cleanupBps) || 0)}`}
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
                value={deadlineHours}
                onChange={(e) => setDeadlineHours(e.target.value)}
                required
              />
              <Input
                label="Grace Period (hours)"
                type="number"
                step="0.5"
                min="1"
                value={gracePeriodHours}
                onChange={(e) => setGracePeriodHours(e.target.value)}
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
              value={verifierAddr}
              onChange={(e) => setVerifierAddr(e.target.value)}
              placeholder={account?.address ?? 'Enter verifier address'}
              hint="Leave empty to use your own address"
            />
          </Panel>

          {/* ── SUBMIT ── */}
          <Button type="submit" disabled={isPending || escrowOverflow} className="w-full">
            {step === 'tx1' && 'SIGNING TX1 — CREATE BOUNTY...'}
            {step === 'encrypt' && 'ENCRYPTING WITH SEAL...'}
            {step === 'tx2' && 'SIGNING TX2 — SET ENCRYPTED DETAILS...'}
            {step === 'done' && 'DEPLOYED!'}
            {step === 'form' && (isEncrypted ? 'DEPLOY BOUNTY (2 TXs)' : 'DEPLOY BOUNTY')}
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
