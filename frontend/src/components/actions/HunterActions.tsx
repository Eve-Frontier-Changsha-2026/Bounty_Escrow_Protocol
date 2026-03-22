import { useState } from 'react';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import { Textarea } from '../ui/Textarea';
import { useTransactionExecutor } from '../../hooks/useTransactionExecutor';
import { buildClaimBounty } from '../../lib/ptb/claim';
import { buildClaimReward } from '../../lib/ptb/reward';
import { buildAbandon } from '../../lib/ptb/abandon';
import { buildWithdrawPenalty } from '../../lib/ptb/withdraw-penalty';
import { buildDestroyTicket } from '../../lib/ptb/cleanup';
import { buildSubmitProof } from '../../lib/ptb/submit-proof';
import { buildResubmitProof } from '../../lib/ptb/resubmit-proof';
import { buildDisputeRejection } from '../../lib/ptb/dispute-rejection';
import { buildAutoApproveProof } from '../../lib/ptb/auto-approve';
import { BountyStatus, ProofStatus, LIMITS } from '../../lib/constants';
import { mistToSui } from '../../lib/format';
import type { ParsedBounty, ParsedClaimTicket, ParsedProofSubmission, Toast } from '../../lib/types';

const INVALIDATE_KEYS = [['bountyDetail'], ['bountyList'], ['ownedTickets'], ['proofSubmission'], ['reviewConfig']];

interface HunterActionsProps {
  bounty: ParsedBounty;
  ticket: ParsedClaimTicket | null;
  isApproved: boolean;
  proof: ParsedProofSubmission | null;
  reviewPeriodMs: number;
  onToast: (t: Toast) => void;
}

