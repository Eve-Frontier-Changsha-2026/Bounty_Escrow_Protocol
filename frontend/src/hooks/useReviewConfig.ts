import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { V3_PACKAGE_ID } from '../config/contracts';
import { LIMITS } from '../lib/constants';

export function useReviewConfig(bountyId: string | undefined) {
  return useQuery({
    queryKey: ['reviewConfig', bountyId],
    queryFn: async () => {
      const result = await jsonRpcClient.getDynamicFieldObject({
        parentId: bountyId!,
        name: {
          type: `${V3_PACKAGE_ID}::bounty::ReviewConfigKey`,
          value: {},
        },
      });

      if (!result.data?.content || result.data.content.dataType !== 'moveObject') {
        return LIMITS.DEFAULT_REVIEW_PERIOD_MS;
      }

      const fields = result.data.content.fields as Record<string, unknown>;
      const rawValue = fields.value as Record<string, unknown> | undefined;
      if (!rawValue) return LIMITS.DEFAULT_REVIEW_PERIOD_MS;
      const value = (rawValue.fields as Record<string, unknown> | undefined) ?? rawValue;

      return Number(value.review_period_ms ?? LIMITS.DEFAULT_REVIEW_PERIOD_MS);
    },
    enabled: !!bountyId,
  });
}
