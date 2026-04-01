import { useQuery } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import type { ParsedBounty } from '../lib/types';

/** Safely extract value from Balance<T> (nested struct or flat string) */
function unwrapBalance(val: unknown): bigint {
  if (val == null) return 0n;
  if (typeof val === 'string' || typeof val === 'number' || typeof val === 'bigint') {
    return BigInt(String(val));
  }
  const obj = val as Record<string, unknown>;
  const inner = (obj.fields as Record<string, unknown> | undefined)?.value ?? obj.value;
  return inner != null ? BigInt(String(inner)) : 0n;
}

export function useBountyDetail(bountyId: string | undefined) {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['bountyDetail', bountyId],
    queryFn: async () => {
      const result = await client.getObject({
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

      // Parse active_hunter_stakes VecMap → array of hunter addresses
      const hunterStakes = fields.active_hunter_stakes as { fields?: { contents?: Array<{ fields?: { key?: string } }> } } | undefined;
      const hunters: string[] = (hunterStakes?.fields?.contents ?? [])
        .map(entry => entry.fields?.key ?? '')
        .filter(Boolean);

      return {
        id: result.data.objectId,
        version: Number(fields.version ?? 0),
        creator: String(fields.creator ?? ''),
        title: String(fields.title ?? ''),
        description: String(fields.description ?? ''),
        escrowValue: unwrapBalance(fields.escrow),
        stakePoolValue: unwrapBalance(fields.stake_pool),
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
        hunters,
      } satisfies ParsedBounty;
    },
    enabled: !!bountyId,
    staleTime: 15_000,
  });
}
