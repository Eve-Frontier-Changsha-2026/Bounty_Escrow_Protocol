export interface ParsedBounty {
  id: string;
  version: number;
  creator: string;
  title: string;
  description: string;
  escrowValue: bigint;
  stakePoolValue: bigint;
  rewardAmount: bigint;
  requiredStake: bigint;
  cleanupRewardBps: number;
  deadline: number;
  gracePeriod: number;
  status: number;
  maxClaims: number;
  activeClaims: number;
  completedClaims: number;
  coinType: string;
  hunters: string[];
}

export interface ParsedClaimTicket {
  id: string;
  bountyId: string;
  hunter: string;
  stakeAmount: bigint;
  claimedAt: number;
}

export interface ParsedVerifierCap {
  id: string;
  bountyId: string;
}

export interface BountyCreatedEvent {
  bounty_id: string;
  creator: string;
  coin_type: string;
  reward_amount: string;
  required_stake: string;
  max_claims: string;
  deadline: string;
  grace_period: string;
  verifier: string;
}

export interface ParsedProofSubmission {
  proofUrl: string;
  proofDescription: string;
  submittedAt: number;
  status: number;
  rejectionReason: string;
  disputeReason: string;
  resolvedBy: string;
  resolvedAt: number;
  hasResubmitted: boolean;
}

export interface Toast {
  type: 'success' | 'error';
  message: string;
  digest?: string;
}
