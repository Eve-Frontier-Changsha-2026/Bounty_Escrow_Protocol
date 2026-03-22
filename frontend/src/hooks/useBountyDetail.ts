import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import type { ParsedBounty } from '../lib/types';

export function useBountyDetail(bountyId: string | undefined) {
  return useQuery({
    queryKey: ['bountyDetail', bountyId],
    queryFn: async () => {
      const result = await jsonRpcClient.getObject({
        id: bountyId!,
        options: { showContent: true },
      });

      if (!result.data?.content || result.data.content.dataType !== 'moveObject') {
        throw new Error('Bounty not found');
      }

      const fields = result.data.content.fields as Record<string, unknown>;
      const typeStr = result.data.content.type ?? '';
      const coinTypeMatch = typeStr.match(/<(.+)>/);
      const coinType = coinTypeMatch?.[1] ?? '0x2::sui::SUI';

      return {
        id: result.data.objectId,
        version: Number(fields.version ?? 0),
        creator: String(fields.creator ?? ''),
        title: String(fields.title ?? ''),
        description: String(fields.description ?? ''),
        escrowValue: BigInt(String(fields.escrow ?? '0')),
        stakePoolValue: BigInt(String(fields.stake_pool ?? '0')),
        rewardAmount: BigInt(String(fields.reward_amount ?? '0')),
        requiredStake: BigInt(String(fields.required_stake ?? '0')),
        cleanupRewardBps: Number(fields.cleanup_reward_bps ?? 0),
        deadline: Number(fields.deadline ?? 0),
        gracePeriod: Number(fields.grace_period ?? 0),
        status: Number(fields.status ?? 0),
        maxClaims: Number(fields.max_claims ?? 0),
        activeClaims: Number(fields.active_claims ?? 0),
        completedClaims: Number(fields.completed_claims ?? 0),
        coinType,
      } satisfies ParsedBounty;
    },
    enabled: !!bountyId,
  });
}
