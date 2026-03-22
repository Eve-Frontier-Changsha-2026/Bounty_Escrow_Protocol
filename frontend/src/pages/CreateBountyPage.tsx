import { useState, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { Button } from '../components/ui/Button';
import { Input } from '../components/ui/Input';
import { Textarea } from '../components/ui/Textarea';
import { TransactionToast } from '../components/ui/TransactionToast';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildCreateBounty } from '../lib/ptb/create';
import { suiToMist, bpsToPercent } from '../lib/format';
import { LIMITS } from '../lib/constants';
import type { Toast } from '../lib/types';

const INVALIDATE_KEYS = [['bountyList']];

export function CreateBountyPage() {
  const navigate = useNavigate();
  const account = useCurrentAccount();
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);
  const [toast, setToast] = useState<Toast | null>(null);

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [rewardSui, setRewardSui] = useState('');
  const [stakeSui, setStakeSui] = useState('');
  const [maxClaims, setMaxClaims] = useState('1');
  const [deadlineHours, setDeadlineHours] = useState('24');
  const [gracePeriodHours, setGracePeriodHours] = useState('24');
  const [cleanupBps, setCleanupBps] = useState('100');
  const [verifierAddr, setVerifierAddr] = useState('');

  const totalEscrow = useMemo(() => {
    try {
      const reward = suiToMist(rewardSui || '0');
      return reward * BigInt(maxClaims || '1');
    } catch {
      return 0n;
    }
  }, [rewardSui, maxClaims]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!account) return;

    try {
      const now = Date.now();
      const deadlineMs = BigInt(Math.floor(parseFloat(deadlineHours) * 3_600_000));
      const graceMs = BigInt(Math.floor(parseFloat(gracePeriodHours) * 3_600_000));

      const tx = buildCreateBounty({
        title,
        description,
        rewardAmount: suiToMist(rewardSui),
        requiredStake: suiToMist(stakeSui || '0'),
        maxClaims: parseInt(maxClaims),
        deadline: BigInt(now) + deadlineMs,
        gracePeriod: graceMs,
        cleanupRewardBps: parseInt(cleanupBps),
        verifierAddr: verifierAddr || account.address,
      });

      const digest = await execute(tx);
      setToast({ type: 'success', message: 'Bounty created!', digest });
      setTimeout(() => navigate('/'), 2000);
    } catch (err) {
      setToast({ type: 'error', message: err instanceof Error ? err.message : 'Failed to create bounty' });
    }
  }

  return (
    <WalletGuard>
      <div className="max-w-2xl mx-auto">
        <h1 className="font-heading text-2xl sm:text-3xl text-eve-text mb-1">CREATE BOUNTY</h1>
        <p className="text-eve-sub text-sm mb-8">Deploy a new bounty contract on the frontier</p>

        <form onSubmit={handleSubmit}>
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
              Total escrow required: <span className="text-eve-gold font-heading">
                {totalEscrow > 0n ? `${Number(totalEscrow) / 1e9} SUI` : '—'}
              </span>
            </div>
          </Panel>

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

          <Button type="submit" disabled={isPending} className="w-full">
            {isPending ? 'DEPLOYING...' : 'DEPLOY BOUNTY'}
          </Button>
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
