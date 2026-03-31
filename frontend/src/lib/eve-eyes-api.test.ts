// frontend/src/lib/eve-eyes-api.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  fetchKillmailFeed,
  fetchBuildingLeaderboard,
  fetchSystemSearch,
} from './eve-eyes-api';
import type {
  EveEyesKillmail,
  BuildingLeaderboardEntry,
  SolarSystemResult,
} from './eve-eyes-api';

const mockKillmail: EveEyesKillmail = {
  killmailItemId: '12345',
  killTimestamp: 1711900000000,
  killer: { label: 'ramonliao' },
  victim: { label: 'target1' },
  status: 'resolved',
};

const mockBuilding: BuildingLeaderboardEntry = {
  ownerCharacter: 'ramonliao',
  resolvedWallet: '0xwallet1',
  moduleName: 'gate',
  count: 3,
};

const mockSystem: SolarSystemResult = {
  id: 30000142,
  name: 'Jita',
};

beforeEach(() => {
  vi.restoreAllMocks();
});

describe('fetchKillmailFeed', () => {
  it('fetches killmails with default params', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ items: [mockKillmail] }),
    }));

    const result = await fetchKillmailFeed();
    expect(result).toEqual([mockKillmail]);
    expect(fetch).toHaveBeenCalledWith(
      expect.stringContaining('/api/indexer/killmails'),
      expect.objectContaining({ headers: expect.any(Object) }),
    );
  });

  it('passes limit and status params', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ items: [] }),
    }));

    await fetchKillmailFeed(10, 'resolved');
    const url = (fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
    expect(url).toContain('limit=10');
    expect(url).toContain('status=resolved');
  });

  it('throws on non-ok response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 500 }));
    await expect(fetchKillmailFeed()).rejects.toThrow('Eve Eyes killmails error: 500');
  });
});

describe('fetchBuildingLeaderboard', () => {
  it('fetches leaderboard with moduleName filter', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ leaderboard: [mockBuilding] }),
    }));

    const result = await fetchBuildingLeaderboard(10, 'gate');
    expect(result).toEqual([mockBuilding]);
    const url = (fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
    expect(url).toContain('moduleName=gate');
  });

  it('throws on non-ok response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 403 }));
    await expect(fetchBuildingLeaderboard()).rejects.toThrow('Eve Eyes leaderboard error: 403');
  });
});

describe('fetchSystemSearch', () => {
  it('searches systems by query', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ data: [mockSystem] }),
    }));

    const result = await fetchSystemSearch('jita');
    expect(result).toEqual([mockSystem]);
    const url = (fetch as ReturnType<typeof vi.fn>).mock.calls[0][0] as string;
    expect(url).toContain('q=jita');
  });

  it('returns empty array for empty query', async () => {
    const result = await fetchSystemSearch('');
    expect(result).toEqual([]);
  });

  it('throws on non-ok response', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 404 }));
    await expect(fetchSystemSearch('xyz')).rejects.toThrow('Eve Eyes systems error: 404');
  });
});

// --- Monkey Tests ---

describe('fetchKillmailFeed — edge cases', () => {
  it('handles malformed JSON', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.reject(new SyntaxError('Unexpected token')),
    }));
    await expect(fetchKillmailFeed()).rejects.toThrow('Unexpected token');
  });

  it('handles missing items field gracefully', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({}),
    }));
    const result = await fetchKillmailFeed();
    expect(result).toEqual([]);
  });
});

describe('fetchBuildingLeaderboard — edge cases', () => {
  it('handles missing leaderboard field', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ ok: true }),
    }));
    const result = await fetchBuildingLeaderboard();
    expect(result).toEqual([]);
  });
});
