import { useQuery } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import { V4_PACKAGE_ID } from '../config/contracts';

export interface DisputeTimestamp {
  disputedAt: number;
}

export function useDisputeTimestamp(bountyId: string | undefined, hunterAddress: string | undefined) {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['disputeTimestamp', bountyId, hunterAddress],
    queryFn: async (): Promise<DisputeTimestamp | null> => {
      const result = await client.getDynamicFieldObject({
        parentId: bountyId!,
        name: {
          type: `${V4_PACKAGE_ID}::bounty::DisputeTimestampKey`,
          value: { hunter: hunterAddress! },
        },
      });

      if (!result.data?.content || result.data.content.dataType !== 'moveObject') {
        return null;
      }

      const fields = result.data.content.fields as Record<string, unknown>;
      const value = (fields.value as Record<string, unknown>)?.fields as Record<string, unknown>
        ?? fields.value as Record<string, unknown>;
      if (!value) return null;

      return {
        disputedAt: Number(value.disputed_at ?? 0),
      };
    },
    enabled: !!bountyId && !!hunterAddress,
    staleTime: 60_000,
  });
}
