import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildResolveDispute(args: {
  bountyId: string;
  hunterAddr: string;
  approve: boolean;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::resolve_dispute`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.address(args.hunterAddr),
      tx.pure.bool(args.approve),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
