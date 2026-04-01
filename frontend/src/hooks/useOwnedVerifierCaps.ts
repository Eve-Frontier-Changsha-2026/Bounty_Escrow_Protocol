import { useQuery } from '@tanstack/react-query';
import { useCurrentAccount, useCurrentClient } from '@mysten/dapp-kit-react';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';
import type { ParsedVerifierCap } from '../lib/types';

const CAP_TYPE = `${ORIGINAL_PACKAGE_ID}::verifier::VerifierCap`;
const MAX_PAGES = 10;

export function useOwnedVerifierCaps() {
  const account = useCurrentAccount();
  const client = useCurrentClient();

  return useQuery({
    queryKey: ['ownedVerifierCaps', account?.address],
    queryFn: async () => {
      const all: ParsedVerifierCap[] = [];
      let cursor: string | null | undefined;

      for (let page = 0; page < MAX_PAGES; page++) {
        const result = await client.getOwnedObjects({
          owner: account!.address,
          filter: { StructType: CAP_TYPE },
          options: { showContent: true },
          cursor: cursor ?? undefined,
        });

        for (const obj of result.data) {
          if (obj.data?.content?.dataType !== 'moveObject') continue;
          const data = obj.data;
          const fields = (data.content as { fields: Record<string, unknown> }).fields;
          all.push({
            id: data.objectId,
            bountyId: String(fields.bounty_id ?? ''),
          });
        }

        if (!result.hasNextPage || !result.nextCursor) break;
        cursor = result.nextCursor;
      }

      return all;
    },
    enabled: !!account,
    staleTime: 60_000,
  });
}
