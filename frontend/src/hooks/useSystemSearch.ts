import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { fetchSystemSearch } from '../lib/eve-eyes-api';
import type { SolarSystemResult } from '../lib/eve-eyes-api';

function useDebouncedValue(value: string, delayMs: number): string {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(id);
  }, [value, delayMs]);
  return debounced;
}

export function useSystemSearch(query: string) {
  const trimmed = useDebouncedValue(query.trim(), 300);
  return useQuery<SolarSystemResult[]>({
    queryKey: ['systemSearch', trimmed],
    queryFn: () => fetchSystemSearch(trimmed),
    enabled: trimmed.length >= 2,
    staleTime: 5 * 60_000,
  });
}
