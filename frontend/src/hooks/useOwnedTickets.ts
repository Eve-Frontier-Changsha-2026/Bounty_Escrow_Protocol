import { useQuery } from '@tanstack/react-query';
import { useCurrentAccount, useCurrentClient } from '@mysten/dapp-kit-react';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';
import type { ParsedClaimTicket } from '../lib/types';

const TICKET_TYPE = `${ORIGINAL_PACKAGE_ID}::bounty::ClaimTicket`;

export function useOwnedTickets() {
  const account = useCurrentAccount();
  const client = useCurrentClient();

  return useQuery({
    queryKey: ['ownedTickets', account?.address],
    queryFn: async () => {
      const result = await client.getOwnedObjects({
        owner: account!.address,
        filter: { StructType: TICKET_TYPE },
        options: { showContent: true },
      });

      return result.data
        .filter((obj) => obj.data?.content?.dataType === 'moveObject')
        .map((obj): ParsedClaimTicket => {
          const data = obj.data!;
          const fields = (data.content as { fields: Record<string, unknown> }).fields;
          return {
            id: data.objectId,
            bountyId: String(fields.bounty_id ?? ''),
            hunter: String(fields.hunter ?? ''),
            stakeAmount: BigInt(String(fields.stake_amount ?? '0')),
            claimedAt: Number(fields.claimed_at ?? 0),
          };
        });
    },
    enabled: !!account,
    staleTime: 60_000,
  });
}
