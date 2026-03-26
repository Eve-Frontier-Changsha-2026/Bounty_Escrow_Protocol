import { describe, it, expect, vi, beforeEach } from 'vitest';
import { fetchCharacters, fetchKillmails } from './eve-api';
import type { EveCharacter, EveKillmail } from './eve-api';

const mockCharacters: EveCharacter[] = [
  {
    id: '0xabc123',
    name: 'ramonliao',
    address: '0xwallet1',
    tribeId: 1,
    tribeName: 'TestTribe',
    tribeTicker: 'TT',
    createdAt: 1000,
  },
  {
    id: '0xdef456',
    name: 'hunter2',
    address: '0xwallet2',
    tribeId: 2,
    tribeName: 'OtherTribe',
    tribeTicker: 'OT',
    createdAt: 2000,
  },
];

const mockKillmails: EveKillmail[] = [
  {
    id: '0xkill1',
    killerId: '0xabc123',
    killerName: 'ramonliao',
    victimId: '0xdef456',
    victimName: 'hunter2',
    reporterId: '0xreporter',
    reporterName: 'reporter1',
    lossType: 'SHIP',
    solarSystemId: 30000142,
    killedAt: 5000,
    shard: 1,
  },
];

beforeEach(() => {
  vi.restoreAllMocks();
});

describe('fetchCharacters', () => {
  it('returns character items on success', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ items: mockCharacters }),
    }));

    const result = await fetchCharacters();
    expect(result).toEqual(mockCharacters);
    expect(result).toHaveLength(2);
    expect(fetch).toHaveBeenCalledWith('https://utopia.evedataco.re/api/characters');
  });

  it('throws on non-ok response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 500,
    }));

    await expect(fetchCharacters()).rejects.toThrow('Characters API error: 500');
  });

  it('throws on network error', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('Network failed')));
    await expect(fetchCharacters()).rejects.toThrow('Network failed');
  });

  it('handles empty items array', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ items: [] }),
    }));

    const result = await fetchCharacters();
    expect(result).toEqual([]);
  });
});

describe('fetchKillmails', () => {
  it('returns killmail items on success', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ items: mockKillmails }),
    }));

    const result = await fetchKillmails();
    expect(result).toEqual(mockKillmails);
    expect(result[0].killerId).toBe('0xabc123');
    expect(fetch).toHaveBeenCalledWith('https://utopia.evedataco.re/api/killmails');
  });

  it('throws on non-ok response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 403,
    }));

    await expect(fetchKillmails()).rejects.toThrow('Killmails API error: 403');
  });

  it('handles empty killmails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ items: [] }),
    }));

    const result = await fetchKillmails();
    expect(result).toEqual([]);
  });
});

// --- Monkey Tests ---

describe('fetchCharacters — edge cases', () => {
  it('handles malformed JSON gracefully', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.reject(new SyntaxError('Unexpected token')),
    }));
    await expect(fetchCharacters()).rejects.toThrow('Unexpected token');
  });

  it('handles 429 rate limit', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: false,
      status: 429,
    }));
    await expect(fetchCharacters()).rejects.toThrow('Characters API error: 429');
  });
});

describe('fetchKillmails — edge cases', () => {
  it('handles huge payload (1000 items)', async () => {
    const bigPayload = Array.from({ length: 1000 }, (_, i) => ({
      ...mockKillmails[0],
      id: `0xkill${i}`,
      killedAt: i * 1000,
    }));
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ items: bigPayload }),
    }));

    const result = await fetchKillmails();
    expect(result).toHaveLength(1000);
  });
});
