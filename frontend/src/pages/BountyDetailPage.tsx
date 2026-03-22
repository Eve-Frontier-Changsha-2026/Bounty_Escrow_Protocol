import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { useBountyDetail } from '../hooks/useBountyDetail';
import { useUserRole } from '../hooks/useUserRole';
import { useProofSubmission } from '../hooks/useProofSubmission';
import { useReviewConfig } from '../hooks/useReviewConfig';
import { Panel } from '../components/ui/Panel';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { TransactionToast } from '../components/ui/TransactionToast';
import { StatusBadge } from '../components/bounty/StatusBadge';
import { CountdownTimer } from '../components/bounty/CountdownTimer';
import { BountyStats } from '../components/bounty/BountyStats';
import { ProofStatusPanel } from '../components/bounty/ProofStatusPanel';
import { CreatorActions } from '../components/actions/CreatorActions';
import { HunterActions } from '../components/actions/HunterActions';
import { VerifierActions } from '../components/actions/VerifierActions';
import { PublicActions } from '../components/actions/PublicActions';
import { truncateAddress, formatTimestamp, bpsToPercent, mistToSui } from '../lib/format';
import { BountyStatus, ProofStatus, LIMITS } from '../lib/constants';
import type { Toast } from '../lib/types';

export function BountyDetailPage() {
  const { bountyId } = useParams();
  const account = useCurrentAccount();
  const { data: bounty, isLoading, error } = useBountyDetail(bountyId);
  const { isCreator, isVerifier, ticket, verifierCap } = useUserRole(bounty);
  const { data: proof } = useProofSubmission(bountyId, account?.address);
  const { data: reviewPeriodMs } = useReviewConfig(bountyId);
  const [toast, setToast] = useState<Toast | null>(null);

  if (isLoading) {
    return (
      <div className="flex justify-center py-20">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error || !bounty) {
    return (
      <Panel className="text-center py-12">
        <p className="text-eve-danger text-sm mb-2">Bounty not found</p>
        <p className="text-eve-sub text-xs mb-4">{String(error ?? 'Unknown error')}</p>
        <Link to="/" className="text-eve-cyan text-sm hover:underline">&larr; Back to board</Link>
      </Panel>
    );
  }

  const isActive = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;
  const gracePeriodEnd = bounty.deadline + bounty.gracePeriod;
  const effectiveReviewPeriod = reviewPeriodMs ?? LIMITS.DEFAULT_REVIEW_PERIOD_MS;

  // Derive approval from proof status
  const isApproved = proof?.status === ProofStatus.APPROVED || proof?.status === ProofStatus.RESOLVED_APPROVED;

  return (
    <div className="max-w-3xl mx-auto">
      <Link to="/" className="text-eve-sub text-xs hover:text-eve-cyan transition-colors mb-4 inline-block">
        &larr; BACK TO BOARD
      </Link>

      {/* Header */}
      <Panel className="mb-4">
        <div className="flex items-start justify-between mb-4">
          <div className="flex-1">
            <h1 className="font-heading text-xl sm:text-2xl text-eve-text mb-2">{bounty.title}</h1>
            <div className="flex items-center gap-3 flex-wrap">
              <StatusBadge status={bounty.status} />
              <span className="text-xs text-eve-sub">
                Created by {truncateAddress(bounty.creator)}
                {isCreator && <span className="text-eve-gold ml-1">(you)</span>}
              </span>
            </div>
          </div>
        </div>

        {bounty.description && (
          <p className="text-sm text-eve-sub mb-4 whitespace-pre-wrap">{bounty.description}</p>
        )}

        <BountyStats
          rewardAmount={bounty.rewardAmount}
          requiredStake={bounty.requiredStake}
          activeClaims={bounty.activeClaims}
          maxClaims={bounty.maxClaims}
          escrowValue={bounty.escrowValue}
        />
      </Panel>

      {/* Timing Info */}
      <Panel className="mb-4">
        <h2 className="font-heading text-xs text-eve-gold tracking-wider mb-3">TIMING</h2>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 text-center">
          <div>
            <div className="text-xs text-eve-sub">Deadline</div>
            <div className="text-sm text-eve-text">{formatTimestamp(bounty.deadline)}</div>
          </div>
          <div>
            <div className="text-xs text-eve-sub">Grace End</div>
            <div className="text-sm text-eve-text">{formatTimestamp(gracePeriodEnd)}</div>
          </div>
          <div>
            <div className="text-xs text-eve-sub">Cleanup Reward</div>
            <div className="text-sm text-eve-gold">{bpsToPercent(bounty.cleanupRewardBps)}</div>
          </div>
          <div>
            <div className="text-xs text-eve-sub">Completed</div>
            <div className="text-sm text-eve-text">{bounty.completedClaims} / {bounty.maxClaims}</div>
          </div>
        </div>

        {isActive && (
          <div className="mt-4 pt-3 border-t border-eve-panel-border/50 flex flex-wrap gap-4">
            <CountdownTimer targetMs={bounty.deadline} label="Deadline in" />
            {Date.now() > bounty.deadline && (
              <CountdownTimer targetMs={gracePeriodEnd} label="Grace ends in" />
            )}
          </div>
        )}
      </Panel>

      {/* Proof Status */}
      {proof && (
        <ProofStatusPanel proof={proof} reviewPeriodMs={effectiveReviewPeriod} />
      )}

      {/* Details */}
      <Panel className="mb-4">
        <h2 className="font-heading text-xs text-eve-gold tracking-wider mb-3">DETAILS</h2>
        <div className="space-y-2 text-xs">
          <div className="flex justify-between">
            <span className="text-eve-sub">Bounty ID</span>
            <span className="font-mono text-eve-text truncate ml-4 max-w-[300px]">{bounty.id}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-eve-sub">Coin Type</span>
            <span className="font-mono text-eve-text">{bounty.coinType === '0x2::sui::SUI' ? 'SUI' : truncateAddress(bounty.coinType)}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-eve-sub">Stake Pool</span>
            <span className="text-eve-text">{mistToSui(bounty.stakePoolValue)} SUI</span>
          </div>
        </div>
      </Panel>

      {/* Actions */}
      {account && (
        <Panel className="mb-4 space-y-4">
          <h2 className="font-heading text-xs text-eve-gold tracking-wider">ACTIONS</h2>

          {isCreator && (
            <CreatorActions bounty={bounty} onToast={setToast} />
          )}

          {!isCreator && (
            <HunterActions
              bounty={bounty}
              ticket={ticket}
              isApproved={isApproved ?? false}
              proof={proof ?? null}
              reviewPeriodMs={effectiveReviewPeriod}
              onToast={setToast}
            />
          )}

          {isVerifier && verifierCap && (
            <VerifierActions
              bounty={bounty}
              verifierCap={verifierCap}
              onToast={setToast}
            />
          )}

          <PublicActions bounty={bounty} onToast={setToast} />
        </Panel>
      )}

      {toast && (
        <TransactionToast
          type={toast.type}
          message={toast.message}
          digest={toast.digest}
          onClose={() => setToast(null)}
        />
      )}
    </div>
  );
}

export default BountyDetailPage;
