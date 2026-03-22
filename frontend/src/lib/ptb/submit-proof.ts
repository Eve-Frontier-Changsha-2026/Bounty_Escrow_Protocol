import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildSubmitProof(args: {
  bountyId: string;
  proofUrl: string;
  proofDescription: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::submit_proof`,
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
