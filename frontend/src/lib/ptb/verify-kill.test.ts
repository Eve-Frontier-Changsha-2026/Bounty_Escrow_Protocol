import { describe, it, expect, vi } from 'vitest';
import { Transaction } from '@mysten/sui/transactions';
import { buildVerifyKill } from './verify-kill';

vi.mock('../../config/contracts', () => ({
  PACKAGE_ID: '0xPKG',
  CLOCK: '0x6',
  DEFAULT_COIN_TYPE: '0x2::sui::SUI',
}));

describe('buildVerifyKill', () => {
  it('returns a Transaction instance', () => {
    const tx = buildVerifyKill({
      bountyId: '0xbounty1',
      killmailId: '0xkill1',
      characterId: '0xchar1',
    });
    expect(tx).toBeInstanceOf(Transaction);
  });

  it('does not throw with custom coin type', () => {
    expect(() =>
      buildVerifyKill({
        bountyId: '0xbounty1',
        killmailId: '0xkill1',
        characterId: '0xchar1',
        coinType: '0xcustom::token::TOKEN',
      })
    ).not.toThrow();
  });

  it('returns a new Transaction each call (no state leak)', () => {
    const tx1 = buildVerifyKill({ bountyId: '0xb1', killmailId: '0xk1', characterId: '0xc1' });
    const tx2 = buildVerifyKill({ bountyId: '0xb2', killmailId: '0xk2', characterId: '0xc2' });
    expect(tx1).not.toBe(tx2);
  });

  it('handles very long object IDs without throwing', () => {
    const longId = '0x' + 'a'.repeat(64);
    expect(() =>
      buildVerifyKill({
        bountyId: longId,
        killmailId: longId,
        characterId: longId,
      })
    ).not.toThrow();
  });
});
