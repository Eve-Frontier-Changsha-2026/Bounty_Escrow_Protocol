import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

/** Build a verify_kill transaction. */
export function buildVerifyKill(args: {
  bountyId: string;
  killmailId: string;      // Killmail Sui Object ID
  characterId: string;     // Hunter's Character Sui Object ID
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::verify_kill::verify_kill`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.object(args.killmailId),
      tx.object(args.characterId),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
