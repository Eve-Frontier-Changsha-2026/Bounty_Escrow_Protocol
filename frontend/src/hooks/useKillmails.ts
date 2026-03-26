import { useQuery } from '@tanstack/react-query';
import { fetchKillmails } from '../lib/eve-api';
import type { EveKillmail } from '../lib/eve-api';

export function useKillmails() {
  return useQuery<EveKillmail[]>({
    queryKey: ['eveKillmails'],
    queryFn: fetchKillmails,
    staleTime: 5 * 60_000,
  });
}
