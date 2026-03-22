import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildDisputeRejection(args: {
  bountyId: string;
  reason: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::dispute_rejection`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.string(args.reason),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
