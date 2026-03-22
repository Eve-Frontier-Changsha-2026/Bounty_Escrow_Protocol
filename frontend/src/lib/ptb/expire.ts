import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildExpire(args: {
  bountyId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::expire`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
