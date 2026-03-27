import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { V7_PACKAGE_ID } from '../config/contracts';
import type { TargetVictim } from '../lib/types';

export function useTargetVictim(bountyId: string | undefined) {
  return useQuery({
    queryKey: ['targetVictim', bountyId],
    queryFn: async (): Promise<TargetVictim | null> => {
      const result = await jsonRpcClient.getDynamicFieldObject({
        parentId: bountyId!,
        name: {
          type: `${V7_PACKAGE_ID}::task_type::TargetVictimKey`,
          value: {},
        },
      });

      if (!result.data?.content || result.data.content.dataType !== 'moveObject') {
        return null;
      }

      const fields = result.data.content.fields as Record<string, unknown>;
      const rawValue = fields.value as Record<string, unknown> | undefined;
      if (!rawValue) return null;
      const value = (rawValue.fields as Record<string, unknown> | undefined) ?? rawValue;

      return {
        victimId: String(value.victim_id ?? '0'),
      };
    },
    enabled: !!bountyId,
  });
}
