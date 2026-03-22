import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildApproveHunter(args: {
  bountyId: string;
  hunterAddr: string;
  verifierCapId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::approve`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.address(args.hunterAddr),
      tx.object(args.verifierCapId),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
