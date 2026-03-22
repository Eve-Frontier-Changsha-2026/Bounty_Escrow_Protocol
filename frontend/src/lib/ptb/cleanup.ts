import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildDestroyTicket(args: {
  ticketId: string;
  bountyId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::destroy_ticket`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.ticketId),
      tx.object(args.bountyId),
    ],
  });

  return tx;
}

export function buildDestroyVerifierCap(args: {
  capId: string;
  bountyId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::destroy_verifier_cap`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.capId),
      tx.object(args.bountyId),
    ],
  });

  return tx;
}
