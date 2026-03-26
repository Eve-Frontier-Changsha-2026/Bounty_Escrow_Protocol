import { useState, useMemo } from 'react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { Button } from './ui/Button';
import { useCharacters } from '../hooks/useCharacters';
import { useKillmails } from '../hooks/useKillmails';
import { useTransactionExecutor } from '../hooks/useTransactionExecutor';
import { buildVerifyKill } from '../lib/ptb/verify-kill';
import type { ParsedBounty, Toast } from '../lib/types';
import type { EveCharacter, EveKillmail } from '../lib/eve-api';

const INVALIDATE_KEYS = [['bountyDetail'], ['bountyList'], ['ownedTickets'], ['proofSubmission']];

interface KillVerifyButtonProps {
  bounty: ParsedBounty;
  targetVictimId?: string;   // u64 from bounty DF (if set)
  createdAt: number;         // task type created_at (ms)
  onToast: (t: Toast) => void;
}

export function KillVerifyButton({ bounty, targetVictimId: _targetVictimId, createdAt, onToast }: KillVerifyButtonProps) {
  const account = useCurrentAccount();
  const { data: characters = [], isLoading: charsLoading } = useCharacters();
  const { data: killmails = [], isLoading: killsLoading } = useKillmails();
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);

  // Hunter characters (matched by wallet address)
  const hunterChars = useMemo(
    () => characters.filter((c) => c.address === account?.address),
    [characters, account?.address],
  );

  // If multiple characters, let hunter pick
  const [selectedCharId, setSelectedCharId] = useState<string | null>(null);

  const activeChar: EveCharacter | undefined =
    hunterChars.length === 1
      ? hunterChars[0]
      : hunterChars.find((c) => c.id === selectedCharId) ?? undefined;

  // Find matching killmail
  const matchingKillmail: EveKillmail | undefined = useMemo(() => {
    if (!activeChar) return undefined;

    const candidates = killmails
      .filter((km) => {
        // Hunter must be the killer
        if (km.killerId !== activeChar.id) return false;
        // Kill must be after bounty task type creation
        if (km.killedAt < createdAt) return false;
        return true;
      })
      // Sort by killedAt desc — use most recent
      .sort((a, b) => b.killedAt - a.killedAt);

    return candidates[0];
  }, [killmails, activeChar, createdAt]);

  const isLoading = charsLoading || killsLoading;

  async function handleVerify() {
    if (!activeChar || !matchingKillmail) return;
    try {
      const tx = buildVerifyKill({
        bountyId: bounty.id,
        killmailId: matchingKillmail.id,
        characterId: activeChar.id,
        coinType: bounty.coinType,
      });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Kill verified! Bounty auto-approved.', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Verify kill failed' });
    }
  }

  // --- Render states ---

  if (isLoading) {
    return <p className="text-xs text-eve-sub">Loading characters & killmails...</p>;
  }

  if (hunterChars.length === 0) {
    return (
      <p className="text-xs text-eve-sub">
        No EVE character found for your wallet. Create a character in-game first.
      </p>
    );
  }

  // Multiple characters — show picker
  if (hunterChars.length > 1 && !activeChar) {
    return (
      <div className="space-y-2">
        <p className="text-xs text-eve-sub">Select your character:</p>
        <div className="flex flex-wrap gap-2">
          {hunterChars.map((c) => (
            <button
              key={c.id}
              type="button"
              onClick={() => setSelectedCharId(c.id)}
              className="px-3 py-1.5 text-xs bg-eve-bg-2 border border-eve-panel-border rounded hover:border-eve-cyan/60 transition-colors"
            >
              {c.name}
            </button>
          ))}
        </div>
      </div>
    );
  }

  if (!matchingKillmail) {
    return (
      <div className="space-y-1">
        <p className="text-xs text-eve-sub">
          No matching killmail found for <span className="text-eve-text">{activeChar!.name}</span>.
        </p>
        <p className="text-[10px] text-eve-sub/60">
          Kill must be recorded on-chain after bounty creation ({new Date(createdAt).toLocaleDateString()}).
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      <div className="text-xs text-eve-sub space-y-0.5">
        <p>
          Killmail found: <span className="text-eve-text">{activeChar!.name}</span> killed{' '}
          <span className="text-eve-danger">{matchingKillmail.victimName}</span>
        </p>
        <p className="text-[10px] text-eve-sub/60">
          {new Date(matchingKillmail.killedAt).toLocaleString()} · Solar System {matchingKillmail.solarSystemId} · {matchingKillmail.lossType}
        </p>
      </div>
      <Button variant="primary" disabled={isPending} onClick={handleVerify} className="w-full">
        {isPending ? 'VERIFYING KILL...' : 'VERIFY KILL (AUTO-APPROVE)'}
      </Button>
    </div>
  );
}
