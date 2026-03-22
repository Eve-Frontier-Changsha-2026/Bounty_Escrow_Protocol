import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { WalletGuard } from '../components/ui/WalletGuard';
import { Panel } from '../components/ui/Panel';
import { LoadingSpinner } from '../components/ui/LoadingSpinner';
import { StatusBadge } from '../components/bounty/StatusBadge';
import { useBountyList } from '../hooks/useBountyList';
import { useOwnedTickets } from '../hooks/useOwnedTickets';
import { useOwnedVerifierCaps } from '../hooks/useOwnedVerifierCaps';
import { truncateAddress, mistToSui, formatTimestamp } from '../lib/format';

type Tab = 'created' | 'claimed' | 'verifying';

export function MyActivityPage() {
  const [activeTab, setActiveTab] = useState<Tab>('created');
  const account = useCurrentAccount();
  const { data: bounties, isLoading: bountiesLoading } = useBountyList();
  const { data: tickets, isLoading: ticketsLoading } = useOwnedTickets();
  const { data: caps, isLoading: capsLoading } = useOwnedVerifierCaps();

  const isLoading = bountiesLoading || ticketsLoading || capsLoading;

  const myCreated = bounties?.filter((b) => b.creator === account?.address) ?? [];
  const myTickets = tickets ?? [];
  const myCaps = caps ?? [];

  const tabs: { key: Tab; label: string; count: number }[] = [
    { key: 'created', label: 'CREATED', count: myCreated.length },
    { key: 'claimed', label: 'CLAIMED', count: myTickets.length },
    { key: 'verifying', label: 'VERIFYING', count: myCaps.length },
  ];

  return (
    <WalletGuard>
      <div>
        <h1 className="font-heading text-2xl sm:text-3xl text-eve-text mb-1">MY ACTIVITY</h1>
        <p className="text-eve-sub text-sm mb-8">Your bounties, claims, and verifications</p>

        {/* Tabs */}
        <div className="flex gap-1 mb-6">
          {tabs.map(({ key, label, count }) => (
            <button
              key={key}
              onClick={() => setActiveTab(key)}
              className={`px-4 py-2 rounded-full text-xs font-heading tracking-wider transition-all cursor-pointer ${
                activeTab === key
                  ? 'bg-eve-cyan/20 text-eve-cyan border border-eve-cyan/40'
                  : 'text-eve-sub hover:text-eve-text border border-transparent'
              }`}
            >
              {label} <span className="opacity-60">{count}</span>
            </button>
          ))}
        </div>

        {isLoading && (
          <div className="flex justify-center py-12">
            <LoadingSpinner />
          </div>
        )}

        {/* Created Tab */}
        {!isLoading && activeTab === 'created' && (
          <div className="space-y-3">
            {myCreated.length === 0 ? (
              <Panel className="text-center py-8">
                <p className="text-eve-sub text-sm">No bounties created yet</p>
                <Link to="/create" className="text-eve-cyan text-sm hover:underline mt-2 inline-block">
                  Create your first bounty &rarr;
                </Link>
              </Panel>
            ) : (
              myCreated.map((b) => (
                <Link key={b.id} to={`/bounty/${b.id}`} className="block">
                  <Panel className="hover:border-eve-cyan/50 transition-all">
                    <div className="flex items-center justify-between">
                      <div>
                        <h3 className="font-heading text-sm text-eve-text">{b.title}</h3>
                        <span className="text-xs text-eve-sub">
                          {mistToSui(b.rewardAmount)} SUI &middot; {b.activeClaims}/{b.maxClaims} claims
                        </span>
                      </div>
                      <StatusBadge status={b.status} />
                    </div>
                  </Panel>
                </Link>
              ))
            )}
          </div>
        )}

        {/* Claimed Tab */}
        {!isLoading && activeTab === 'claimed' && (
          <div className="space-y-3">
            {myTickets.length === 0 ? (
              <Panel className="text-center py-8">
                <p className="text-eve-sub text-sm">No active claims</p>
                <Link to="/" className="text-eve-cyan text-sm hover:underline mt-2 inline-block">
                  Browse bounties &rarr;
                </Link>
              </Panel>
            ) : (
              myTickets.map((t) => (
                <Link key={t.id} to={`/bounty/${t.bountyId}`} className="block">
                  <Panel className="hover:border-eve-cyan/50 transition-all">
                    <div className="flex items-center justify-between">
                      <div>
                        <h3 className="font-heading text-sm text-eve-text">
                          Bounty {truncateAddress(t.bountyId)}
                        </h3>
                        <span className="text-xs text-eve-sub">
                          Staked: {mistToSui(t.stakeAmount)} SUI &middot; Claimed: {formatTimestamp(t.claimedAt)}
                        </span>
                      </div>
                      <span className="text-xs text-eve-cyan font-heading">ACTIVE</span>
                    </div>
                  </Panel>
                </Link>
              ))
            )}
          </div>
        )}

        {/* Verifying Tab */}
        {!isLoading && activeTab === 'verifying' && (
          <div className="space-y-3">
            {myCaps.length === 0 ? (
              <Panel className="text-center py-8">
                <p className="text-eve-sub text-sm">Not a verifier for any bounties</p>
              </Panel>
            ) : (
              myCaps.map((c) => (
                <Link key={c.id} to={`/bounty/${c.bountyId}`} className="block">
                  <Panel className="hover:border-eve-cyan/50 transition-all">
                    <div className="flex items-center justify-between">
                      <div>
                        <h3 className="font-heading text-sm text-eve-text">
                          Bounty {truncateAddress(c.bountyId)}
                        </h3>
                        <span className="text-xs text-eve-sub">
                          Cap: {truncateAddress(c.id)}
                        </span>
                      </div>
                      <span className="text-xs text-eve-gold font-heading">VERIFIER</span>
                    </div>
                  </Panel>
                </Link>
              ))
            )}
          </div>
        )}
      </div>
    </WalletGuard>
  );
}

export default MyActivityPage;
