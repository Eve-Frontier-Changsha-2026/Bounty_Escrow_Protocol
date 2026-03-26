const EVE_API_BASE = 'https://utopia.evedataco.re';

export interface EveCharacter {
  id: string;         // Sui Object ID
  name: string;
  address: string;    // wallet address
  tribeId: number;
  tribeName: string;
  tribeTicker: string;
  createdAt: number;
}

export interface EveKillmail {
  id: string;         // Sui Object ID
  killerId: string;   // Character Object ID
  killerName: string;
  victimId: string;   // Character Object ID
  victimName: string;
  reporterId: string;
  reporterName: string;
  lossType: string;   // "SHIP" | "STRUCTURE"
  solarSystemId: number;
  killedAt: number;   // ms timestamp
  shard: number;
}

export async function fetchCharacters(): Promise<EveCharacter[]> {
  const res = await fetch(`${EVE_API_BASE}/api/characters`);
  if (!res.ok) throw new Error(`Characters API error: ${res.status}`);
  const data: { items: EveCharacter[] } = await res.json();
  return data.items;
}

export async function fetchKillmails(): Promise<EveKillmail[]> {
  const res = await fetch(`${EVE_API_BASE}/api/killmails`);
  if (!res.ok) throw new Error(`Killmails API error: ${res.status}`);
  const data: { items: EveKillmail[] } = await res.json();
  return data.items;
}
