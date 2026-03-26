import { useQuery } from '@tanstack/react-query';
import { fetchCharacters } from '../lib/eve-api';
import type { EveCharacter } from '../lib/eve-api';

export function useCharacters() {
  return useQuery<EveCharacter[]>({
    queryKey: ['eveCharacters'],
    queryFn: fetchCharacters,
    staleTime: 5 * 60_000,
  });
}
