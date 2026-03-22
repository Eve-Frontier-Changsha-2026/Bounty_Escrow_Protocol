export const BountyStatus = {
  OPEN: 0,
  CLAIMED: 1,
  COMPLETED: 2,
  CANCELLED: 3,
  EXPIRED: 4,
} as const;

export type BountyStatusValue = (typeof BountyStatus)[keyof typeof BountyStatus];

export const STATUS_LABEL: Record<number, string> = {
  0: 'OPEN',
  1: 'CLAIMED',
  2: 'COMPLETED',
  3: 'CANCELLED',
  4: 'EXPIRED',
};

export const STATUS_COLOR: Record<number, string> = {
  0: 'text-status-open',
  1: 'text-status-claimed',
  2: 'text-status-completed',
  3: 'text-status-cancelled',
  4: 'text-status-expired',
};

export const STATUS_BG: Record<number, string> = {
  0: 'bg-status-open/15 border-status-open/40',
  1: 'bg-status-claimed/15 border-status-claimed/40',
  2: 'bg-status-completed/15 border-status-completed/40',
  3: 'bg-status-cancelled/15 border-status-cancelled/40',
  4: 'bg-status-expired/15 border-status-expired/40',
};

export const ERROR_MESSAGES: Record<number, string> = {
  0: 'Insufficient escrow funds',
  1: 'Deadline too soon (min 1 hour)',
  2: 'Deadline too far (max 1 year)',
  3: 'Cleanup reward too high (max 10%)',
  4: 'Title too long (max 256 chars)',
  5: 'Title cannot be empty',
  6: 'Description too long (max 2048 chars)',
  7: 'Bounty is not open',
  8: 'Maximum claims reached',
  9: 'Insufficient stake',
  10: 'Deadline has passed',
  11: 'Creator cannot claim own bounty',
  12: 'Already claimed this bounty',
  13: 'Not the bounty creator',
  14: 'Bounty cannot be cancelled',
  15: 'Insufficient escrow for penalty',
  16: 'Invalid verifier capability',
  17: 'Hunter is not active',
  18: 'Insufficient escrow for reward',
  19: 'Not the ticket owner',
  20: 'Grace period has not passed',
  21: 'Bounty is not active',
  22: 'Max claims cannot be zero',
  23: 'Reward amount cannot be zero',
  24: 'Max claims too high (max 100)',
  25: 'Bounty is not in terminal state',
  26: 'Ticket/bounty mismatch',
  27: 'Hunter is not approved',
  28: 'Bounty is not cancelled',
  29: 'Hunters have not withdrawn yet',
  30: 'Cannot abandon after deadline',
  31: 'Too many metadata entries (max 20)',
  32: 'Metadata value too long (max 1024 chars)',
  33: 'Hunter already approved',
  34: 'Arithmetic overflow',
  35: 'Grace period too short (min 1 hour)',
  36: 'Proof already submitted',
  37: 'Hunter has not claimed this bounty',
  38: 'No proof submitted',
  39: 'Proof not in submitted state',
  40: 'Proof not in rejected state',
  41: 'Proof not in disputed state',
  42: 'Review period has not expired yet',
  43: 'Already auto-approved',
  44: 'Invalid review period (1 hour – 7 days)',
  45: 'Proof URL cannot be empty',
  46: 'Proof URL too long (max 512 chars)',
  47: 'Rejection reason cannot be empty',
  48: 'Dispute reason cannot be empty',
  49: 'Resubmission already used (max 1)',
  50: 'Reason too long (max 1024 chars)',
  51: 'Review window has expired',
};

export const ProofStatus = {
  SUBMITTED: 10,
  APPROVED: 11,
  REJECTED: 12,
  DISPUTED: 13,
  RESOLVED_APPROVED: 14,
  RESOLVED_REJECTED: 15,
} as const;

export type ProofStatusValue = (typeof ProofStatus)[keyof typeof ProofStatus];

export const PROOF_STATUS_LABEL: Record<number, string> = {
  10: 'SUBMITTED',
  11: 'APPROVED',
  12: 'REJECTED',
  13: 'DISPUTED',
  14: 'RESOLVED (APPROVED)',
  15: 'RESOLVED (REJECTED)',
};

export const PROOF_STATUS_COLOR: Record<number, string> = {
  10: 'text-eve-cyan',
  11: 'text-status-completed',
  12: 'text-eve-danger',
  13: 'text-eve-gold',
  14: 'text-status-completed',
  15: 'text-eve-danger',
};

export const MIST_PER_SUI = 1_000_000_000n;

export const LIMITS = {
  MAX_TITLE: 256,
  MAX_DESCRIPTION: 2048,
  MAX_CLAIMS: 100,
  MAX_CLEANUP_BPS: 1000,
  MIN_DEADLINE_MS: 3_600_000,
  MAX_DEADLINE_MS: 31_536_000_000,
  MIN_GRACE_MS: 3_600_000,
  DEFAULT_GRACE_MS: 86_400_000,
  MAX_PROOF_URL: 512,
  MAX_PROOF_DESCRIPTION: 2048,
  MAX_REASON: 1024,
  MIN_REVIEW_PERIOD_MS: 3_600_000,
  MAX_REVIEW_PERIOD_MS: 604_800_000,
  DEFAULT_REVIEW_PERIOD_MS: 259_200_000,
} as const;
