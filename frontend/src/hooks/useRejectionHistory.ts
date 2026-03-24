import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { PACKAGE_ID } from '../config/contracts';

export interface RejectionRecord {
  reason: string;
  verifier: string;
  rejectedAt: number;
}

export function useRejectionHistory(
  bountyId: string | undefined,
  hunterAddress: string | undefined,
) {
  return useQuery({
    queryKey: ['rejectionHistory', bountyId, hunterAddress],
    queryFn: async () => {
      const result = await jsonRpcClient.queryEvents({
        query: {
          MoveEventType: `${PACKAGE_ID}::bounty::ProofRejectedEvent`,
        },
        order: 'ascending',
      });

      // Filter by bountyId and hunter
      return (result.data ?? [])
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
  });
}
