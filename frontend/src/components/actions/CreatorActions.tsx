import { useState } from 'react';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import { useTransactionExecutor } from '../../hooks/useTransactionExecutor';
import { useHunterProofs } from '../../hooks/useProofSubmission';
import { buildCancel } from '../../lib/ptb/cancel';
import { buildWithdrawRemaining } from '../../lib/ptb/withdraw-remaining';
import { buildResolveDispute } from '../../lib/ptb/resolve-dispute';
import { buildSetReviewPeriod } from '../../lib/ptb/set-review-period';
import { buildSetArbitrator } from '../../lib/ptb/set-arbitrator';
import { BountyStatus, ProofStatus, PROOF_STATUS_LABEL, LIMITS } from '../../lib/constants';
import { truncateAddress } from '../../lib/format';
import type { ParsedBounty, Toast } from '../../lib/types';
import type { ArbitratorConfig } from '../../hooks/useArbitratorConfig';

const INVALIDATE_KEYS = [['bountyDetail'], ['bountyList'], ['proofSubmission'], ['reviewConfig'], ['arbitratorConfig']];

interface CreatorActionsProps {
  bounty: ParsedBounty;
  arbitratorConfig: ArbitratorConfig | null;
  onToast: (t: Toast) => void;
}

export function CreatorActions({ bounty, arbitratorConfig, onToast }: CreatorActionsProps) {
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);
  const proofQueries = useHunterProofs(bounty.id, bounty.hunters);
  const [pendingAddr, setPendingAddr] = useState<string | null>(null);
  const [reviewPeriodHours, setReviewPeriodHours] = useState('72');
  const [showReviewPeriod, setShowReviewPeriod] = useState(false);

  // Arbitrator form state
  const [showArbitratorForm, setShowArbitratorForm] = useState(false);
  const [arbAddress, setArbAddress] = useState('');
  const [arbTimeoutDays, setArbTimeoutDays] = useState('7');

  const isActive = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;
  const canCancel = isActive;
  const canWithdrawRemaining = bounty.status === BountyStatus.CANCELLED && bounty.activeClaims === 0;
  const canSetReviewPeriod = bounty.status === BountyStatus.OPEN && bounty.activeClaims === 0;
  const canSetArbitrator = bounty.status === BountyStatus.OPEN && bounty.activeClaims === 0;

  const reviewPeriodMs = Math.round(parseFloat(reviewPeriodHours || '0') * 3_600_000);
  const reviewPeriodValid = reviewPeriodMs >= LIMITS.MIN_REVIEW_PERIOD_MS && reviewPeriodMs <= LIMITS.MAX_REVIEW_PERIOD_MS;

  const arbTimeoutMs = Math.round(parseFloat(arbTimeoutDays || '0') * 86_400_000);
  const arbAddressValid = /^0x[0-9a-fA-F]{64}$/.test(arbAddress.trim());
  const arbTimeoutValid = arbTimeoutMs >= LIMITS.MIN_DISPUTE_TIMEOUT_MS && arbTimeoutMs <= LIMITS.MAX_DISPUTE_TIMEOUT_MS;

  const hasArbitrator = !!arbitratorConfig;

  async function handleResolveDispute(hunterAddr: string, approve: boolean) {
    setPendingAddr(hunterAddr);
    try {
      const tx = buildResolveDispute({
        bountyId: bounty.id,
        hunterAddr,
        approve,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: `Dispute ${approve ? 'approved' : 'rejected'} for ${truncateAddress(hunterAddr)}!`, digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Resolve failed' });
    } finally {
      setPendingAddr(null);
    }
  }

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

  async function handleSetArbitrator() {
    if (!arbAddressValid || !arbTimeoutValid) return;
    try {
      const tx = buildSetArbitrator({
        bountyId: bounty.id,
        arbitrator: arbAddress.trim(),
        disputeTimeoutMs: arbTimeoutMs,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: `Arbitrator set to ${truncateAddress(arbAddress)}!`, digest });
      setShowArbitratorForm(false);
      setArbAddress('');
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Set arbitrator failed' });
    }
  }

  // Collect hunters with disputed or resolved proofs for display
  const disputeEntries = bounty.hunters
    .map((hunter, i) => ({ hunter, proof: proofQueries[i]?.data }))
    .filter(({ proof }) =>
      proof?.status === ProofStatus.DISPUTED ||
      proof?.status === ProofStatus.RESOLVED_APPROVED ||
      proof?.status === ProofStatus.RESOLVED_REJECTED
    );

  return (
    <div className="space-y-3">
      <h3 className="font-heading text-xs text-eve-gold tracking-wider">CREATOR ACTIONS</h3>

      {/* Arbitrator info / setup */}
      {hasArbitrator && (
        <div className="p-3 bg-eve-bg-2 rounded-lg border border-eve-panel-border/50 space-y-1">
          <h4 className="font-heading text-[10px] text-eve-sub tracking-wider">ARBITRATOR</h4>
          <div className="text-xs text-eve-text font-mono">{truncateAddress(arbitratorConfig.arbitrator)}</div>
          <div className="text-[10px] text-eve-sub">
            Dispute timeout: {Math.round(arbitratorConfig.disputeTimeoutMs / 86_400_000)}d
          </div>
        </div>
      )}

      {canSetArbitrator && (
        <div className="space-y-2">
          {!showArbitratorForm ? (
            <Button variant="secondary" onClick={() => setShowArbitratorForm(true)} className="w-full">
              {hasArbitrator ? 'UPDATE ARBITRATOR' : 'SET ARBITRATOR'}
            </Button>
          ) : (
            <div className="space-y-2 p-3 bg-eve-bg-2 rounded-lg border border-eve-panel-border/50">
              <Input
                label="Arbitrator Address"
                value={arbAddress}
                onChange={(e) => setArbAddress(e.target.value)}
                placeholder="0x..."
                hint="Cannot be your own address"
              />
              <Input
                label="Dispute Timeout (days)"
                type="number"
                value={arbTimeoutDays}
                onChange={(e) => setArbTimeoutDays(e.target.value)}
                placeholder="7"
                hint={`Range: ${LIMITS.MIN_DISPUTE_TIMEOUT_MS / 86_400_000}–${LIMITS.MAX_DISPUTE_TIMEOUT_MS / 86_400_000} days`}
              />
              <div className="flex gap-2">
                <Button
                  variant="primary"
                  disabled={isPending || !arbAddressValid || !arbTimeoutValid}
                  onClick={handleSetArbitrator}
                  className="flex-1"
                >
                  {isPending ? 'SETTING...' : 'CONFIRM'}
                </Button>
                <Button variant="secondary" onClick={() => setShowArbitratorForm(false)}>CANCEL</Button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Dispute resolution list */}
      {isActive && disputeEntries.length > 0 && (
        <div className="space-y-2">
          <h4 className="font-heading text-[10px] text-eve-sub tracking-wider">DISPUTES</h4>
          {disputeEntries.map(({ hunter, proof }) => {
            const status = proof!.status;
            const isDisputed = status === ProofStatus.DISPUTED;
            const busy = isPending && pendingAddr === hunter;

            return (
              <div
                key={hunter}
                className="p-3 bg-eve-bg-2 rounded-lg border border-eve-panel-border/50 space-y-2"
              >
                <div className="flex items-center justify-between gap-3">
                  <span className="text-xs font-mono text-eve-text truncate flex-1">
                    {truncateAddress(hunter)}
                  </span>
                  <span className={`text-[10px] font-heading tracking-wider ${
                    status === ProofStatus.RESOLVED_APPROVED
                      ? 'text-green-400'
                      : status === ProofStatus.RESOLVED_REJECTED
                        ? 'text-eve-danger'
                        : 'text-yellow-400'
                  }`}>
                    {PROOF_STATUS_LABEL[status] ?? `STATUS ${status}`}
                  </span>
                </div>

                {/* Proof content */}
                {proof && (
                  <div className="text-[11px] text-eve-sub space-y-1">
                    {proof.proofUrl && (
                      <p className="truncate">URL: <span className="text-eve-text">{proof.proofUrl}</span></p>
                    )}
                    {proof.proofDescription && (
                      <p className="truncate">Desc: <span className="text-eve-text">{proof.proofDescription}</span></p>
                    )}
                    {proof.disputeReason && (
                      <p className="truncate">Dispute: <span className="text-yellow-400">{proof.disputeReason}</span></p>
                    )}
                  </div>
                )}

                {/* Action buttons — only for DISPUTED status */}
                {isDisputed && !hasArbitrator && (
                  <div className="flex gap-2 pt-1">
                    <Button
                      variant="primary"
                      disabled={busy}
                      onClick={() => handleResolveDispute(hunter, true)}
                      className="text-xs !px-3 !py-1 flex-1"
                    >
                      {busy ? '...' : 'APPROVE'}
                    </Button>
                    <Button
                      variant="danger"
                      disabled={busy}
                      onClick={() => handleResolveDispute(hunter, false)}
                      className="text-xs !px-3 !py-1 flex-1"
                    >
                      {busy ? '...' : 'REJECT'}
                    </Button>
                  </div>
                )}

                {/* Arbitrator assigned — creator cannot resolve */}
                {isDisputed && hasArbitrator && (
                  <p className="text-[10px] text-eve-sub italic">
                    Assigned to arbitrator: {truncateAddress(arbitratorConfig.arbitrator)}
                  </p>
                )}

                {/* Resolved status messages */}
                {status === ProofStatus.RESOLVED_APPROVED && (
                  <p className="text-[10px] text-green-400 italic">Approved. Hunter can claim reward.</p>
                )}
                {status === ProofStatus.RESOLVED_REJECTED && (
                  <p className="text-[10px] text-eve-danger italic">Rejected. Stake will be forfeited on expiry.</p>
                )}
              </div>
            );
          })}
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
