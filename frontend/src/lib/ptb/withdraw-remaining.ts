import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildWithdrawRemaining(args: {
  bountyId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::withdraw_remaining`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
    ],
  });

  return tx;
}
