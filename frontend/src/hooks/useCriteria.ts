import { useQuery } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc';
import { V5_PACKAGE_ID } from '../config/contracts';
import { TaskType } from '../lib/constants';
import type { KillCriteria, DeliveryCriteria, BuildCriteria } from '../lib/types';

export type CriteriaResult =
  | { type: 'kill'; data: KillCriteria }
  | { type: 'delivery'; data: DeliveryCriteria }
  | { type: 'build'; data: BuildCriteria }
  | null;

type ReadClient = Pick<SuiJsonRpcClient, 'getDynamicFieldObject'>;

/**
 * Fetch criteria DF for a bounty given its task type.
 * Pass taskType from useTaskType() so this hook only fires when we know which criteria to read.
 */
export function useCriteria(bountyId: string | undefined, taskType: number | undefined) {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['criteria', bountyId, taskType],
    queryFn: async (): Promise<CriteriaResult> => {
      if (taskType === TaskType.KILL) {
        return fetchKillCriteria(client, bountyId!);
      } else if (taskType === TaskType.DELIVERY) {
        return fetchDeliveryCriteria(client, bountyId!);
      } else if (taskType === TaskType.BUILD) {
        return fetchBuildCriteria(client, bountyId!);
      }
      return null;
    },
    enabled: !!bountyId && taskType != null && taskType !== TaskType.CUSTOM && taskType !== TaskType.INTEL,
    staleTime: 60_000,
  });
}

async function fetchKillCriteria(client: ReadClient, parentId: string): Promise<CriteriaResult> {
  const result = await client.getDynamicFieldObject({
    parentId,
    name: {
      type: `${V5_PACKAGE_ID}::task_type::KillCriteriaKey`,
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
    type: 'kill',
    data: {
      solarSystemId: String(value.solar_system_id ?? '0'),
      lossType: Number(value.loss_type ?? 0),
      minKills: Number(value.min_kills ?? 1),
    },
  };
}

async function fetchDeliveryCriteria(client: ReadClient, parentId: string): Promise<CriteriaResult> {
  const result = await client.getDynamicFieldObject({
    parentId,
    name: {
      type: `${V5_PACKAGE_ID}::task_type::DeliveryCriteriaKey`,
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
    type: 'delivery',
    data: {
      itemTypeId: String(value.item_type_id ?? '0'),
      minQuantity: Number(value.min_quantity ?? 0),
      targetAssemblyId: String(value.target_assembly_id ?? '0x0'),
    },
  };
}

async function fetchBuildCriteria(client: ReadClient, parentId: string): Promise<CriteriaResult> {
  const result = await client.getDynamicFieldObject({
    parentId,
    name: {
      type: `${V5_PACKAGE_ID}::task_type::BuildCriteriaKey`,
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
    type: 'build',
    data: {
      assemblyTypeId: String(value.assembly_type_id ?? '0'),
      solarSystemId: String(value.solar_system_id ?? '0'),
    },
  };
}
