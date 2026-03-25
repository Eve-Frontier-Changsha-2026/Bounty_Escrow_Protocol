import { useState } from 'react';
import { Button } from '../ui/Button';
import { Textarea } from '../ui/Textarea';
import { useTransactionExecutor } from '../../hooks/useTransactionExecutor';
import { useHunterProofs } from '../../hooks/useProofSubmission';
import { buildApproveHunter } from '../../lib/ptb/approve';
import { buildRejectProof } from '../../lib/ptb/reject-proof';
import { buildDestroyVerifierCap } from '../../lib/ptb/cleanup';
import { BountyStatus, ProofStatus, PROOF_STATUS_LABEL, LIMITS } from '../../lib/constants';
import { truncateAddress } from '../../lib/format';
import type { ParsedBounty, ParsedVerifierCap, Toast } from '../../lib/types';

const INVALIDATE_KEYS = [['bountyDetail'], ['bountyList'], ['ownedVerifierCaps'], ['proofSubmission']];

interface VerifierActionsProps {
  bounty: ParsedBounty;
  verifierCap: ParsedVerifierCap;
  onToast: (t: Toast) => void;
}

export function VerifierActions({ bounty, verifierCap, onToast }: VerifierActionsProps) {
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);
  const proofQueries = useHunterProofs(bounty.id, bounty.hunters);
  const [rejectTarget, setRejectTarget] = useState<string | null>(null);
  const [rejectionReason, setRejectionReason] = useState('');
  const [pendingAddr, setPendingAddr] = useState<string | null>(null);

  const canAct = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;
  const isTerminal = bounty.status === BountyStatus.COMPLETED ||
    bounty.status === BountyStatus.CANCELLED ||
    bounty.status === BountyStatus.EXPIRED;

  const reasonValid = rejectionReason.trim().length > 0 && rejectionReason.trim().length <= LIMITS.MAX_REASON;

  async function handleApprove(hunterAddr: string) {
    setPendingAddr(hunterAddr);
    try {
      const tx = buildApproveHunter({
        bountyId: bounty.id,
        hunterAddr,
        verifierCapId: verifierCap.id,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: `Hunter ${truncateAddress(hunterAddr)} approved!`, digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Approve failed' });
    } finally {
      setPendingAddr(null);
    }
  }

  async function handleRejectProof() {
    if (!rejectTarget || !reasonValid) return;
    setPendingAddr(rejectTarget);
    try {
      const tx = buildRejectProof({
        bountyId: bounty.id,
        hunterAddr: rejectTarget,
        reason: rejectionReason.trim(),
        verifierCapId: verifierCap.id,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: `Proof from ${truncateAddress(rejectTarget)} rejected!`, digest });
      setRejectTarget(null);
      setRejectionReason('');
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Reject failed' });
    } finally {
      setPendingAddr(null);
    }
  }

  async function handleDestroyCap() {
    try {
      const tx = buildDestroyVerifierCap({
        capId: verifierCap.id,
        bountyId: bounty.id,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Verifier cap destroyed!', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Destroy failed' });
    }
  }

  return (
    <div className="space-y-3">
      <h3 className="font-heading text-xs text-eve-cyan tracking-wider">VERIFIER ACTIONS</h3>

      {canAct && bounty.hunters.length > 0 && (
        <div className="space-y-2">
          {bounty.hunters.map((hunter, i) => {
            const proofQuery = proofQueries[i];
            const proof = proofQuery?.data;
            const proofStatus = proof?.status;
            const isActionable = proofStatus === ProofStatus.SUBMITTED;
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
                    proofStatus === ProofStatus.APPROVED || proofStatus === ProofStatus.RESOLVED_APPROVED
                      ? 'text-green-400'
                      : proofStatus === ProofStatus.REJECTED || proofStatus === ProofStatus.RESOLVED_REJECTED
                        ? 'text-eve-danger'
                        : proofStatus === ProofStatus.DISPUTED
                          ? 'text-yellow-400'
                          : proofStatus === ProofStatus.SUBMITTED
                            ? 'text-eve-cyan'
                            : 'text-eve-sub'
                  }`}>
                    {proof ? PROOF_STATUS_LABEL[proofStatus!] ?? `STATUS ${proofStatus}` : 'NO PROOF'}
                  </span>
                </div>

                {/* Show proof content if submitted */}
                {proof && (
                  <div className="text-[11px] text-eve-sub space-y-1">
                    {proof.proofUrl && (
                      <p className="truncate">URL: <span className="text-eve-text">{proof.proofUrl}</span></p>
                    )}
                    {proof.proofDescription && (
                      <p className="truncate">Desc: <span className="text-eve-text">{proof.proofDescription}</span></p>
                    )}
                    {proof.rejectionReason && (
                      <p className="truncate">Rejection: <span className="text-eve-danger">{proof.rejectionReason}</span></p>
                    )}
                  </div>
                )}

                {/* Action buttons — only when proof is SUBMITTED (reviewable) */}
                {isActionable && (
                  <div className="flex gap-2 pt-1">
                    <Button
                      variant="primary"
                      disabled={busy}
                      onClick={() => handleApprove(hunter)}
                      className="text-xs !px-3 !py-1 flex-1"
                    >
                      {busy ? '...' : 'APPROVE'}
                    </Button>
                    <Button
                      variant="danger"
                      disabled={busy}
                      onClick={() => { setRejectTarget(hunter); setRejectionReason(''); }}
                      className="text-xs !px-3 !py-1 flex-1"
                    >
                      REJECT
                    </Button>
                  </div>
                )}

                {/* Status messages for non-actionable states */}
                {!proof && (
                  <p className="text-[10px] text-eve-sub italic">Waiting for hunter to submit proof...</p>
                )}
                {proofStatus === ProofStatus.REJECTED && !proof?.hasResubmitted && (
                  <p className="text-[10px] text-eve-sub italic">Rejected. Waiting for hunter to resubmit...</p>
                )}
                {proofStatus === ProofStatus.DISPUTED && (
                  <p className="text-[10px] text-yellow-400 italic">Disputed. Pending creator resolution...</p>
                )}
                {(proofStatus === ProofStatus.APPROVED || proofStatus === ProofStatus.RESOLVED_APPROVED) && (
                  <p className="text-[10px] text-green-400 italic">Approved. Hunter can claim reward.</p>
                )}
              </div>
            );
          })}
        </div>
      )}

      {canAct && bounty.hunters.length === 0 && (
        <p className="text-xs text-eve-sub">No hunters have claimed this bounty yet.</p>
      )}

      {/* Reject reason modal */}
      {rejectTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
          <div className="w-full max-w-md mx-4 p-5 bg-eve-bg-2 rounded-xl border border-eve-danger/40 shadow-lg space-y-4">
            <h4 className="font-heading text-sm text-eve-danger tracking-wider">
              REJECT PROOF
            </h4>
            <p className="text-xs text-eve-sub">
              Hunter: <span className="font-mono text-eve-text">{truncateAddress(rejectTarget)}</span>
            </p>
            <Textarea
              label="Rejection Reason"
              value={rejectionReason}
              onChange={(e) => setRejectionReason(e.target.value)}
              placeholder="Explain why the proof is insufficient..."
              hint={`${rejectionReason.length}/${LIMITS.MAX_REASON}`}
            />
            <div className="flex gap-2">
              <Button
                variant="danger"
                disabled={isPending || !reasonValid}
                onClick={handleRejectProof}
                className="flex-1"
              >
                {isPending ? 'REJECTING...' : 'CONFIRM REJECT'}
              </Button>
              <Button
                variant="secondary"
                onClick={() => { setRejectTarget(null); setRejectionReason(''); }}
              >
                CANCEL
              </Button>
            </div>
          </div>
        </div>
      )}

      {isTerminal && (
        <Button variant="secondary" disabled={isPending} onClick={handleDestroyCap} className="w-full">
          {isPending ? 'DESTROYING...' : 'DESTROY VERIFIER CAP (cleanup)'}
        </Button>
      )}
    </div>
  );
}
