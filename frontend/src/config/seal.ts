import { V7_PACKAGE_ID, MODULE } from './contracts';

/** Seal approve entry function target for key servers */
export const SEAL_APPROVE_TARGET = `${MODULE.encryptedDetails}::seal_approve_bounty`;

/** Mysten testnet key server configuration (2-of-2 threshold) */
export const SEAL_CONFIG = {
  packageId: V7_PACKAGE_ID,
  serverConfigs: [
    {
      objectId:
        '0x73d05d62c18d9374e3ea529e8e0ed6161da1a141a94d3f76ae3fe4e99356db75',
      weight: 1,
    },
    {
      objectId:
        '0xf5d14a81a982144ae441cd7d64b09027f116a468bd36e7eca494f750591623c8',
      weight: 1,
    },
  ],
  threshold: 2,
  verifyKeyServers: !import.meta.env.DEV,
} as const;
