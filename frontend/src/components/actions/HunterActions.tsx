import { Button } from '../ui/Button';
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
import { buildAutoResolveDispute } from '../../lib/ptb/auto-resolve-dispute';
import { buildWithdrawFromBounty } from '../../lib/ptb/withdraw-from-bounty';
import { BountyStatus, ProofStatus, TaskType, LIMITS } from '../../lib/constants';
import { KillVerifyButton } from '../KillVerifyButton';
import { mistToSui } from '../../lib/format';
import { ProofForm } from './ProofForm';
import { DisputeForm } from './DisputeForm';
import { HunterStatusMessages } from './HunterStatusMessages';
import type { ParsedBounty, ParsedClaimTicket, ParsedProofSubmission, Toast } from '../../lib/types';
import type { ArbitratorConfig } from '../../hooks/useArbitratorConfig';
import type { DisputeTimestamp } from '../../hooks/useDisputeTimestamp';

const INVALIDATE_KEYS = [['bountyDetail'], ['bountyList'], ['ownedTickets'], ['proofSubmission'], ['reviewConfig'], ['arbitratorConfig'], ['disputeTimestamp']];

interface HunterActionsProps {
  bounty: ParsedBounty;
  ticket: ParsedClaimTicket | null;
  isApproved: boolean;
  proof: ParsedProofSubmission | null;
  reviewPeriodMs: number;
  arbitratorConfig: ArbitratorConfig | null;
  disputeTimestamp: DisputeTimestamp | null;
  onToast: (t: Toast) => void;
  taskType?: number;
  targetVictimId?: string;
  taskCreatedAt?: number;
}

