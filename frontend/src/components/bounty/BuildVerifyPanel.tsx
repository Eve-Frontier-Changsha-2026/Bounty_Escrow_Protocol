import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { useBuildingLeaderboard } from '../../hooks/useBuildingLeaderboard';
import { LoadingSpinner } from '../ui/LoadingSpinner';
import type { BuildingLeaderboardEntry } from '../../lib/eve-eyes-api';

const MODULE_LABEL: Record<string, string> = {
  assembly: 'ASSEMBLY',
  gate: 'GATE',
  network_node: 'NETWORK NODE',
  storage_unit: 'STORAGE UNIT',
  turret: 'TURRET',
};

const MODULE_COLOR: Record<string, string> = {
  assembly: 'text-eve-gold bg-eve-gold/10',
  gate: 'text-eve-cyan bg-eve-cyan/10',
  network_node: 'text-eve-accent bg-eve-accent/10',
  storage_unit: 'text-eve-text bg-eve-bg-2',
  turret: 'text-eve-danger bg-eve-danger/10',
};

export function BuildVerifyPanel() {
  const account = useCurrentAccount();

  const { data: buildings, isLoading, error } = useBuildingLeaderboard(
    account?.address,
    undefined,
  );

  if (!account) return null;
  if (error) return null;

  return (
    <div>
      <h3 className="font-heading text-xs text-eve-gold tracking-wider mb-2">
        YOUR BUILDINGS
      </h3>
      <p className="text-[10px] text-eve-sub/60 mb-3">
        Buildings detected for your wallet via Eve Eyes. Oracle attestation still required for on-chain verification.
      </p>

      {isLoading && (
        <div className="flex justify-center py-4">
          <LoadingSpinner size="sm" />
        </div>
      )}

      {!isLoading && (!buildings || buildings.length === 0) && (
        <p className="text-xs text-eve-sub py-2">
          No buildings found for your wallet. Build a structure in-game and check back.
        </p>
      )}

      {buildings && buildings.length > 0 && (
        <div className="space-y-1.5">
          {buildings.map((b, i) => (
            <BuildingRow key={`${b.moduleName}-${b.ownerCharacter}-${i}`} building={b} />
          ))}
        </div>
      )}

      <div className="mt-3 p-2 rounded bg-eve-bg-2/50 border border-eve-panel-border/30">
        <p className="text-[10px] text-eve-sub/80">
          Oracle attestation pending. Your building has been found — verification will complete automatically once the oracle signs.
        </p>
      </div>
    </div>
  );
}

function BuildingRow({ building }: { building: BuildingLeaderboardEntry }) {
  const colorClass = MODULE_COLOR[building.moduleName] ?? 'text-eve-sub bg-eve-bg-2';
  const label = MODULE_LABEL[building.moduleName] ?? building.moduleName.toUpperCase();

  return (
    <div className="flex items-center gap-3 px-3 py-2 bg-eve-bg-2/50 rounded border border-eve-panel-border/30">
      <span
        className={`text-[10px] px-1.5 py-0.5 rounded font-heading tracking-wider ${colorClass}`}
      >
        {label}
      </span>
      <div className="flex-1 min-w-0 text-xs">
        <span className="text-eve-text">{building.ownerCharacter}</span>
      </div>
      <span className="text-[10px] text-eve-sub/60">
        x{building.count}
      </span>
    </div>
  );
}
