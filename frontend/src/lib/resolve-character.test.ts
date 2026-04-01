import { describe, it, expect, vi, beforeEach } from 'vitest';
import { resolveCharacterItemId } from './resolve-character';

const mockGetObject = vi.fn();
const mockClient = { getObject: mockGetObject } as Parameters<typeof resolveCharacterItemId>[0];

beforeEach(() => {
  vi.clearAllMocks();
});

describe('resolveCharacterItemId', () => {
  it('resolves a valid Character object to item_id', async () => {
    mockGetObject.mockResolvedValue({
      data: {
        objectId: '0xabc123',
        version: '1',
        digest: 'test',
        content: {
          dataType: 'moveObject',
          type: '0x::character::Character',
          hasPublicTransfer: false,
          fields: {
            key: {
              fields: {
                item_id: '2112000187',
              },
            },
          },
        },
      },
    });

    const result = await resolveCharacterItemId(mockClient, '0xabc123');
    expect(result).toBe('2112000187');
    expect(mockGetObject).toHaveBeenCalledWith({
      id: '0xabc123',
      options: { showContent: true },
    });
  });

  it('throws when object not found (no data)', async () => {
    mockGetObject.mockResolvedValue({ data: null } as never);

    await expect(resolveCharacterItemId(mockClient, '0xnonexist'))
      .rejects.toThrow('Character object not found: 0xnonexist');
  });

  it('throws when content is not moveObject', async () => {
    mockGetObject.mockResolvedValue({
      data: {
        objectId: '0xpkg',
        version: '1',
        digest: 'test',
        content: {
          dataType: 'package',
        },
      },
    } as never);

    await expect(resolveCharacterItemId(mockClient, '0xpkg'))
      .rejects.toThrow('Character object not found: 0xpkg');
  });

  it('throws when key.item_id is missing', async () => {
    mockGetObject.mockResolvedValue({
      data: {
        objectId: '0xbad',
        version: '1',
        digest: 'test',
        content: {
          dataType: 'moveObject',
          type: '0x::character::Character',
          hasPublicTransfer: false,
          fields: {
            name: 'test',
          },
        },
      },
    });

    await expect(resolveCharacterItemId(mockClient, '0xbad'))
      .rejects.toThrow('Character missing key.item_id: 0xbad');
  });

  it('throws when key exists but item_id is undefined', async () => {
    mockGetObject.mockResolvedValue({
      data: {
        objectId: '0xpartial',
        version: '1',
        digest: 'test',
        content: {
          dataType: 'moveObject',
          type: '0x::character::Character',
          hasPublicTransfer: false,
          fields: {
            key: { fields: {} },
          },
        },
      },
    });

    await expect(resolveCharacterItemId(mockClient, '0xpartial'))
      .rejects.toThrow('Character missing key.item_id: 0xpartial');
  });

  // --- Monkey Tests ---

  it('handles RPC network failure', async () => {
    mockGetObject.mockRejectedValue(new Error('RPC timeout'));
    await expect(resolveCharacterItemId(mockClient, '0xany')).rejects.toThrow('RPC timeout');
  });

  it('handles empty string object ID', async () => {
    mockGetObject.mockResolvedValue({ data: null } as never);
    await expect(resolveCharacterItemId(mockClient, '')).rejects.toThrow('Character object not found: ');
  });

  it('returns string item_id even for large u64 values', async () => {
    mockGetObject.mockResolvedValue({
      data: {
        objectId: '0xlarge',
        version: '1',
        digest: 'test',
        content: {
          dataType: 'moveObject',
          type: '0x::character::Character',
          hasPublicTransfer: false,
          fields: {
            key: {
              fields: {
                item_id: '18446744073709551615', // u64 max
              },
            },
          },
        },
      },
    });

    const result = await resolveCharacterItemId(mockClient, '0xlarge');
    expect(result).toBe('18446744073709551615');
  });
});
