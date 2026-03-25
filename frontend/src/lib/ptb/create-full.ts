import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';
import { TaskType } from '../constants';

/**
 * TX1 — Composable bounty creation.
 * create_bounty_owned → set_task_type → set_*_criteria → [set_target_victim] → [set_encryption_state] → share_bounty
 * Returns change coin to sender.
 */
export function buildCreateBountyFull(args: {
  // Core bounty params
  title: string;
  description: string;
  rewardAmount: bigint;
  requiredStake: bigint;
  maxClaims: number;
  deadline: bigint;
  gracePeriod: bigint;
  cleanupRewardBps: number;
  verifierAddr: string;
  // Task type config
  taskType: number;
  // Criteria (depends on taskType)
  killCriteria?: { solarSystemId: number; lossType: number; minKills: number };
  deliveryCriteria?: {
    itemTypeId: number;
    minQuantity: number;
    targetAssemblyId: string;
  };
  buildCriteria?: { assemblyTypeId: number; solarSystemId: number };
  // v7 optional
  targetVictimId?: number;
  isEncrypted?: boolean;
  // coin type
  coinType?: string;
  sender: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;
  const totalEscrow = args.rewardAmount * BigInt(args.maxClaims);

  const [payment] = tx.splitCoins(tx.gas, [totalEscrow]);

  // 1. create_bounty_owned → returns (Bounty<T>, Coin<T>)
  const [bounty, change] = tx.moveCall({
    target: `${PACKAGE_ID}::bounty::create_bounty_owned`,
    typeArguments: [coinType],
    arguments: [
      tx.pure.string(args.title),
      tx.pure.string(args.description),
      payment,
      tx.pure.u64(args.rewardAmount),
      tx.pure.u64(args.requiredStake),
      tx.pure.u64(args.maxClaims),
      tx.pure.u64(args.deadline),
      tx.pure.u64(args.gracePeriod),
      tx.pure.u16(args.cleanupRewardBps),
      tx.pure.address(args.verifierAddr),
      tx.object(CLOCK),
    ],
  });

  // 2. set_task_type (CUSTOM=0 skips criteria)
  if (args.taskType !== TaskType.CUSTOM) {
    tx.moveCall({
      target: `${PACKAGE_ID}::task_type::set_task_type`,
      typeArguments: [coinType],
      arguments: [bounty, tx.pure.u8(args.taskType), tx.object(CLOCK)],
    });

    // 3. set criteria based on task type
    if (args.taskType === TaskType.KILL && args.killCriteria) {
      tx.moveCall({
        target: `${PACKAGE_ID}::task_type::set_kill_criteria`,
        typeArguments: [coinType],
        arguments: [
          bounty,
          tx.pure.u64(args.killCriteria.solarSystemId),
          tx.pure.u8(args.killCriteria.lossType),
          tx.pure.u64(args.killCriteria.minKills),
        ],
      });

      // 4. optional target victim (KILL only)
      if (args.targetVictimId != null) {
        tx.moveCall({
          target: `${PACKAGE_ID}::task_type::set_target_victim`,
          typeArguments: [coinType],
          arguments: [bounty, tx.pure.u64(args.targetVictimId)],
        });
      }
    }

    if (args.taskType === TaskType.DELIVERY && args.deliveryCriteria) {
      tx.moveCall({
        target: `${PACKAGE_ID}::task_type::set_delivery_criteria`,
        typeArguments: [coinType],
        arguments: [
          bounty,
          tx.pure.u64(args.deliveryCriteria.itemTypeId),
          tx.pure.u64(args.deliveryCriteria.minQuantity),
          tx.pure.address(args.deliveryCriteria.targetAssemblyId),
        ],
      });
    }

    if (args.taskType === TaskType.BUILD && args.buildCriteria) {
      tx.moveCall({
        target: `${PACKAGE_ID}::task_type::set_build_criteria`,
        typeArguments: [coinType],
        arguments: [
          bounty,
          tx.pure.u64(args.buildCriteria.assemblyTypeId),
          tx.pure.u64(args.buildCriteria.solarSystemId),
        ],
      });
    }

    // 5. optional encryption state
    if (args.isEncrypted) {
      tx.moveCall({
        target: `${PACKAGE_ID}::task_type::set_encryption_state`,
        typeArguments: [coinType],
        arguments: [bounty, tx.pure.bool(true), tx.object(CLOCK)],
      });
    }
  }

  // 6. share_bounty — must be last (once shared, can't &mut in same TX)
  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::share_bounty`,
    typeArguments: [coinType],
    arguments: [bounty],
  });

  // 7. return change coin to sender
  tx.transferObjects([change], args.sender);

  return tx;
}
