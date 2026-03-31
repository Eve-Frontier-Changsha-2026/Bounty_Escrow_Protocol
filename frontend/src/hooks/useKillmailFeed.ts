import { useQuery } from '@tanstack/react-query';
import { fetchKillmailFeed } from '../lib/eve-eyes-api';
import type { EveEyesKillmail } from '../lib/eve-eyes-api';

export function useKillmailFeed(
  limit?: number,
  status?: 'resolved' | 'pending',
) {
  return useQuery<EveEyesKillmail[]>({
    queryKey: ['killmailFeed', limit, status],
    queryFn: () => fetchKillmailFeed(limit, status),
    staleTime: 30_000,
    refetchInterval: 30_000,
  });
}
