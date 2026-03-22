import { SuiJsonRpcClient } from '@mysten/sui/jsonRpc';

export const jsonRpcClient = new SuiJsonRpcClient({
  url: 'https://fullnode.testnet.sui.io:443',
  network: 'testnet',
});
