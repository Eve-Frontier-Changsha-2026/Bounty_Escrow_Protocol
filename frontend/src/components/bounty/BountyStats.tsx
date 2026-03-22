import { mistToSui } from '../../lib/format';

interface BountyStatsProps {
  rewardAmount: bigint;
  requiredStake: bigint;
  activeClaims: number;
  maxClaims: number;
  escrowValue: bigint;
}

export function BountyStats({ rewardAmount, requiredStake, activeClaims, maxClaims, escrowValue }: BountyStatsProps) {
  const progress = maxClaims > 0 ? (activeClaims / maxClaims) * 100 : 0;

  return (
    <div className="space-y-3">
      <div className="grid grid-cols-3 gap-3 text-center">
        <div>
          <div className="text-xs text-eve-sub uppercase">Reward</div>
          <div className="text-sm font-heading text-eve-gold">{mistToSui(rewardAmount)} SUI</div>
        </div>
        <div>
          <div className="text-xs text-eve-sub uppercase">Stake</div>
          <div className="text-sm font-heading text-eve-cyan">{mistToSui(requiredStake)} SUI</div>
        </div>
        <div>
          <div className="text-xs text-eve-sub uppercase">Escrow</div>
          <div className="text-sm font-heading text-eve-text">{mistToSui(escrowValue)} SUI</div>
        </div>
      </div>

      <div>
        <div className="flex justify-between text-xs text-eve-sub mb-1">
          <span>Claims</span>
          <span>{activeClaims} / {maxClaims}</span>
        </div>
        <div className="h-1.5 bg-eve-bg-2 rounded-full overflow-hidden">
          <div
            className="h-full bg-gradient-to-r from-eve-cyan to-eve-gold rounded-full transition-all duration-500"
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>
    </div>
  );
}
