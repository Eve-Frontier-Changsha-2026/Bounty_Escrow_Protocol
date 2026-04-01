import { Link } from 'react-router-dom';
import type { ParsedBounty } from '../../lib/types';
import { BountyStatus } from '../../lib/constants';
import { truncateAddress } from '../../lib/format';
import { StatusBadge } from './StatusBadge';
import { TaskTypeBadge } from './TaskTypeBadge';
import { CountdownTimer } from './CountdownTimer';
import { BountyStats } from './BountyStats';

interface BountyCardProps {
  bounty: ParsedBounty;
  /** Pre-fetched task type (from batch query). When omitted, no badge is shown. */
  taskType?: number;
}

export function BountyCard({ bounty, taskType }: BountyCardProps) {
  const isActive = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;

  return (
    <Link
      to={`/bounty/${bounty.id}`}
      className="eve-panel rounded-lg p-5 hover:border-eve-cyan/50 transition-all duration-300 hover:shadow-[0_0_20px_rgba(102,203,255,0.15)] block"
    >
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-2 flex-1 mr-2 min-w-0">
          <h3 className="font-heading text-sm text-eve-text truncate">
            {bounty.title}
          </h3>
          {taskType != null && <TaskTypeBadge taskType={taskType} />}
        </div>
        <StatusBadge status={bounty.status} />
      </div>

      <p className="text-xs text-eve-sub line-clamp-2 mb-4">
        {bounty.description}
      </p>

      <BountyStats
        rewardAmount={bounty.rewardAmount}
        requiredStake={bounty.requiredStake}
        activeClaims={bounty.activeClaims}
        maxClaims={bounty.maxClaims}
        escrowValue={bounty.escrowValue}
      />

      <div className="flex items-center justify-between mt-4 pt-3 border-t border-eve-panel-border/50">
        <span className="text-xs text-eve-sub">
          by {truncateAddress(bounty.creator)}
        </span>
        {isActive && (
          <CountdownTimer targetMs={bounty.deadline} label="Deadline" />
        )}
      </div>
    </Link>
  );
}
