import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

/** Set task type on an existing shared bounty. Creator only, OPEN status, 0 active claims. */
export function buildSetTaskType(args: {
  bountyId: string;
  taskType: number;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::task_type::set_task_type`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.u8(args.taskType),
      tx.object(CLOCK),
    ],
  });

  return tx;
}
