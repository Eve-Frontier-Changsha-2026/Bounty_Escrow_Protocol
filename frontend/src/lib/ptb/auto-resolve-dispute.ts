import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildAutoResolveDispute(args: {
  bountyId: string;
  hunterAddr: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::auto_resolve_dispute`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.address(args.hunterAddr),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
