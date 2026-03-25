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

// === v5 Task Type ===

export interface TaskTypeConfig {
  taskType: number;
  verificationMode: number;
  createdAt: number;
}

export interface KillCriteria {
  solarSystemId: number;
  lossType: number;
  minKills: number;
}

export interface DeliveryCriteria {
  itemTypeId: number;
  minQuantity: number;
  targetAssemblyId: string; // address hex
}

export interface BuildCriteria {
  assemblyTypeId: number;
  solarSystemId: number;
}

// === v7 Encrypted Details ===

export interface TargetVictim {
  victimId: number;
}

export interface EncryptionState {
  isEncrypted: boolean;
  encryptedAt: number;
}

export interface EncryptedDetails {
  encryptedPayload: Uint8Array;
  createdAt: number;
}

export interface ParsedViewerReceipt {
  id: string;
  viewer: string;
  bountyId: string;
}

export interface Toast {
  type: 'success' | 'error';
  message: string;
  digest?: string;
}
