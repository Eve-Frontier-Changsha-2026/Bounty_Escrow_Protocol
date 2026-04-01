import { SealClient, SessionKey } from '@mysten/seal';
import type { SealCompatibleClient } from '@mysten/seal';
import { Transaction } from '@mysten/sui/transactions';
import { fromHex } from '@mysten/sui/utils';
import { SEAL_APPROVE_TARGET, SEAL_CONFIG } from '../config/seal';

// ---------------------------------------------------------------------------
// SealClient — keyed by suiClient identity (recreates on network switch)
// ---------------------------------------------------------------------------

let _cached: { ref: SealCompatibleClient; client: SealClient } | null = null;

export function getSealClient(suiClient: SealCompatibleClient): SealClient {
  if (!_cached || _cached.ref !== suiClient) {
    _cached = {
      ref: suiClient,
      client: new SealClient({
        suiClient,
        serverConfigs: [...SEAL_CONFIG.serverConfigs],
        verifyKeyServers: SEAL_CONFIG.verifyKeyServers,
      }),
    };
  }
  return _cached.client;
}

// ---------------------------------------------------------------------------
// Namespace helper — bountyId (32 bytes) is the Seal "id" prefix
// ---------------------------------------------------------------------------

/**
 * Build the Seal identity bytes for a bounty.
 * Format: raw 32-byte object ID (no 0x prefix).
 * The Move `seal_approve_bounty` checks that the first 32 bytes of `id`
 * match the receipt's `bounty_id`.
 */
export function bountyIdToSealId(bountyId: string): Uint8Array {
  return fromHex(bountyId);
}

// ---------------------------------------------------------------------------
// Encrypt
// ---------------------------------------------------------------------------

/**
 * Encrypt plaintext for a specific bounty.
 * Returns the BCS-encoded EncryptedObject bytes (ready for `set_encrypted_details`).
 */
export async function sealEncrypt(args: {
  suiClient: SealCompatibleClient;
  bountyId: string;
  plaintext: Uint8Array;
}): Promise<{ encryptedObject: Uint8Array; backupKey: Uint8Array }> {
  const client = getSealClient(args.suiClient);
  const id = bountyIdToSealId(args.bountyId);

  const { encryptedObject, key } = await client.encrypt({
    threshold: SEAL_CONFIG.threshold,
    packageId: SEAL_CONFIG.packageId,
    id: new TextDecoder().decode(id), // Seal SDK expects hex string as id
    data: args.plaintext,
  });

  return { encryptedObject, backupKey: key };
}

// ---------------------------------------------------------------------------
// Session key management
// ---------------------------------------------------------------------------

const SESSION_TTL_MIN = 10;

export async function createSessionKey(args: {
  address: string;
  suiClient: SealCompatibleClient;
}): Promise<SessionKey> {
  return SessionKey.create({
    address: args.address,
    packageId: SEAL_CONFIG.packageId,
    ttlMin: SESSION_TTL_MIN,
    suiClient: args.suiClient,
  });
}

// ---------------------------------------------------------------------------
// Build seal_approve TX bytes (for key server dry-run)
// ---------------------------------------------------------------------------

/**
 * Build a TX that calls `seal_approve_bounty(id, &receipt)`.
 * The key server dry-runs this to verify access — it never goes on-chain.
 */
export function buildSealApproveTx(args: {
  sealId: Uint8Array;
  viewerReceiptId: string;
}): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: SEAL_APPROVE_TARGET,
    arguments: [
      tx.pure.vector('u8', Array.from(args.sealId)),
      tx.object(args.viewerReceiptId),
    ],
  });
  return tx;
}

// ---------------------------------------------------------------------------
// Decrypt
// ---------------------------------------------------------------------------

/**
 * Decrypt encrypted bounty details.
 * Requires an active SessionKey (with personal message signed) and a viewer receipt.
 */
export async function sealDecrypt(args: {
  suiClient: SealCompatibleClient;
  encryptedData: Uint8Array;
  sessionKey: SessionKey;
  bountyId: string;
  viewerReceiptId: string;
}): Promise<Uint8Array> {
  const client = getSealClient(args.suiClient);
  const sealId = bountyIdToSealId(args.bountyId);

  const approveTx = buildSealApproveTx({
    sealId,
    viewerReceiptId: args.viewerReceiptId,
  });

  const txBytes = await approveTx.build({ client: args.suiClient });

  return client.decrypt({
    data: args.encryptedData,
    sessionKey: args.sessionKey,
    txBytes,
  });
}
