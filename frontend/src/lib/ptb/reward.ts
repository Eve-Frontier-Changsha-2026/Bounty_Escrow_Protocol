import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildClaimReward(args: {
  bountyId: string;
  ticketId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::claim_reward`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.object(args.ticketId),
    ],
  });

  return tx;
}
