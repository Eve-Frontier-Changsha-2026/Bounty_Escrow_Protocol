import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildSetArbitrator(args: {
  bountyId: string;
  arbitrator: string;
  disputeTimeoutMs: number;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::set_arbitrator`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.address(args.arbitrator),
      tx.pure.u64(args.disputeTimeoutMs),
    ],
  });

  return tx;
}
