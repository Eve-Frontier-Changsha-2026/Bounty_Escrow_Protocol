const EVE_EYES_BASE = import.meta.env.DEV
  ? '/eve-eyes-api'
  : 'https://eve-eyes.d0v.xyz';

const API_KEY = import.meta.env.VITE_EVE_EYES_API_KEY ?? '';

function headers(): Record<string, string> {
  const h: Record<string, string> = { 'Content-Type': 'application/json' };
  if (API_KEY) h['Authorization'] = `ApiKey ${API_KEY}`;
  return h;
}

// --- Types ---

export interface EveEyesKillmail {
  killmailItemId: string;
  killTimestamp: number;
  killer: { label: string };
  victim: { label: string };
  status: string;
}

export interface BuildingLeaderboardEntry {
  ownerCharacter: string;
  resolvedWallet: string;
  moduleName: string;
  count: number;
}

export interface SolarSystemResult {
  id: number;
  name: string;
}

// --- Fetchers ---

export async function fetchKillmailFeed(
  limit?: number,
  status?: 'resolved' | 'pending',
): Promise<EveEyesKillmail[]> {
  const params = new URLSearchParams();
  if (limit) params.set('limit', String(limit));
  if (status) params.set('status', status);
  const qs = params.toString();

  const res = await fetch(
    `${EVE_EYES_BASE}/api/indexer/killmails${qs ? `?${qs}` : ''}`,
    { headers: headers() },
  );
  if (!res.ok) throw new Error(`Eve Eyes killmails error: ${res.status}`);
  const data = await res.json();
  return data.items ?? [];
}

export async function fetchBuildingLeaderboard(
  limit?: number,
  moduleName?: string,
): Promise<BuildingLeaderboardEntry[]> {
  const params = new URLSearchParams();
  if (limit) params.set('limit', String(limit));
  if (moduleName) params.set('moduleName', moduleName);
  const qs = params.toString();

  const res = await fetch(
    `${EVE_EYES_BASE}/api/v1/indexer/building-leaderboard${qs ? `?${qs}` : ''}`,
    { headers: headers() },
  );
  if (!res.ok) throw new Error(`Eve Eyes leaderboard error: ${res.status}`);
  const data = await res.json();
  return data.leaderboard ?? [];
}

export async function fetchSystemSearch(
  query: string,
): Promise<SolarSystemResult[]> {
  if (!query.trim()) return [];

  const res = await fetch(
    `${EVE_EYES_BASE}/api/world/systems/search?q=${encodeURIComponent(query)}`,
    { headers: headers() },
  );
  if (!res.ok) throw new Error(`Eve Eyes systems error: ${res.status}`);
  const data = await res.json();
  return data.data ?? [];
}
