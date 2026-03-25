import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

/**
 * TX2 — Set encrypted details on an existing shared bounty.
 * Called after TX1 (create-full) completes, because Seal encryption
 * needs the bountyId as namespace prefix.
 *
 * Move signature: set_encrypted_details<T>(bounty, encrypted_payload: vector<u8>, clock, ctx)
 */
export function buildSetEncryptedDetails(args: {
  bountyId: string;
  encryptedPayload: Uint8Array;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::encrypted_details::set_encrypted_details`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.vector('u8', Array.from(args.encryptedPayload)),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
