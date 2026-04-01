import { useQuery } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import type { SuiEvent } from '@mysten/sui/client';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';
import type { ParsedBounty, BountyCreatedEvent } from '../lib/types';

/** Safely extract value from Balance<T> (nested struct or flat string) */
function unwrapBalance(val: unknown): bigint {
  if (val == null) return 0n;
  if (typeof val === 'string' || typeof val === 'number' || typeof val === 'bigint') {
    return BigInt(String(val));
  }
  // Balance<T> JSON-RPC nested format: { fields: { value: "123" } }
  const obj = val as Record<string, unknown>;
  const inner = (obj.fields as Record<string, unknown> | undefined)?.value ?? obj.value;
  return inner != null ? BigInt(String(inner)) : 0n;
}

function parseBountyFields(id: string, fields: Record<string, unknown>, coinType: string): ParsedBounty {
  return {
    id,
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
    hunters: [],
  };
}

export function useBountyList() {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['bountyList'],
    queryFn: async () => {
      // Step 1: Query BountyCreated events with cursor pagination
      const eventType = `${ORIGINAL_PACKAGE_ID}::bounty::BountyCreated`;
      const allEvents: SuiEvent[] = [];
      let cursor: string | null | undefined = undefined;
      const MAX_PAGES = 10;

      for (let page = 0; page < MAX_PAGES; page++) {
        const events = await client.queryEvents({
          query: { MoveEventType: eventType },
          limit: 50,
          order: 'descending',
          cursor: cursor ?? undefined,
        });
        allEvents.push(...events.data);
        if (!events.hasNextPage || !events.nextCursor) break;
        cursor = events.nextCursor;
      }

      if (!allEvents.length) return [];

      // Step 2: Extract bounty IDs and coin types
      const bountyMeta = allEvents.map((e) => {
        const parsed = e.parsedJson as BountyCreatedEvent;
        return {
          id: parsed.bounty_id,
          coinType: parsed.coin_type ?? '0x2::sui::SUI',
        };
      });

      // Deduplicate by ID (Map for O(1) lookup in step 3)
      const uniqueMap = new Map(bountyMeta.map((b) => [b.id, b]));
      const unique = [...uniqueMap.values()];

      // Step 3: Fetch current object state
      const objectIds = unique.map((b) => b.id);
      const objects = await client.multiGetObjects({
        ids: objectIds,
        options: { showContent: true },
      });

      const bounties: ParsedBounty[] = [];
      for (const obj of objects) {
        if (!obj.data?.content || obj.data.content.dataType !== 'moveObject') continue;
        const fields = obj.data.content.fields as Record<string, unknown>;
        const objId = obj.data.objectId;
        const meta = uniqueMap.get(objId);

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
