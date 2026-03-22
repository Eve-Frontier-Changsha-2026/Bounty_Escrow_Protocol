import { Transaction } from '@mysten/sui/transactions';
import { PACKAGE_ID, CLOCK, DEFAULT_COIN_TYPE } from '../../config/contracts';

export function buildCreateBounty(args: {
  title: string;
  description: string;
  rewardAmount: bigint;
  requiredStake: bigint;
  maxClaims: number;
  deadline: bigint;
  gracePeriod: bigint;
  cleanupRewardBps: number;
  verifierAddr: string;
  coinType?: string;
}) {
  const tx = new Transaction();
  const coinType = args.coinType ?? DEFAULT_COIN_TYPE;
  const totalEscrow = args.rewardAmount * BigInt(args.maxClaims);

  const [payment] = tx.splitCoins(tx.gas, [totalEscrow]);

  tx.moveCall({
    target: `${PACKAGE_ID}::bounty::create`,
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

  return tx;
}
