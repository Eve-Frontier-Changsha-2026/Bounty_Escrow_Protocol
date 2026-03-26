import { useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { useBountyDetail } from '../hooks/useBountyDetail';
import { useUserRole } from '../hooks/useUserRole';
import { useProofSubmission } from '../hooks/useProofSubmission';
import { useReviewConfig } from '../hooks/useReviewConfig';
import { useRejectionHistory } from '../hooks/useRejectionHistory';
import { useArbitratorConfig } from '../hooks/useArbitratorConfig';
import { useDisputeTimestamp } from '../hooks/useDisputeTimestamp';
import { useTaskType } from '../hooks/useTaskType';
import { useCriteria } from '../hooks/useCriteria';
import { useTargetVictim } from '../hooks/useTargetVictim';
import { useEncryptionState } from '../hooks/useEncryptionState';
import { useEncryptedDetails } from '../hooks/useEncryptedDetails';
import { useViewerReceipt } from '../hooks/useViewerReceipt';
import { useSealDecrypt } from '../hooks/useSealDecrypt';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildMintViewerReceipt } from '../lib/ptb/mint-viewer-receipt';
import { Panel } from '../components/ui/Panel';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { TransactionToast } from '../components/ui/TransactionToast';
import { StatusBadge } from '../components/bounty/StatusBadge';
import { TaskTypeBadge } from '../components/bounty/TaskTypeBadge';
import { CountdownTimer } from '../components/bounty/CountdownTimer';
import { BountyStats } from '../components/bounty/BountyStats';
import { ProofStatusPanel } from '../components/bounty/ProofStatusPanel';
import { CreatorActions } from '../components/actions/CreatorActions';
import { HunterActions } from '../components/actions/HunterActions';
import { VerifierActions } from '../components/actions/VerifierActions';
import { PublicActions } from '../components/actions/PublicActions';
import { truncateAddress, formatTimestamp, bpsToPercent, mistToSui } from '../lib/format';
import { BountyStatus, ProofStatus, TaskType, TASK_TYPE_LABEL, LIMITS } from '../lib/constants';
import type { Toast } from '../lib/types';

const VERIFICATION_MODE_LABEL: Record<number, string> = {
  0: 'MANUAL',
  1: 'AUTO',
  2: 'ORACLE',
  3: 'HYBRID',
};

const DECRYPT_INVALIDATE_KEYS = [['viewerReceipt']];

