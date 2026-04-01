import { useQuery } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import { V7_PACKAGE_ID } from '../config/contracts';
import type { EncryptionState } from '../lib/types';

export function useEncryptionState(bountyId: string | undefined) {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['encryptionState', bountyId],
    queryFn: async (): Promise<EncryptionState | null> => {
      const result = await client.getDynamicFieldObject({
        parentId: bountyId!,
        name: {
          type: `${V7_PACKAGE_ID}::task_type::EncryptionStateKey`,
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
        isEncrypted: Boolean(value.is_encrypted ?? false),
        encryptedAt: Number(value.encrypted_at ?? 0),
      };
    },
    enabled: !!bountyId,
    staleTime: 60_000,
  });
}