export function HunterActions({ bounty, ticket, isApproved, proof, reviewPeriodMs, arbitratorConfig, disputeTimestamp, onToast, taskType, targetVictimId, taskCreatedAt }: HunterActionsProps) {
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);

  const isActive = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;
  const beforeDeadline = Date.now() < bounty.deadline;
  const beforeGraceEnd = Date.now() < bounty.deadline + bounty.gracePeriod;

  const canClaim = !ticket && bounty.status === BountyStatus.OPEN && bounty.activeClaims < bounty.maxClaims && beforeDeadline;
  const canAbandon = !!ticket && isActive && beforeDeadline;
  const canClaimReward = !!ticket && isApproved;
  const canWithdrawPenalty = !!ticket && bounty.status === BountyStatus.CANCELLED;
  const canDestroyTicket = !!ticket &&
    (bounty.status === BountyStatus.COMPLETED ||
     bounty.status === BountyStatus.CANCELLED ||
     bounty.status === BountyStatus.EXPIRED);

  const canSubmitProof = !!ticket && !proof && isActive && beforeDeadline;
  const canResubmitProof = !!ticket && proof?.status === ProofStatus.REJECTED && !proof.hasResubmitted && beforeDeadline;
  const canDisputeRejection = !!ticket && proof?.status === ProofStatus.REJECTED && Date.now() < bounty.deadline + bounty.gracePeriod;
  const canAutoApprove = !!ticket && proof?.status === ProofStatus.SUBMITTED &&
    Date.now() >= proof.submittedAt + reviewPeriodMs;

  const canWithdrawFromBounty = !!ticket && isActive && beforeGraceEnd &&
    (!proof || proof.status === ProofStatus.REJECTED || proof.status === ProofStatus.RESOLVED_REJECTED);

  const disputeTimeoutMs = arbitratorConfig?.disputeTimeoutMs ?? LIMITS.DEFAULT_DISPUTE_TIMEOUT_MS;
  const canAutoResolve = !!ticket && proof?.status === ProofStatus.DISPUTED && !!disputeTimestamp &&
    Date.now() >= disputeTimestamp.disputedAt + disputeTimeoutMs;

  const autoResolveAt = disputeTimestamp ? disputeTimestamp.disputedAt + disputeTimeoutMs : 0;
  const autoResolveRemaining = Math.max(0, autoResolveAt - Date.now());

  // --- Action handlers ---

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

  async function handleProofSubmit(proofUrl: string, proofDescription: string) {
    try {
      const tx = buildSubmitProof({ bountyId: bounty.id, proofUrl, proofDescription, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Proof submitted!', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Submit proof failed' });
    }
  }

  async function handleProofResubmit(proofUrl: string, proofDescription: string) {
    try {
      const tx = buildResubmitProof({ bountyId: bounty.id, proofUrl, proofDescription, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Proof resubmitted!', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Resubmit failed' });
    }
  }

  async function handleDisputeSubmit(reason: string) {
    try {
      const tx = buildDisputeRejection({ bountyId: bounty.id, reason, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Dispute raised!', digest });
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

  async function handleAutoResolve() {
    try {
      const tx = buildAutoResolveDispute({ bountyId: bounty.id, hunterAddr: ticket!.hunter, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Dispute auto-resolved in your favor!', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Auto-resolve failed' });
    }
  }

  async function handleWithdrawFromBounty() {
    try {
      const tx = buildWithdrawFromBounty({ bountyId: bounty.id, ticketId: ticket!.id, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Withdrawn from bounty. Stake returned!', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Withdraw failed' });
    }
  }

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

      {/* Kill Verify */}
      {ticket && taskType === TaskType.KILL && !isApproved && !proof && isActive && taskCreatedAt && (
        <KillVerifyButton
          bounty={bounty}
          targetVictimId={targetVictimId}
          createdAt={taskCreatedAt}
          onToast={onToast}
        />
      )}

      {/* Collect reward */}
      {canClaimReward && (
        <Button variant="primary" disabled={isPending} onClick={() => handleAction('reward')} className="w-full">
          {isPending ? 'COLLECTING...' : `COLLECT REWARD (${mistToSui(bounty.rewardAmount)} SUI)`}
        </Button>
      )}

      {/* Submit / Resubmit proof */}
      {canSubmitProof && <ProofForm mode="submit" isPending={isPending} onSubmit={handleProofSubmit} />}
      {canResubmitProof && <ProofForm mode="resubmit" isPending={isPending} onSubmit={handleProofResubmit} />}

      {/* Dispute rejection */}
      {canDisputeRejection && <DisputeForm isPending={isPending} onSubmit={handleDisputeSubmit} />}

      {/* Auto-approve */}
      {canAutoApprove && (
        <Button variant="primary" disabled={isPending} onClick={handleAutoApprove} className="w-full">
          {isPending ? 'APPROVING...' : 'AUTO-APPROVE (review period expired)'}
        </Button>
      )}

      {/* Auto-resolve dispute */}
      {canAutoResolve && (
        <Button variant="primary" disabled={isPending} onClick={handleAutoResolve} className="w-full">
          {isPending ? 'RESOLVING...' : 'AUTO-RESOLVE DISPUTE (timeout expired)'}
        </Button>
      )}

      {/* Status messages */}
      <HunterStatusMessages
        ticket={ticket}
        proof={proof}
        canAutoApprove={canAutoApprove}
        canAutoResolve={canAutoResolve}
        canSubmitProof={canSubmitProof}
        canClaimReward={canClaimReward}
        canAbandon={canAbandon}
        canWithdrawPenalty={canWithdrawPenalty}
        canDestroyTicket={canDestroyTicket}
        canWithdrawFromBounty={canWithdrawFromBounty}
        arbitratorConfig={arbitratorConfig}
        autoResolveRemaining={autoResolveRemaining}
      />

      {/* Withdraw from bounty */}
      {canWithdrawFromBounty && (
        <Button variant="secondary" disabled={isPending} onClick={handleWithdrawFromBounty} className="w-full">
          {isPending ? 'WITHDRAWING...' : 'WITHDRAW FROM BOUNTY (get stake back)'}
        </Button>
      )}

      {/* Abandon */}
      {canAbandon && !canWithdrawFromBounty && (
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
    </div>
  );
}
