// v6 — latest function call target
export const PACKAGE_ID =
  '0x68295e2919455c667f73f436c5594a22c4eed2cd3a96d12b96eb52502a00b933';

// v1 — original package (Bounty, ClaimTicket, VerifierCap, BountyCreated types)
export const ORIGINAL_PACKAGE_ID =
  '0x8222b1e623985cf9ef25d6d60f8a812c24fb0ac81f8ab6db6929bde273e6cb16';

// v3 — ProofKey, ReviewConfigKey, ProofRejectedEvent types
export const V3_PACKAGE_ID =
  '0x76b952d0acf15742daadb76f6b1921442bafbd8201d5449d2e0a73056a7df39c';

// v4 — ArbitratorConfigKey, DisputeTimestampKey, ArbitratorConfig, DisputeTimestamp types
export const V4_PACKAGE_ID =
  '0x5357556af095edf9ff7f8481d384e10266758f746b0f2aafde0805a9415f521c';

// v5 — TaskTypeKey, KillCriteriaKey, DeliveryCriteriaKey, BuildCriteriaKey,
//       IntelConfigKey, OracleRegistry, OracleNonceKey, UsedKillmailKey,
//       ViewerReceipt, KillVerifiedEvent, DeliveryVerifiedEvent, BuildVerifiedEvent,
//       IntelPostedEvent, IntelConfirmedEvent types
export const V5_PACKAGE_ID =
  '0xf324f9a1ca201524bffb3041fda191582f5b5aa4bf3aa327900d8cf6e4fe45ca';

export const ORACLE_REGISTRY_ID =
  '0x0af29639026b162193914095a729f4fd3d1c1360df9301ba9261ce3390e79231';

export const MODULE = {
  bounty: `${PACKAGE_ID}::bounty`,
  taskType: `${PACKAGE_ID}::task_type`,
  oracle: `${PACKAGE_ID}::oracle`,
  intelEscrow: `${PACKAGE_ID}::intel_escrow`,
  verifyKill: `${PACKAGE_ID}::verify_kill`,
  verifyDelivery: `${PACKAGE_ID}::verify_delivery`,
  verifyBuild: `${PACKAGE_ID}::verify_build`,
} as const;

export const DEFAULT_COIN_TYPE = '0x2::sui::SUI';

export const CLOCK = '0x6';
