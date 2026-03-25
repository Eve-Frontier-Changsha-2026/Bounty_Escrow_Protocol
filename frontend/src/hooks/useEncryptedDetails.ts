import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { V7_PACKAGE_ID } from '../config/contracts';
import type { EncryptedDetails } from '../lib/types';

export function useEncryptedDetails(bountyId: string | undefined) {
  return useQuery({
    queryKey: ['encryptedDetails', bountyId],
    queryFn: async (): Promise<EncryptedDetails | null> => {
      const result = await jsonRpcClient.getDynamicFieldObject({
        parentId: bountyId!,
        name: {
          type: `${V7_PACKAGE_ID}::encrypted_details::EncryptedDetailsKey`,
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

      // encrypted_payload is a vector<u8>, returned as number[] by JSON-RPC
      const rawPayload = value.encrypted_payload as number[] | undefined;
      const encryptedPayload = rawPayload ? new Uint8Array(rawPayload) : new Uint8Array();

      return {
        encryptedPayload,
        createdAt: Number(value.created_at ?? 0),
      };
    },
    enabled: !!bountyId,
  });
}
