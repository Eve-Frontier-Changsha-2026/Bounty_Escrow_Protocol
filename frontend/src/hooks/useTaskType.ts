import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { V5_PACKAGE_ID } from '../config/contracts';
import type { TaskTypeConfig } from '../lib/types';

export function useTaskType(bountyId: string | undefined) {
  return useQuery({
    queryKey: ['taskType', bountyId],
    queryFn: async (): Promise<TaskTypeConfig | null> => {
      const result = await jsonRpcClient.getDynamicFieldObject({
        parentId: bountyId!,
        name: {
          type: `${V5_PACKAGE_ID}::task_type::TaskTypeKey`,
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
        taskType: Number(value.task_type ?? 0),
        verificationMode: Number(value.verification_mode ?? 0),
        createdAt: Number(value.created_at ?? 0),
      };
    },
    enabled: !!bountyId,
  });
}
