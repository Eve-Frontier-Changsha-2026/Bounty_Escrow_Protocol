import { Panel } from '../ui/Panel';
import { CountdownTimer } from './CountdownTimer';
import { PROOF_STATUS_LABEL, PROOF_STATUS_COLOR, ProofStatus } from '../../lib/constants';
import { formatTimestamp, truncateAddress } from '../../lib/format';
import type { ParsedProofSubmission } from '../../lib/types';
import type { RejectionRecord } from '../../hooks/useRejectionHistory';

interface ProofStatusPanelProps {
  proof: ParsedProofSubmission;
  reviewPeriodMs: number;
  rejections: RejectionRecord[];
}

export function ProofStatusPanel({ proof, reviewPeriodMs, rejections }: ProofStatusPanelProps) {
  const label = PROOF_STATUS_LABEL[proof.status] ?? 'UNKNOWN';
  const color = PROOF_STATUS_COLOR[proof.status] ?? 'text-eve-sub';
  const reviewDeadline = proof.submittedAt + reviewPeriodMs;
  const showReviewCountdown = proof.status === ProofStatus.SUBMITTED && Date.now() < reviewDeadline;

  return (
    <Panel className="mb-4">
      <h2 className="font-heading text-xs text-eve-gold tracking-wider mb-3">PROOF STATUS</h2>

      <div className="space-y-3">
        {/* Status badge */}
        <div className="flex items-center gap-2">
          <span className={`font-heading text-sm ${color}`}>{label}</span>
          {proof.hasResubmitted && (
            <span className="text-xs text-eve-sub bg-eve-bg-2 px-2 py-0.5 rounded">RESUBMITTED</span>
          )}
        </div>

        {/* Proof URL */}
        <div className="text-xs">
          <span className="text-eve-sub">Proof URL: </span>
          <a
            href={proof.proofUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="text-eve-cyan hover:underline break-all"
          >
            {proof.proofUrl}
          </a>
        </div>

        {/* Proof description */}
        {proof.proofDescription && (
          <div className="text-xs">
            <span className="text-eve-sub">Description: </span>
            <span className="text-eve-text whitespace-pre-wrap">{proof.proofDescription}</span>
          </div>
        )}

        {/* Submitted timestamp */}
        <div className="text-xs text-eve-sub">
          Submitted at {formatTimestamp(proof.submittedAt)}
        </div>

        {/* Review countdown */}
        {showReviewCountdown && (
          <div className="pt-2 border-t border-eve-panel-border/50">
            <CountdownTimer targetMs={reviewDeadline} label="Auto-approve in" />
          </div>
        )}

        {/* Rejection history (all events) */}
        {rejections.length > 0 && (
          <div className="pt-2 border-t border-eve-panel-border/50 space-y-3">
            <div className="text-xs text-eve-danger font-heading tracking-wider">
              REJECTION HISTORY ({rejections.length})
            </div>
            {rejections.map((r, i) => (
              <div key={i} className="pl-3 border-l-2 border-eve-danger/40 space-y-0.5">
                <p className="text-xs text-eve-text whitespace-pre-wrap">{r.reason}</p>
                <p className="text-[10px] text-eve-sub">
                  By {truncateAddress(r.verifier)} at {formatTimestamp(r.rejectedAt)}
                </p>
              </div>
            ))}
          </div>
        )}

        {/* Dispute reason */}
        {proof.status === ProofStatus.DISPUTED && proof.disputeReason && (
          <div className="pt-2 border-t border-eve-panel-border/50">
            <div className="text-xs text-eve-gold">
              <span className="font-heading tracking-wider">DISPUTE REASON</span>
            </div>
            <p className="text-xs text-eve-text mt-1 whitespace-pre-wrap">{proof.disputeReason}</p>
          </div>
        )}

        {/* Resolved dispute */}
        {(proof.status === ProofStatus.RESOLVED_APPROVED || proof.status === ProofStatus.RESOLVED_REJECTED) && (
          <div className="pt-2 border-t border-eve-panel-border/50">
            <div className={`text-xs ${proof.status === ProofStatus.RESOLVED_APPROVED ? 'text-status-completed' : 'text-eve-danger'}`}>
              <span className="font-heading tracking-wider">
                DISPUTE {proof.status === ProofStatus.RESOLVED_APPROVED ? 'APPROVED' : 'REJECTED'}
              </span>
            </div>
            {proof.resolvedBy && proof.resolvedBy !== '0x0000000000000000000000000000000000000000000000000000000000000000' && (
              <div className="text-xs text-eve-sub mt-1">
                By {truncateAddress(proof.resolvedBy)} at {formatTimestamp(proof.resolvedAt)}
              </div>
            )}
          </div>
        )}
      </div>
    </Panel>
  );
}
