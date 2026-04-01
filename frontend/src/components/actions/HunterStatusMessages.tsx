import { ProofStatus } from '../../lib/constants';
import type { ParsedProofSubmission, ParsedClaimTicket } from '../../lib/types';
import type { ArbitratorConfig } from '../../hooks/useArbitratorConfig';

interface HunterStatusMessagesProps {
  ticket: ParsedClaimTicket | null;
  proof: ParsedProofSubmission | null;
  canAutoApprove: boolean;
  canAutoResolve: boolean;
  canSubmitProof: boolean;
  canClaimReward: boolean;
  canAbandon: boolean;
  canWithdrawPenalty: boolean;
  canDestroyTicket: boolean;
  canWithdrawFromBounty: boolean;
  arbitratorConfig: ArbitratorConfig | null;
  autoResolveRemaining: number;
}

function formatCountdown(ms: number): string {
  const days = Math.floor(ms / 86_400_000);
  const hours = Math.floor((ms % 86_400_000) / 3_600_000);
  if (days > 0) return `${days}d ${hours}h`;
  const minutes = Math.floor((ms % 3_600_000) / 60_000);
  return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
}

export function HunterStatusMessages({
  ticket,
  proof,
  canAutoApprove,
  canAutoResolve,
  canSubmitProof,
  canClaimReward,
  canAbandon,
  canWithdrawPenalty,
  canDestroyTicket,
  canWithdrawFromBounty,
  arbitratorConfig,
  autoResolveRemaining,
}: HunterStatusMessagesProps) {
  if (!ticket) return null;

  return (
    <>
      {proof?.status === ProofStatus.SUBMITTED && !canAutoApprove && (
        <p className="text-xs text-eve-sub">Proof submitted. Waiting for verifier review...</p>
      )}
      {proof?.status === ProofStatus.DISPUTED && !canAutoResolve && (
        <div className="space-y-1">
          <p className="text-xs text-eve-sub">
            Dispute pending {arbitratorConfig ? 'arbitrator' : 'creator'} resolution...
          </p>
          {autoResolveRemaining > 0 && (
            <p className="text-[10px] text-eve-gold">
              Auto-resolve in {formatCountdown(autoResolveRemaining)}
            </p>
          )}
        </div>
      )}
      {proof?.status === ProofStatus.RESOLVED_REJECTED && (
        <p className="text-xs text-eve-danger">Dispute was resolved against you.</p>
      )}
      {!proof && !canSubmitProof && !canClaimReward && !canAbandon && !canWithdrawPenalty && !canDestroyTicket && !canWithdrawFromBounty && (
        <p className="text-xs text-eve-sub">Waiting for verifier approval...</p>
      )}
    </>
  );
}
