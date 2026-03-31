import { useQuery } from '@tanstack/react-query';
import { fetchSystemSearch } from '../lib/eve-eyes-api';
import type { SolarSystemResult } from '../lib/eve-eyes-api';

export function useSystemSearch(query: string) {
  const trimmed = query.trim();
  return useQuery<SolarSystemResult[]>({
    queryKey: ['systemSearch', trimmed],
    queryFn: () => fetchSystemSearch(trimmed),
    enabled: trimmed.length >= 2,
    staleTime: 5 * 60_000,
  });
}
