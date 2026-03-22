import { useState, useCallback } from 'react';
import { useDAppKit, useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react';
import { useQueryClient } from '@tanstack/react-query';
import type { Transaction } from '@mysten/sui/transactions';

export function useTransactionExecutor(invalidateKeys: string[][]) {
  const dAppKit = useDAppKit();
  const client = useCurrentClient();
  const queryClient = useQueryClient();
  const account = useCurrentAccount();
  const [isPending, setIsPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const execute = useCallback(
    async (tx: Transaction) => {
      if (!account) throw new Error('Wallet not connected');
      setIsPending(true);
      setError(null);
      try {
        const result = await dAppKit.signAndExecuteTransaction({ transaction: tx });
        if (result.FailedTransaction) {
          throw new Error(
            result.FailedTransaction.status.error?.message ?? 'Transaction failed',
          );
        }
        await client.waitForTransaction({ digest: result.Transaction.digest });
        for (const key of invalidateKeys) {
          await queryClient.invalidateQueries({ queryKey: key });
        }
        return result.Transaction.digest;
      } catch (e) {
        const msg = e instanceof Error ? e.message : 'Unknown error';
        setError(msg);
        throw e;
      } finally {
        setIsPending(false);
      }
    },
    [dAppKit, client, queryClient, account, invalidateKeys],
  );

  return { execute, isPending, error, clearError: () => setError(null) };
}
