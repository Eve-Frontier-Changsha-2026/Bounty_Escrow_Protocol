import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { V7_PACKAGE_ID } from '../config/contracts';
import type { ParsedViewerReceipt } from '../lib/types';

/**
 * Query owned BountyViewerReceipt objects for the current user, filtered to a specific bounty.
 * Returns the first matching receipt or null.
 */
export function useViewerReceipt(
  ownerAddress: string | undefined,
  bountyId: string | undefined,
) {
  return useQuery({
    queryKey: ['viewerReceipt', ownerAddress, bountyId],
    queryFn: async (): Promise<ParsedViewerReceipt | null> => {
      const receiptType = `${V7_PACKAGE_ID}::encrypted_details::BountyViewerReceipt`;

      const result = await jsonRpcClient.getOwnedObjects({
        owner: ownerAddress!,
        filter: { StructType: receiptType },
        options: { showContent: true },
      });

      for (const item of result.data) {
        if (!item.data?.content || item.data.content.dataType !== 'moveObject') continue;

        const fields = item.data.content.fields as Record<string, unknown>;
        const receiptBountyId = String(fields.bounty_id ?? '');

        if (receiptBountyId === bountyId) {
          return {
            id: item.data.objectId,
            viewer: String(fields.viewer ?? ''),
            bountyId: receiptBountyId,
          };
        }
      }

      return null;
    },
    enabled: !!ownerAddress && !!bountyId,
  });
}
