import { truncateAddress } from '../../lib/format';

interface HunterListProps {
  activeHunterStakes: [string, string][];
  approvedHunters: string[];
}

export function HunterList({ activeHunterStakes, approvedHunters }: HunterListProps) {
  if (activeHunterStakes.length === 0) {
    return <p className="text-eve-sub text-xs">No active hunters</p>;
  }

  const approvedSet = new Set(approvedHunters);

  return (
    <div className="space-y-2">
      {activeHunterStakes.map(([hunter, stake]) => (
        <div
          key={hunter}
          className="flex items-center justify-between py-2 px-3 rounded bg-eve-bg-2/50"
        >
          <div className="flex items-center gap-2">
            <span className="font-mono text-xs text-eve-text">{truncateAddress(hunter)}</span>
            {approvedSet.has(hunter) && (
              <span className="text-xs text-status-completed border border-status-completed/40 bg-status-completed/10 px-1.5 py-0.5 rounded-full">
                APPROVED
              </span>
            )}
          </div>
          <span className="text-xs text-eve-sub">
            {Number(stake) / 1e9} SUI staked
          </span>
        </div>
      ))}
    </div>
  );
}
