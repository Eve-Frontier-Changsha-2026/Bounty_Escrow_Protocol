import type { ReactNode } from 'react';
import { useCurrentAccount } from '@mysten/dapp-kit-react';
import { ConnectButton } from '@mysten/dapp-kit-react/ui';
import { Panel } from './Panel';

export function WalletGuard({ children }: { children: ReactNode }) {
  const account = useCurrentAccount();

  if (!account) {
    return (
      <div className="flex items-center justify-center min-h-[60vh]">
        <Panel className="text-center max-w-md">
          <h2 className="font-heading text-xl text-eve-gold mb-3">CONNECT WALLET</h2>
          <p className="text-eve-sub text-sm mb-6">
            Connect your wallet to access this section.
          </p>
          <ConnectButton />
        </Panel>
      </div>
    );
  }

  return <>{children}</>;
}
