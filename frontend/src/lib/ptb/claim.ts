import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildClaimBounty(args: {
  bountyId: string;
  stakeAmount: bigint;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  const [stake] = tx.splitCoins(tx.gas, [args.stakeAmount]);

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::claim`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      stake,
      tx.object(CLOCK),
    ],
  });

  return tx;
}
