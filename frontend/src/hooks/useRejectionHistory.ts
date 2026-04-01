import { useQuery } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import type { SuiEvent } from '@mysten/sui/client';
import { V3_PACKAGE_ID } from '../config/contracts';

export interface RejectionRecord {
  reason: string;
  verifier: string;
  rejectedAt: number;
}

const MAX_PAGES = 5;

export function useRejectionHistory(
  bountyId: string | undefined,
  hunterAddress: string | undefined,
) {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['rejectionHistory', bountyId, hunterAddress],
    queryFn: async () => {
      const eventType = `${V3_PACKAGE_ID}::bounty::ProofRejectedEvent`;
      const allEvents: SuiEvent[] = [];
      let cursor: string | null | undefined = undefined;

      for (let page = 0; page < MAX_PAGES; page++) {
        const result = await client.queryEvents({
          query: { MoveEventType: eventType },
          limit: 50,
          order: 'ascending',
          cursor: cursor ?? undefined,
        });
        allEvents.push(...result.data);
        if (!result.hasNextPage || !result.nextCursor) break;
        cursor = result.nextCursor;
      }

      // Client-side filter (SUI event query doesn't support per-field filters)
      return allEvents
        .filter(evt => {
          const parsed = evt.parsedJson as Record<string, string> | undefined;
          return parsed?.bounty_id === bountyId && parsed?.hunter === hunterAddress;
        })
        .map(evt => {
          const p = evt.parsedJson as Record<string, string>;
          return {
            reason: p.reason ?? '',
            verifier: p.verifier ?? '',
            rejectedAt: Number(p.rejected_at ?? 0),
          } satisfies RejectionRecord;
        });
    },
    enabled: !!bountyId && !!hunterAddress,
    staleTime: 30_000,
  });
}
