import { createDAppKit } from '@mysten/dapp-kit-react';
import { SuiJsonRpcClient } from '@mysten/sui/jsonRpc';
import { NETWORKS, DEFAULT_NETWORK, RPC_URLS, type Network } from './config/network';

export const dAppKit = createDAppKit({
  networks: [...NETWORKS],
  defaultNetwork: DEFAULT_NETWORK,
  createClient: (network) =>
    new SuiJsonRpcClient({
      url: RPC_URLS[network as Network],
      network: network as Network,
    }),
});

declare module '@mysten/dapp-kit-react' {
  interface Register {
    dAppKit: typeof dAppKit;
  }
}
