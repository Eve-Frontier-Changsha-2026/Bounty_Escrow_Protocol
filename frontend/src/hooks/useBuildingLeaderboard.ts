import { useQuery } from '@tanstack/react-query';
import { fetchBuildingLeaderboard } from '../lib/eve-eyes-api';
import type { BuildingLeaderboardEntry } from '../lib/eve-eyes-api';

export function useBuildingLeaderboard(
  walletAddress?: string,
  moduleName?: string,
) {
  return useQuery<BuildingLeaderboardEntry[]>({
    queryKey: ['buildingLeaderboard', moduleName],
    queryFn: () => fetchBuildingLeaderboard(50, moduleName),
    staleTime: 60_000,
    enabled: !!walletAddress,
    select: (data) =>
      walletAddress
        ? data.filter(
            (e) =>
              e.resolvedWallet.toLowerCase() === walletAddress.toLowerCase(),
          )
        : data,
  });
}
