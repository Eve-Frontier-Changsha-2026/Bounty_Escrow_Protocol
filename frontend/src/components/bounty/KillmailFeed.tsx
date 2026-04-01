import { useState } from 'react';
import { useKillmailFeed } from '../../hooks/useKillmailFeed';
import { LoadingSpinner } from '../ui/LoadingSpinner';
import { timeAgo } from '../../lib/format';
import type { EveEyesKillmail } from '../../lib/eve-eyes-api';

type StatusFilter = 'all' | 'resolved' | 'pending';

export function KillmailFeed() {
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all');
  const apiStatus = statusFilter === 'all' ? undefined : statusFilter;
  const { data: killmails, isLoading, error } = useKillmailFeed(20, apiStatus);

  const filters: { value: StatusFilter; label: string }[] = [
    { value: 'all', label: 'ALL' },
    { value: 'resolved', label: 'RESOLVED' },
    { value: 'pending', label: 'PENDING' },
  ];

  if (error) {
    return (
      <div className="text-xs text-eve-sub/60 text-center py-4">
        Kill feed unavailable
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <h2 className="font-heading text-sm text-eve-danger tracking-wider">
          RECENT KILLS
        </h2>
        <div className="flex gap-1">
          {filters.map((f) => (
            <button
              key={f.value}
              onClick={() => setStatusFilter(f.value)}
              className={`px-2 py-1 rounded-full text-[10px] font-heading tracking-wider transition-all cursor-pointer ${
                statusFilter === f.value
                  ? 'bg-eve-danger/20 text-eve-danger border border-eve-danger/40'
                  : 'text-eve-sub hover:text-eve-text border border-transparent'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {isLoading && (
        <div className="flex justify-center py-6">
          <LoadingSpinner size="sm" />
        </div>
      )}

      {killmails && killmails.length === 0 && (
        <p className="text-xs text-eve-sub text-center py-4">
          No killmails found
        </p>
      )}

      {killmails && killmails.length > 0 && (
        <div className="space-y-1.5">
          {killmails.map((km, i) => (
            <KillmailRow key={`${km.killmailItemId}-${i}`} killmail={km} />
          ))}
        </div>
      )}
    </div>
  );
}

function KillmailRow({ killmail }: { killmail: EveEyesKillmail }) {
  return (
    <div className="flex items-center gap-3 px-3 py-2 bg-eve-bg-2/50 rounded-lg border border-eve-panel-border/30 hover:border-eve-danger/30 transition-colors">
      <div className="flex-1 min-w-0">
        <div className="text-xs">
          <span className="text-eve-text font-heading">
            {killmail.killer.label}
          </span>
          <span className="text-eve-sub mx-1.5">&rarr;</span>
          <span className="text-eve-danger font-heading">
            {killmail.victim.label}
          </span>
        </div>
      </div>
      <span
        className={`text-[10px] px-1.5 py-0.5 rounded font-heading tracking-wider ${
          killmail.status === 'resolved'
            ? 'text-status-completed bg-status-completed/10'
            : 'text-eve-gold bg-eve-gold/10'
        }`}
      >
        {killmail.status.toUpperCase()}
      </span>
      <span className="text-[10px] text-eve-sub/60 whitespace-nowrap">
        {timeAgo(killmail.killTimestamp)}
      </span>
    </div>
  );
}
