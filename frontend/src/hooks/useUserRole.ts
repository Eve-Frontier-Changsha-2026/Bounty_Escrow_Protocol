import { useMemo } from 'react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { useOwnedTickets } from './useOwnedTickets';
import { useOwnedVerifierCaps } from './useOwnedVerifierCaps';
import type { ParsedBounty } from '../lib/types';

const EMPTY = { isCreator: false, isHunter: false, isVerifier: false, ticket: null, verifierCap: null } as const;

export function useUserRole(bounty: ParsedBounty | undefined) {
  const account = useCurrentAccount();
  const { data: tickets } = useOwnedTickets();
  const { data: caps } = useOwnedVerifierCaps();

  return useMemo(() => {
    if (!bounty || !account) return EMPTY;

    const isCreator = bounty.creator === account.address;
    const ticket = tickets?.find((t) => t.bountyId === bounty.id) ?? null;
    const verifierCap = caps?.find((c) => c.bountyId === bounty.id) ?? null;

    return {
      isCreator,
      isHunter: !!ticket,
      isVerifier: !!verifierCap,
      ticket,
      verifierCap,
    };
  }, [bounty, account, tickets, caps]);
}
