import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildRejectProof(args: {
  bountyId: string;
  hunterAddr: string;
  reason: string;
  verifierCapId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::reject_proof`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.address(args.hunterAddr),
      tx.pure.string(args.reason),
      tx.object(args.verifierCapId),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
