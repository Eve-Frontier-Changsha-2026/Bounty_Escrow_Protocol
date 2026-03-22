import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildSetReviewPeriod(args: {
  bountyId: string;
  reviewPeriodMs: number;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::set_review_period`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.u64(args.reviewPeriodMs),
    ],
  });

  return tx;
}
