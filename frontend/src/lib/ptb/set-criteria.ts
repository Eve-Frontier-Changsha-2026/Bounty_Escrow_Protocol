import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, DEFAULT_COIN_TYPE } from '../../config/contracts';

/** Set KILL criteria on a bounty. Requires task type already set to KILL. */
export function buildSetKillCriteria(args: {
  bountyId: string;
  solarSystemId: string;
  lossType: number;
  minKills: number;
  targetVictimId?: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::task_type::set_kill_criteria`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.u64(args.solarSystemId),
      tx.pure.u8(args.lossType),
      tx.pure.u64(args.minKills),
    ],
  });

  if (args.targetVictimId != null) {
    tx.moveCall({
      target: `${PACKAGE_ID}::task_type::set_target_victim`,
      typeArguments: [coinType],
      arguments: [tx.object(args.bountyId), tx.pure.u64(args.targetVictimId)],
    });
  }

  return tx;
}

/** Set DELIVERY criteria on a bounty. Requires task type already set to DELIVERY. */
export function buildSetDeliveryCriteria(args: {
  bountyId: string;
  itemTypeId: string;
  minQuantity: number;
  targetAssemblyId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::task_type::set_delivery_criteria`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.u64(args.itemTypeId),
      tx.pure.u64(args.minQuantity),
      tx.pure.address(args.targetAssemblyId),
    ],
  });

  return tx;
}

/** Set BUILD criteria on a bounty. Requires task type already set to BUILD. */
export function buildSetBuildCriteria(args: {
  bountyId: string;
  assemblyTypeId: string;
  solarSystemId: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;

  tx.moveCall({
    target: `${PACKAGE_ID}::task_type::set_build_criteria`,
    typeArguments: [coinType],
    arguments: [
      tx.object(args.bountyId),
      tx.pure.u64(args.assemblyTypeId),
      tx.pure.u64(args.solarSystemId),
    ],
  });

  return tx;
}
