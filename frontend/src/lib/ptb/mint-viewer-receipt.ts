import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, DEFAULT_COIN_TYPE } from '../../config/contracts';

/** Mint a BountyViewerReceipt for Seal decrypt access. Active hunter only. */
export function buildMintViewerReceipt(args: {
  bountyId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::encrypted_details::mint_viewer_receipt`,
    typeArguments: [coinType],
    arguments: [tx.object(args.bountyId)],
  });

  return tx;
}
