import { useQuery } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import { V4_PACKAGE_ID } from '../config/contracts';

export interface ArbitratorConfig {
  arbitrator: string;
  disputeTimeoutMs: number;
}

export function useArbitratorConfig(bountyId: string | undefined) {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['arbitratorConfig', bountyId],
    queryFn: async (): Promise<ArbitratorConfig | null> => {
      const result = await client.getDynamicFieldObject({
        parentId: bountyId!,
        name: {
          type: `${V4_PACKAGE_ID}::bounty::ArbitratorConfigKey`,
          value: {},
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
        arbitrator: String(value.arbitrator ?? ''),
        disputeTimeoutMs: Number(value.dispute_timeout_ms ?? 0),
      };
    },
    enabled: !!bountyId,
    staleTime: 60_000,
  });
}
