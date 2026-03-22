import { useState } from 'react';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import { Textarea } from '../ui/Textarea';
import { useTransactionExecutor } from '../../hooks/useTransactionExecutor';
import { buildApproveHunter } from '../../lib/ptb/approve';
import { buildRejectProof } from '../../lib/ptb/reject-proof';
import { buildDestroyVerifierCap } from '../../lib/ptb/cleanup';
import { BountyStatus, LIMITS } from '../../lib/constants';
import type { ParsedBounty, ParsedVerifierCap, Toast } from '../../lib/types';

const INVALIDATE_KEYS = [['bountyDetail'], ['bountyList'], ['ownedVerifierCaps'], ['proofSubmission']];

interface VerifierActionsProps {
  bounty: ParsedBounty;
  verifierCap: ParsedVerifierCap;
  onToast: (t: Toast) => void;
}

export function VerifierActions({ bounty, verifierCap, onToast }: VerifierActionsProps) {
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);
  const [hunterAddr, setHunterAddr] = useState('');
  const [rejectionReason, setRejectionReason] = useState('');
  const [mode, setMode] = useState<'approve' | 'reject'>('approve');

  const canApprove = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;
  const isTerminal = bounty.status === BountyStatus.COMPLETED ||
    bounty.status === BountyStatus.CANCELLED ||
    bounty.status === BountyStatus.EXPIRED;

  const reasonValid = rejectionReason.trim().length > 0 && rejectionReason.trim().length <= LIMITS.MAX_REASON;

  async function handleApprove() {
    if (!hunterAddr.startsWith('0x')) return;
    try {
      const tx = buildApproveHunter({
        bountyId: bounty.id,
        hunterAddr,
        verifierCapId: verifierCap.id,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Hunter approved!', digest });
      setHunterAddr('');
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Approve failed' });
    }
  }

  async function handleRejectProof() {
    if (!hunterAddr.startsWith('0x') || !reasonValid) return;
    try {
      const tx = buildRejectProof({
        bountyId: bounty.id,
        hunterAddr,
        reason: rejectionReason.trim(),
        verifierCapId: verifierCap.id,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Proof rejected!', digest });
      setHunterAddr('');
      setRejectionReason('');
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Reject failed' });
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

      {canApprove && (
        <div className="space-y-2">
          <Input
            label="Hunter Address"
            value={hunterAddr}
            onChange={(e) => setHunterAddr(e.target.value)}
            placeholder="0x..."
          />

          {/* Mode toggle */}
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => setMode('approve')}
              className={`text-xs px-3 py-1 rounded font-heading tracking-wider transition-colors ${
                mode === 'approve'
                  ? 'bg-eve-cyan/20 text-eve-cyan border border-eve-cyan/40'
                  : 'text-eve-sub hover:text-eve-text'
              }`}
            >
              APPROVE
            </button>
            <button
              type="button"
              onClick={() => setMode('reject')}
              className={`text-xs px-3 py-1 rounded font-heading tracking-wider transition-colors ${
                mode === 'reject'
                  ? 'bg-eve-danger/20 text-eve-danger border border-eve-danger/40'
                  : 'text-eve-sub hover:text-eve-text'
              }`}
            >
              REJECT PROOF
            </button>
          </div>

          {mode === 'approve' && (
            <Button
              variant="primary"
              disabled={isPending || !hunterAddr.startsWith('0x')}
              onClick={handleApprove}
              className="w-full"
            >
              {isPending ? 'APPROVING...' : 'APPROVE HUNTER'}
            </Button>
          )}

          {mode === 'reject' && (
            <div className="space-y-2">
              <Textarea
                label="Rejection Reason"
                value={rejectionReason}
                onChange={(e) => setRejectionReason(e.target.value)}
                placeholder="Explain why the proof is insufficient..."
                hint={`${rejectionReason.length}/${LIMITS.MAX_REASON}`}
              />
              <Button
                variant="danger"
                disabled={isPending || !hunterAddr.startsWith('0x') || !reasonValid}
                onClick={handleRejectProof}
                className="w-full"
              >
                {isPending ? 'REJECTING...' : 'REJECT PROOF'}
              </Button>
            </div>
          )}
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
