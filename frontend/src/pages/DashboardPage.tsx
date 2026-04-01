import { useState, useMemo } from 'react';
import { useBountyList } from '../hooks/useBountyList';
import { useTaskTypes } from '../hooks/useTaskType';
import { BountyCard } from '../components/bounty/BountyCard';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { STATUS_LABEL } from '../lib/constants';
import { KillmailFeed } from '../components/bounty/KillmailFeed';
import { Panel } from '../components/ui/Panel';

const FILTER_OPTIONS = [
  { value: -1, label: 'ALL' },
  { value: 0, label: 'OPEN' },
  { value: 1, label: 'CLAIMED' },
  { value: 2, label: 'COMPLETED' },
  { value: 3, label: 'CANCELLED' },
  { value: 4, label: 'EXPIRED' },
] as const;

export function DashboardPage() {
  const { data: bounties, isLoading, error } = useBountyList();
  const bountyIds = useMemo(() => bounties?.map(b => b.id) ?? [], [bounties]);
  const taskTypeMap = useTaskTypes(bountyIds);
  const [statusFilter, setStatusFilter] = useState(-1);
  const [search, setSearch] = useState('');

  const filtered = bounties?.filter((b) => {
    if (statusFilter >= 0 && b.status !== statusFilter) return false;
    if (search) {
      const q = search.toLowerCase();
      return (
        b.title.toLowerCase().includes(q) ||
        b.creator.toLowerCase().includes(q) ||
        b.id.toLowerCase().includes(q)
      );
    }
    return true;
  });

  return (
    <div>
      <div className="flex flex-col sm:flex-row sm:items-end justify-between gap-4 mb-8">
        <div>
          <h1 className="font-heading text-2xl sm:text-3xl text-eve-text mb-1">BOUNTY BOARD</h1>
          <p className="text-eve-sub text-sm">
            {bounties ? `${bounties.length} bounties on the frontier` : 'Loading...'}
          </p>
        </div>

        <div className="flex items-center gap-3">
          <input
            type="text"
            placeholder="Search bounties..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="bg-eve-bg-2 border border-eve-panel-border rounded-full px-4 py-2 text-sm text-eve-text placeholder:text-eve-sub/50 focus:outline-none focus:border-eve-cyan/60 w-48"
          />
        </div>
      </div>

      {/* Status Filter Tabs */}
      <div className="flex gap-1 mb-6 overflow-x-auto pb-1">
        {FILTER_OPTIONS.map(({ value, label }) => (
          <button
            key={value}
            onClick={() => setStatusFilter(value)}
            className={`px-3 py-1.5 rounded-full text-xs font-heading tracking-wider transition-all cursor-pointer whitespace-nowrap ${
              statusFilter === value
                ? 'bg-eve-cyan/20 text-eve-cyan border border-eve-cyan/40'
                : 'text-eve-sub hover:text-eve-text border border-transparent'
            }`}
          >
            {label}
            {bounties && (
              <span className="ml-1.5 opacity-60">
                {value === -1
                  ? bounties.length
                  : bounties.filter((b) => b.status === value).length}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Content */}
      {isLoading && (
        <div className="flex justify-center py-20">
          <LoadingSpinner size="lg" />
        </div>
      )}

      {error && (
        <div className="eve-panel rounded-lg p-6 text-center">
          <p className="text-eve-danger text-sm">Failed to load bounties</p>
          <p className="text-eve-sub text-xs mt-1">{String(error)}</p>
        </div>
      )}

      {filtered && filtered.length === 0 && (
        <div className="eve-panel rounded-lg p-12 text-center">
          <p className="text-eve-sub text-sm">
            {search ? 'No bounties match your search' : `No ${statusFilter >= 0 ? STATUS_LABEL[statusFilter]?.toLowerCase() : ''} bounties found`}
          </p>
        </div>
      )}

      {filtered && filtered.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map((bounty) => (
            <BountyCard key={bounty.id} bounty={bounty} taskType={taskTypeMap.get(bounty.id)?.taskType} />
          ))}
        </div>
      )}

      {/* Killmail Feed */}
      <Panel className="mt-8">
        <KillmailFeed />
      </Panel>
    </div>
  );
}

export default DashboardPage;
