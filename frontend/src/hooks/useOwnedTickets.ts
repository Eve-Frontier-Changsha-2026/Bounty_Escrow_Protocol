import { useQuery } from '@tanstack/react-query';
import { useCurrentAccount, useCurrentClient } from '@mysten/dapp-kit-react';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';
import type { ParsedClaimTicket } from '../lib/types';

const TICKET_TYPE = `${ORIGINAL_PACKAGE_ID}::bounty::ClaimTicket`;
const MAX_PAGES = 10;

export function useOwnedTickets() {
  const account = useCurrentAccount();
  const client = useCurrentClient();

  return useQuery({
    queryKey: ['ownedTickets', account?.address],
    queryFn: async () => {
      const all: ParsedClaimTicket[] = [];
      let cursor: string | null | undefined;

      for (let page = 0; page < MAX_PAGES; page++) {
        const result = await client.getOwnedObjects({
          owner: account!.address,
          filter: { StructType: TICKET_TYPE },
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
            hunter: String(fields.hunter ?? ''),
            stakeAmount: BigInt(String(fields.stake_amount ?? '0')),
            claimedAt: Number(fields.claimed_at ?? 0),
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
