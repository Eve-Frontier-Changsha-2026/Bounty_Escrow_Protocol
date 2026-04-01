import { useMemo } from 'react';
import { useKillmailFeed } from '../../hooks/useKillmailFeed';
import { LoadingSpinner } from '../ui/LoadingSpinner';
import { timeAgo } from '../../lib/format';
import type { EveEyesKillmail } from '../../lib/eve-eyes-api';

interface KillmailMatchPanelProps {
  taskCreatedAt: number;
}

export function KillmailMatchPanel({
  taskCreatedAt,
}: KillmailMatchPanelProps) {
  const { data: killmails, isLoading, error } = useKillmailFeed(50, 'resolved');

  const matches = useMemo(() => {
    if (!killmails) return [];
    return killmails.filter((km: EveEyesKillmail) => {
      if (km.killTimestamp < taskCreatedAt) return false;
      if (km.status !== 'resolved') return false;
      return true;
    });
  }, [killmails, taskCreatedAt]);

  if (error) return null;

  return (
    <div>
      <h3 className="font-heading text-xs text-eve-danger tracking-wider mb-2">
        MATCHING KILLS
      </h3>
      <p className="text-[10px] text-eve-sub/60 mb-3">
        Recent kills from Eve Eyes feed that occurred after this bounty was created.
      </p>

      {isLoading && (
        <div className="flex justify-center py-4">
          <LoadingSpinner size="sm" />
        </div>
      )}

      {!isLoading && matches.length === 0 && (
        <p className="text-xs text-eve-sub py-2">
          No matching kills found yet. Complete the kill in-game and check back.
        </p>
      )}

      {matches.length > 0 && (
        <div className="space-y-1.5 max-h-48 overflow-y-auto">
          {matches.slice(0, 10).map((km: EveEyesKillmail, i: number) => (
            <div
              key={`${km.killmailItemId}-${i}`}
              className="flex items-center gap-3 px-3 py-2 bg-eve-bg-2/50 rounded border border-eve-panel-border/30"
            >
              <div className="flex-1 min-w-0 text-xs">
                <span className="text-eve-text font-heading">
                  {km.killer.label}
                </span>
                <span className="text-eve-sub mx-1.5">&rarr;</span>
                <span className="text-eve-danger font-heading">
                  {km.victim.label}
                </span>
              </div>
              <span className="text-[10px] text-eve-sub/60 whitespace-nowrap">
                {timeAgo(km.killTimestamp)}
              </span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