export function HunterActions({ bounty, ticket, isApproved, proof, reviewPeriodMs, onToast }: HunterActionsProps) {
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);

  // Proof form state
  const [proofUrl, setProofUrl] = useState('');
  const [proofDescription, setProofDescription] = useState('');
  const [disputeReason, setDisputeReason] = useState('');
  const [showProofForm, setShowProofForm] = useState(false);
  const [showDisputeForm, setShowDisputeForm] = useState(false);

  const isActive = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;
  const beforeDeadline = Date.now() < bounty.deadline;

  const canClaim = !ticket && bounty.status === BountyStatus.OPEN && bounty.activeClaims < bounty.maxClaims;
  const canAbandon = !!ticket && isActive && beforeDeadline;
  const canClaimReward = !!ticket && isApproved;
  const canWithdrawPenalty = !!ticket && bounty.status === BountyStatus.CANCELLED;
  const canDestroyTicket = !!ticket &&
    (bounty.status === BountyStatus.COMPLETED ||
     bounty.status === BountyStatus.CANCELLED ||
     bounty.status === BountyStatus.EXPIRED);

  // Proof-related conditions
  const canSubmitProof = !!ticket && !proof && isActive && beforeDeadline;
  const canResubmitProof = !!ticket && proof?.status === ProofStatus.REJECTED && !proof.hasResubmitted && beforeDeadline;
  const canDisputeRejection = !!ticket && proof?.status === ProofStatus.REJECTED && Date.now() < bounty.deadline + bounty.gracePeriod;
  const canAutoApprove = !!ticket && proof?.status === ProofStatus.SUBMITTED &&
    Date.now() >= proof.submittedAt + reviewPeriodMs;

  async function handleAction(action: string) {
    try {
      let tx;
      switch (action) {
        case 'claim':
          tx = buildClaimBounty({ bountyId: bounty.id, stakeAmount: bounty.requiredStake, coinType: bounty.coinType });
          break;
        case 'reward':
          tx = buildClaimReward({ bountyId: bounty.id, ticketId: ticket!.id, coinType: bounty.coinType });
          break;
        case 'abandon':
          tx = buildAbandon({ bountyId: bounty.id, ticketId: ticket!.id, coinType: bounty.coinType });
          break;
        case 'withdraw':
          tx = buildWithdrawPenalty({ bountyId: bounty.id, ticketId: ticket!.id, coinType: bounty.coinType });
          break;
        case 'destroy':
          tx = buildDestroyTicket({ ticketId: ticket!.id, bountyId: bounty.id, coinType: bounty.coinType });
          break;
        default:
          return;
      }
      const digest = await execute(tx);
      onToast({ type: 'success', message: `${action} successful!`, digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Transaction failed' });
    }
  }

  async function handleSubmitProof() {
    if (!proofUrl.trim()) return;
    try {
      const tx = buildSubmitProof({
        bountyId: bounty.id,
        proofUrl: proofUrl.trim(),
        proofDescription: proofDescription.trim(),
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Proof submitted!', digest });
      setProofUrl('');
      setProofDescription('');
      setShowProofForm(false);
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Submit proof failed' });
    }
  }

  async function handleResubmitProof() {
    if (!proofUrl.trim()) return;
    try {
      const tx = buildResubmitProof({
        bountyId: bounty.id,
        proofUrl: proofUrl.trim(),
        proofDescription: proofDescription.trim(),
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Proof resubmitted!', digest });
      setProofUrl('');
      setProofDescription('');
      setShowProofForm(false);
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Resubmit failed' });
    }
  }

  async function handleDisputeRejection() {
    if (!disputeReason.trim()) return;
    try {
      const tx = buildDisputeRejection({
        bountyId: bounty.id,
        reason: disputeReason.trim(),
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Dispute raised!', digest });
      setDisputeReason('');
      setShowDisputeForm(false);
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Dispute failed' });
    }
  }

  async function handleAutoApprove() {
    try {
      const tx = buildAutoApproveProof({ bountyId: bounty.id, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Proof auto-approved!', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Auto-approve failed' });
    }
  }

  const proofUrlValid = proofUrl.trim().length > 0 && proofUrl.trim().length <= LIMITS.MAX_PROOF_URL;
  const proofDescValid = proofDescription.length <= LIMITS.MAX_PROOF_DESCRIPTION;
  const disputeReasonValid = disputeReason.trim().length > 0 && disputeReason.trim().length <= LIMITS.MAX_REASON;

  return (
    <div className="space-y-3">
      <h3 className="font-heading text-xs text-eve-cyan tracking-wider">HUNTER ACTIONS</h3>

      {/* Claim */}
      {canClaim && (
        <div className="flex items-center justify-between">
          <span className="text-xs text-eve-sub">
            Stake required: {mistToSui(bounty.requiredStake)} SUI
          </span>
          <Button variant="primary" disabled={isPending} onClick={() => handleAction('claim')}>
            {isPending ? 'CLAIMING...' : 'CLAIM BOUNTY'}
          </Button>
        </div>
      )}

      {/* Collect reward */}
      {canClaimReward && (
        <Button variant="primary" disabled={isPending} onClick={() => handleAction('reward')} className="w-full">
          {isPending ? 'COLLECTING...' : `COLLECT REWARD (${mistToSui(bounty.rewardAmount)} SUI)`}
        </Button>
      )}

      {/* Submit proof */}
      {canSubmitProof && (
        <div className="space-y-2">
          {!showProofForm ? (
            <Button variant="primary" onClick={() => setShowProofForm(true)} className="w-full">
              SUBMIT PROOF
            </Button>
          ) : (
            <div className="space-y-2 p-3 bg-eve-bg-2 rounded-lg border border-eve-panel-border/50">
              <Input
                label="Proof URL"
                value={proofUrl}
                onChange={(e) => setProofUrl(e.target.value)}
                placeholder="https://..."
                hint={`${proofUrl.length}/${LIMITS.MAX_PROOF_URL}`}
              />
              <Textarea
                label="Description (optional)"
                value={proofDescription}
                onChange={(e) => setProofDescription(e.target.value)}
                placeholder="Describe your deliverable..."
                hint={`${proofDescription.length}/${LIMITS.MAX_PROOF_DESCRIPTION}`}
              />
              <div className="flex gap-2">
                <Button
                  variant="primary"
                  disabled={isPending || !proofUrlValid || !proofDescValid}
                  onClick={handleSubmitProof}
                  className="flex-1"
                >
                  {isPending ? 'SUBMITTING...' : 'SUBMIT'}
                </Button>
                <Button variant="secondary" onClick={() => setShowProofForm(false)}>CANCEL</Button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Resubmit proof (after rejection, one-shot) */}
      {canResubmitProof && (
        <div className="space-y-2">
          {!showProofForm ? (
            <Button variant="primary" onClick={() => setShowProofForm(true)} className="w-full">
              RESUBMIT PROOF
            </Button>
          ) : (
            <div className="space-y-2 p-3 bg-eve-bg-2 rounded-lg border border-eve-panel-border/50">
              <Input
                label="New Proof URL"
                value={proofUrl}
                onChange={(e) => setProofUrl(e.target.value)}
                placeholder="https://..."
                hint={`${proofUrl.length}/${LIMITS.MAX_PROOF_URL}`}
              />
              <Textarea
                label="New Description (optional)"
                value={proofDescription}
                onChange={(e) => setProofDescription(e.target.value)}
                placeholder="Describe updated deliverable..."
                hint={`${proofDescription.length}/${LIMITS.MAX_PROOF_DESCRIPTION}`}
              />
              <div className="flex gap-2">
                <Button
                  variant="primary"
                  disabled={isPending || !proofUrlValid || !proofDescValid}
                  onClick={handleResubmitProof}
                  className="flex-1"
                >
                  {isPending ? 'RESUBMITTING...' : 'RESUBMIT'}
                </Button>
                <Button variant="secondary" onClick={() => setShowProofForm(false)}>CANCEL</Button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Dispute rejection */}
      {canDisputeRejection && (
        <div className="space-y-2">
          {!showDisputeForm ? (
            <Button variant="danger" onClick={() => setShowDisputeForm(true)} className="w-full">
              DISPUTE REJECTION
            </Button>
          ) : (
            <div className="space-y-2 p-3 bg-eve-bg-2 rounded-lg border border-eve-danger/30">
              <Textarea
                label="Dispute Reason"
                value={disputeReason}
                onChange={(e) => setDisputeReason(e.target.value)}
                placeholder="Explain why the rejection is unjust..."
                hint={`${disputeReason.length}/${LIMITS.MAX_REASON}`}
              />
              <div className="flex gap-2">
                <Button
                  variant="danger"
                  disabled={isPending || !disputeReasonValid}
                  onClick={handleDisputeRejection}
                  className="flex-1"
                >
                  {isPending ? 'FILING...' : 'FILE DISPUTE'}
                </Button>
                <Button variant="secondary" onClick={() => setShowDisputeForm(false)}>CANCEL</Button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Auto-approve (review period expired) */}
      {canAutoApprove && (
        <Button variant="primary" disabled={isPending} onClick={handleAutoApprove} className="w-full">
          {isPending ? 'APPROVING...' : 'AUTO-APPROVE (review period expired)'}
        </Button>
      )}

      {/* Waiting states */}
      {ticket && proof?.status === ProofStatus.SUBMITTED && !canAutoApprove && (
        <p className="text-xs text-eve-sub">Proof submitted. Waiting for verifier review...</p>
      )}
      {ticket && proof?.status === ProofStatus.DISPUTED && (
        <p className="text-xs text-eve-sub">Dispute pending creator resolution...</p>
      )}
      {ticket && proof?.status === ProofStatus.RESOLVED_REJECTED && (
        <p className="text-xs text-eve-danger">Dispute was resolved against you.</p>
      )}

      {/* Abandon */}
      {canAbandon && (
        <Button variant="danger" disabled={isPending} onClick={() => handleAction('abandon')} className="w-full">
          {isPending ? 'ABANDONING...' : 'ABANDON CLAIM (forfeit stake)'}
        </Button>
      )}

      {/* Withdraw penalty */}
      {canWithdrawPenalty && (
        <Button variant="secondary" disabled={isPending} onClick={() => handleAction('withdraw')} className="w-full">
          {isPending ? 'WITHDRAWING...' : 'WITHDRAW PENALTY + STAKE'}
        </Button>
      )}

      {/* Destroy ticket */}
      {canDestroyTicket && !canWithdrawPenalty && !canClaimReward && (
        <Button variant="secondary" disabled={isPending} onClick={() => handleAction('destroy')} className="w-full">
          {isPending ? 'CLEANING...' : 'DESTROY TICKET (cleanup)'}
        </Button>
      )}

      {/* Fallback waiting state (no proof yet, has ticket, nothing else to do) */}
      {ticket && !proof && !canSubmitProof && !canClaimReward && !canAbandon && !canWithdrawPenalty && !canDestroyTicket && (
        <p className="text-xs text-eve-sub">Waiting for verifier approval...</p>
      )}
    </div>
  );
}
