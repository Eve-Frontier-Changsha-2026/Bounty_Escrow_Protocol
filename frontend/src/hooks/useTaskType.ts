import { useMemo } from 'react';
import { useQuery, useQueries } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc';
import { V5_PACKAGE_ID } from '../config/contracts';
import type { TaskTypeConfig } from '../lib/types';

type ReadClient = Pick<SuiJsonRpcClient, 'getDynamicFieldObject'>;

async function fetchTaskType(
  client: ReadClient,
  bountyId: string,
): Promise<TaskTypeConfig | null> {
  const result = await client.getDynamicFieldObject({
    parentId: bountyId,
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
}

/** Single bounty task type query (used in detail pages) */
export function useTaskType(bountyId: string | undefined) {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['taskType', bountyId],
    queryFn: () => fetchTaskType(client, bountyId!),
    enabled: !!bountyId,
    staleTime: 60_000,
  });
}

/** Batch task type query for multiple bounties (used in list pages) */
export function useTaskTypes(bountyIds: string[]) {
  const client = useCurrentClient();

  const results = useQueries({
    queries: bountyIds.map(id => ({
      queryKey: ['taskType', id],
      queryFn: () => fetchTaskType(client, id),
      staleTime: 60_000,
    })),
  });

  return useMemo(() => {
    const map = new Map<string, TaskTypeConfig>();
    for (let i = 0; i < bountyIds.length; i++) {
      const data = results[i]?.data;
      if (data) map.set(bountyIds[i], data);
    }
    return map;
  }, [bountyIds, results]);
}
