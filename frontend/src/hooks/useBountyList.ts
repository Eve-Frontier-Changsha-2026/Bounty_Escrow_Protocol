import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';
import type { ParsedBounty, BountyCreatedEvent } from '../lib/types';

function parseBountyFields(id: string, fields: Record<string, unknown>, coinType: string): ParsedBounty {
  return {
    id,
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
    hunters: [],
  };
}

export function useBountyList() {
  return useQuery({
    queryKey: ['bountyList'],
    queryFn: async () => {
      // Step 1: Query BountyCreated events to discover bounty IDs
      const eventType = `${ORIGINAL_PACKAGE_ID}::bounty::BountyCreated`;
      const events = await jsonRpcClient.queryEvents({
        query: { MoveEventType: eventType },
        limit: 50,
        order: 'descending',
      });

      if (!events.data.length) return [];

      // Step 2: Extract bounty IDs and coin types
      const bountyMeta = events.data.map((e) => {
        const parsed = e.parsedJson as BountyCreatedEvent;
        return {
          id: parsed.bounty_id,
          coinType: parsed.coin_type ?? '0x2::sui::SUI',
        };
      });

      // Deduplicate by ID
      const uniqueMap = new Map(bountyMeta.map((b) => [b.id, b]));
      const unique = [...uniqueMap.values()];

      // Step 3: Fetch current object state via JSON-RPC (gRPC returns raw BCS, not parsed fields)
      const objectIds = unique.map((b) => b.id);
      const objects = await jsonRpcClient.multiGetObjects({
        ids: objectIds,
        options: { showContent: true },
      });

      const bounties: ParsedBounty[] = [];
      for (const obj of objects) {
        if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') continue;
        const fields = obj.data.content.fields as Record<string, unknown>;
        const objId = obj.data.objectId;
        const meta = unique.find((b) => b.id === objId);

        // Extract coin type from the object type string
        const typeStr = obj.data.content.type ?? '';
        const coinTypeMatch = typeStr.match(/<(.+)>/);
        const coinType = coinTypeMatch?.[1] ?? meta?.coinType ?? '0x2::sui::SUI';

        bounties.push(parseBountyFields(objId, fields, coinType));
      }

      return bounties;
    },
    staleTime: 15_000,
  });
}