export function BountyDetailPage() {
  const { bountyId } = useParams();
  const account = useCurrentAccount();
  const { data: bounty, isLoading, error } = useBountyDetail(bountyId);
  const { isCreator, isVerifier, ticket, verifierCap } = useUserRole(bounty);
  const { data: proof, error: proofError } = useProofSubmission(bountyId, account?.address);
  const { data: reviewPeriodMs } = useReviewConfig(bountyId);
  const { data: rejections } = useRejectionHistory(bountyId, account?.address);
  const { data: arbitratorConfig } = useArbitratorConfig(bountyId);
  const { data: disputeTimestamp } = useDisputeTimestamp(bountyId, account?.address);

  // v7 hooks
  const { data: taskTypeConfig } = useTaskType(bountyId);
  const { data: criteria } = useCriteria(bountyId, taskTypeConfig?.taskType);
  const { data: targetVictim } = useTargetVictim(bountyId);
  const { data: encryptionState } = useEncryptionState(bountyId);
  const { data: encryptedDetails } = useEncryptedDetails(bountyId);
  const { data: viewerReceipt } = useViewerReceipt(account?.address, bountyId);

  // Decrypt state
  const { decrypt, isPending: isDecrypting, error: decryptError, clearError: clearDecryptError } = useSealDecrypt();
  const { execute: executeTx, isPending: isMintingReceipt } = useTransactionExecutor(DECRYPT_INVALIDATE_KEYS);
  const [decryptedText, setDecryptedText] = useState<string | null>(null);

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
  const isApproved = proof?.status === ProofStatus.APPROVED || proof?.status === ProofStatus.RESOLVED_APPROVED;

  const taskType = taskTypeConfig?.taskType ?? TaskType.CUSTOM;
  const isEncrypted = encryptionState?.isEncrypted ?? false;
  const hasEncryptedPayload = encryptedDetails && encryptedDetails.encryptedPayload.length > 0;
  const isHunter = !!ticket;

  async function handleMintReceipt() {
    if (!bountyId) return;
    try {
      const tx = buildMintViewerReceipt({ bountyId, coinType: bounty!.coinType });
      const digest = await executeTx(tx);
      setToast({ type: 'success', message: 'Viewer receipt minted', digest });
    } catch (e) {
      setToast({ type: 'error', message: e instanceof Error ? e.message : 'Mint failed' });
    }
  }

  async function handleDecrypt() {
    if (!bountyId || !encryptedDetails || !viewerReceipt) return;
    clearDecryptError();
    try {
      const plaintext = await decrypt({
        encryptedData: encryptedDetails.encryptedPayload,
        bountyId,
        viewerReceiptId: viewerReceipt.id,
      });
      setDecryptedText(new TextDecoder().decode(plaintext));
    } catch {
      // error is set in useSealDecrypt
    }
  }

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
              <TaskTypeBadge taskType={taskType} />
              {isEncrypted && (
                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-heading tracking-wider border text-eve-accent bg-eve-accent/10 border-eve-accent/30">
                  ENCRYPTED
                </span>
              )}
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

      {/* Task Type & Criteria */}
      {taskType !== TaskType.CUSTOM && (
        <Panel className="mb-4">
          <h2 className="font-heading text-xs text-eve-gold tracking-wider mb-3">TASK TYPE</h2>
          <div className="space-y-3">
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-4 text-xs">
              <div>
                <span className="text-eve-sub">Type</span>
                <div className="text-eve-text mt-0.5">{TASK_TYPE_LABEL[taskType] ?? 'UNKNOWN'}</div>
              </div>
              <div>
                <span className="text-eve-sub">Verification</span>
                <div className="text-eve-text mt-0.5">
                  {VERIFICATION_MODE_LABEL[taskTypeConfig?.verificationMode ?? 0] ?? 'MANUAL'}
                </div>
              </div>
              {targetVictim && (
                <div>
                  <span className="text-eve-sub">Target Victim</span>
                  <div className="text-eve-danger mt-0.5 font-mono">ID #{targetVictim.victimId}</div>
                </div>
              )}
            </div>

            {/* Criteria details */}
            {criteria && (
              <div className="pt-3 border-t border-eve-panel-border/50">
                <div className="text-xs text-eve-sub mb-2">CRITERIA</div>
                {criteria.type === 'kill' && (
                  <div className="grid grid-cols-3 gap-4 text-xs">
                    <div>
                      <span className="text-eve-sub">Solar System</span>
                      <div className="text-eve-text mt-0.5 font-mono">{criteria.data.solarSystemId === '0' ? 'Any' : criteria.data.solarSystemId}</div>
                    </div>
                    <div>
                      <span className="text-eve-sub">Loss Type</span>
                      <div className="text-eve-text mt-0.5">{criteria.data.lossType || 'Any'}</div>
                    </div>
                    <div>
                      <span className="text-eve-sub">Min Kills</span>
                      <div className="text-eve-text mt-0.5">{criteria.data.minKills}</div>
                    </div>
                  </div>
                )}
                {criteria.type === 'delivery' && (
                  <div className="grid grid-cols-3 gap-4 text-xs">
                    <div>
                      <span className="text-eve-sub">Item Type</span>
                      <div className="text-eve-text mt-0.5 font-mono">{criteria.data.itemTypeId}</div>
                    </div>
                    <div>
                      <span className="text-eve-sub">Min Quantity</span>
                      <div className="text-eve-text mt-0.5">{criteria.data.minQuantity}</div>
                    </div>
                    <div>
                      <span className="text-eve-sub">Target Assembly</span>
                      <div className="text-eve-text mt-0.5 font-mono truncate">{truncateAddress(criteria.data.targetAssemblyId)}</div>
                    </div>
                  </div>
                )}
                {criteria.type === 'build' && (
                  <div className="grid grid-cols-2 gap-4 text-xs">
                    <div>
                      <span className="text-eve-sub">Assembly Type</span>
                      <div className="text-eve-text mt-0.5 font-mono">{criteria.data.assemblyTypeId}</div>
                    </div>
                    <div>
                      <span className="text-eve-sub">Solar System</span>
                      <div className="text-eve-text mt-0.5 font-mono">{criteria.data.solarSystemId === '0' ? 'Any' : criteria.data.solarSystemId}</div>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Encrypted criteria notice */}
            {isEncrypted && !criteria && taskType !== TaskType.INTEL && (
              <div className="pt-3 border-t border-eve-panel-border/50">
                <p className="text-xs text-eve-accent">
                  Criteria are encrypted. Decrypt the bounty details below to view full requirements.
                </p>
              </div>
            )}
          </div>
        </Panel>
      )}

      {/* Encrypted Details */}
      {hasEncryptedPayload && (
        <Panel className="mb-4">
          <h2 className="font-heading text-xs text-eve-gold tracking-wider mb-3">ENCRYPTED DETAILS</h2>

          {decryptedText !== null ? (
            <div>
              <div className="text-xs text-eve-sub mb-2">DECRYPTED CONTENT</div>
              <pre className="text-sm text-eve-text whitespace-pre-wrap bg-eve-dark/50 rounded p-3 border border-eve-panel-border/50 max-h-60 overflow-y-auto">
                {decryptedText}
              </pre>
            </div>
          ) : (
            <div className="space-y-3">
              <p className="text-xs text-eve-sub">
                This bounty has encrypted details ({encryptedDetails!.encryptedPayload.length} bytes).
                {encryptionState?.encryptedAt
                  ? ` Encrypted on ${formatTimestamp(encryptionState.encryptedAt)}.`
                  : ''}
              </p>

              {/* Decrypt flow for connected users */}
              {account && (
                <div className="flex items-center gap-3">
                  {!viewerReceipt && isHunter && (
                    <button
                      onClick={handleMintReceipt}
                      disabled={isMintingReceipt}
                      className="px-3 py-1.5 text-xs font-heading tracking-wider bg-eve-accent/20 border border-eve-accent/40 text-eve-accent rounded hover:bg-eve-accent/30 transition-colors disabled:opacity-50"
                    >
                      {isMintingReceipt ? 'MINTING...' : '1. MINT VIEWER RECEIPT'}
                    </button>
                  )}
                  {viewerReceipt && (
                    <button
                      onClick={handleDecrypt}
                      disabled={isDecrypting}
                      className="px-3 py-1.5 text-xs font-heading tracking-wider bg-eve-cyan/20 border border-eve-cyan/40 text-eve-cyan rounded hover:bg-eve-cyan/30 transition-colors disabled:opacity-50"
                    >
                      {isDecrypting ? 'DECRYPTING...' : 'DECRYPT'}
                    </button>
                  )}
                  {!viewerReceipt && !isHunter && !isCreator && (
                    <p className="text-xs text-eve-sub">Claim this bounty first to access encrypted details.</p>
                  )}
                  {!viewerReceipt && isCreator && (
                    <p className="text-xs text-eve-sub">You encrypted these details. Use your backup key to decrypt locally.</p>
                  )}
                </div>
              )}

              {decryptError && (
                <p className="text-xs text-eve-danger">{decryptError}</p>
              )}
            </div>
          )}
        </Panel>
      )}

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

      {/* Arbitrator Info */}
      {arbitratorConfig && (
        <Panel className="mb-4">
          <h2 className="font-heading text-xs text-eve-gold tracking-wider mb-3">ARBITRATOR</h2>
          <div className="grid grid-cols-2 gap-4 text-center">
            <div>
              <div className="text-xs text-eve-sub">Address</div>
              <div className="text-sm text-eve-text font-mono">{truncateAddress(arbitratorConfig.arbitrator)}</div>
            </div>
            <div>
              <div className="text-xs text-eve-sub">Dispute Timeout</div>
              <div className="text-sm text-eve-text">{Math.round(arbitratorConfig.disputeTimeoutMs / 86_400_000)} days</div>
            </div>
          </div>
        </Panel>
      )}

      {/* Claimed Hunters */}
      {bounty.hunters.length > 0 && (
        <Panel className="mb-4">
          <h2 className="font-heading text-xs text-eve-gold tracking-wider mb-3">CLAIMED HUNTERS</h2>
          <div className="space-y-1">
            {bounty.hunters.map(h => (
              <div key={h} className="flex items-center gap-2 text-xs font-mono">
                <span className={h === account?.address ? 'text-eve-cyan' : 'text-eve-sub'}>
                  {truncateAddress(h)}
                </span>
                {h === account?.address && <span className="text-eve-gold text-[10px]">(you)</span>}
              </div>
            ))}
          </div>
        </Panel>
      )}

      {/* Proof Status */}
      {proof && (
        <ProofStatusPanel proof={proof} reviewPeriodMs={effectiveReviewPeriod} rejections={rejections ?? []} />
      )}
      {proofError && (
        <Panel className="mb-4 border-eve-danger/50">
          <p className="text-xs text-eve-danger">Proof query error: {String(proofError)}</p>
        </Panel>
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
            <CreatorActions bounty={bounty} arbitratorConfig={arbitratorConfig ?? null} onToast={setToast} />
          )}

          {!isCreator && (
            <HunterActions
              bounty={bounty}
              ticket={ticket}
              isApproved={isApproved ?? false}
              proof={proof ?? null}
              reviewPeriodMs={effectiveReviewPeriod}
              arbitratorConfig={arbitratorConfig ?? null}
              disputeTimestamp={disputeTimestamp ?? null}
              onToast={setToast}
              taskType={taskType}
              targetVictimId={targetVictim?.victimId}
              taskCreatedAt={taskTypeConfig?.createdAt}
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
