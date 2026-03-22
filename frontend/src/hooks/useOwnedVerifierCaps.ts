import { useQuery } from '@tanstack/react-query';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { jsonRpcClient } from '../lib/rpc';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';
import type { ParsedVerifierCap } from '../lib/types';

const CAP_TYPE = `${ORIGINAL_PACKAGE_ID}::verifier::VerifierCap`;

export function useOwnedVerifierCaps() {
  const account = useCurrentAccount();

  return useQuery({
    queryKey: ['ownedVerifierCaps', account?.address],
    queryFn: async () => {
      const result = await jsonRpcClient.getOwnedObjects({
        owner: account!.address,
        filter: { StructType: CAP_TYPE },
        options: { showContent: true },
      });

      return result.data
        .filter((obj) => obj.data?.content?.dataType === 'moveObject')
        .map((obj): ParsedVerifierCap => {
          const data = obj.data!;
          const fields = (data.content as { fields: Record<string, unknown> }).fields;
          return {
            id: data.objectId,
            bountyId: String(fields.bounty_id ?? ''),
          };
        });
    },
    enabled: !!account,
  });
}
