import { useState } from 'react';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import { useTransactionExecutor } from '../../hooks/useTransactionExecutor';
import { buildCancel } from '../../lib/ptb/cancel';
import { buildWithdrawRemaining } from '../../lib/ptb/withdraw-remaining';
import { buildResolveDispute } from '../../lib/ptb/resolve-dispute';
import { buildSetReviewPeriod } from '../../lib/ptb/set-review-period';
import { BountyStatus, LIMITS } from '../../lib/constants';
import type { ParsedBounty, Toast } from '../../lib/types';

const INVALIDATE_KEYS = [['bountyDetail'], ['bountyList'], ['proofSubmission'], ['reviewConfig']];

interface CreatorActionsProps {
  bounty: ParsedBounty;
  onToast: (t: Toast) => void;
}

export function CreatorActions({ bounty, onToast }: CreatorActionsProps) {
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);
  const [disputeHunterAddr, setDisputeHunterAddr] = useState('');
  const [reviewPeriodHours, setReviewPeriodHours] = useState('72');
  const [showReviewPeriod, setShowReviewPeriod] = useState(false);

  const isActive = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;
  const canCancel = isActive;
  const canWithdrawRemaining = bounty.status === BountyStatus.CANCELLED && bounty.activeClaims === 0;
  const canSetReviewPeriod = bounty.status === BountyStatus.OPEN && bounty.activeClaims === 0;

  const reviewPeriodMs = Math.round(parseFloat(reviewPeriodHours || '0') * 3_600_000);
  const reviewPeriodValid = reviewPeriodMs >= LIMITS.MIN_REVIEW_PERIOD_MS && reviewPeriodMs <= LIMITS.MAX_REVIEW_PERIOD_MS;

  async function handleCancel() {
    try {
      const tx = buildCancel({ bountyId: bounty.id, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Bounty cancelled!', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Cancel failed' });
    }
  }

  async function handleWithdraw() {
    try {
      const tx = buildWithdrawRemaining({ bountyId: bounty.id, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Remaining funds withdrawn!', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Withdraw failed' });
    }
  }

  async function handleResolveDispute(approve: boolean) {
    if (!disputeHunterAddr.startsWith('0x')) return;
    try {
      const tx = buildResolveDispute({
        bountyId: bounty.id,
        hunterAddr: disputeHunterAddr,
        approve,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: `Dispute ${approve ? 'approved' : 'rejected'}!`, digest });
      setDisputeHunterAddr('');
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Resolve failed' });
    }
  }

  async function handleSetReviewPeriod() {
    if (!reviewPeriodValid) return;
    try {
      const tx = buildSetReviewPeriod({
        bountyId: bounty.id,
        reviewPeriodMs,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: `Review period set to ${reviewPeriodHours}h!`, digest });
      setShowReviewPeriod(false);
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Set review period failed' });
    }
  }

  return (
    <div className="space-y-3">
      <h3 className="font-heading text-xs text-eve-gold tracking-wider">CREATOR ACTIONS</h3>

      {/* Resolve dispute */}
      {isActive && (
        <div className="space-y-2">
          <Input
            label="Resolve Dispute — Hunter Address"
            value={disputeHunterAddr}
            onChange={(e) => setDisputeHunterAddr(e.target.value)}
            placeholder="0x..."
            hint="Enter the hunter address whose dispute you want to resolve"
          />
          <div className="flex gap-2">
            <Button
              variant="primary"
              disabled={isPending || !disputeHunterAddr.startsWith('0x')}
              onClick={() => handleResolveDispute(true)}
              className="flex-1"
            >
              {isPending ? 'RESOLVING...' : 'APPROVE DISPUTE'}
            </Button>
            <Button
              variant="danger"
              disabled={isPending || !disputeHunterAddr.startsWith('0x')}
              onClick={() => handleResolveDispute(false)}
              className="flex-1"
            >
              {isPending ? 'RESOLVING...' : 'REJECT DISPUTE'}
            </Button>
          </div>
        </div>
      )}

      {/* Set review period */}
      {canSetReviewPeriod && (
        <div className="space-y-2">
          {!showReviewPeriod ? (
            <Button variant="secondary" onClick={() => setShowReviewPeriod(true)} className="w-full">
              SET REVIEW PERIOD
            </Button>
          ) : (
            <div className="space-y-2 p-3 bg-eve-bg-2 rounded-lg border border-eve-panel-border/50">
              <Input
                label="Review Period (hours)"
                type="number"
                value={reviewPeriodHours}
                onChange={(e) => setReviewPeriodHours(e.target.value)}
                placeholder="72"
                hint={`Range: 1–168 hours (${(LIMITS.MIN_REVIEW_PERIOD_MS / 3_600_000)}h – ${(LIMITS.MAX_REVIEW_PERIOD_MS / 3_600_000)}h)`}
              />
              <div className="flex gap-2">
                <Button
                  variant="primary"
                  disabled={isPending || !reviewPeriodValid}
                  onClick={handleSetReviewPeriod}
                  className="flex-1"
                >
                  {isPending ? 'SETTING...' : 'CONFIRM'}
                </Button>
                <Button variant="secondary" onClick={() => setShowReviewPeriod(false)}>CANCEL</Button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Cancel */}
      {canCancel && (
        <Button variant="danger" disabled={isPending} onClick={handleCancel} className="w-full">
          {isPending ? 'CANCELLING...' : 'CANCEL BOUNTY'}
        </Button>
      )}

      {/* Withdraw remaining */}
      {canWithdrawRemaining && (
        <Button variant="secondary" disabled={isPending} onClick={handleWithdraw} className="w-full">
          {isPending ? 'WITHDRAWING...' : 'WITHDRAW REMAINING FUNDS'}
        </Button>
      )}
    </div>
  );
}
