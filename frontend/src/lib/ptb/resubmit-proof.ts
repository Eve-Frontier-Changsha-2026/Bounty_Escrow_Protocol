import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildResubmitProof(args: {
  bountyId: string;
  proofUrl: string;
  proofDescription: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::resubmit_proof`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.string(args.proofUrl),
      tx.pure.string(args.proofDescription),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
