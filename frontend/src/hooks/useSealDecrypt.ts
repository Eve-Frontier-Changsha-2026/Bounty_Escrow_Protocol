import { useState, useCallback, useRef, useEffect } from 'react';
import { useDAppKit, useCurrentClient, useCurrentAccount } from '@mysten/dapp-kit-react';
import type { SessionKey } from '@mysten/seal';
import type { SealCompatibleClient } from '@mysten/seal';
import { createSessionKey, sealDecrypt } from '../lib/seal';

/**
 * Hook to decrypt encrypted bounty details via Seal protocol.
 *
 * Flow:
 * 1. Create SessionKey (ephemeral keypair)
 * 2. Wallet signs personal message → attach signature to session key
 * 3. Build seal_approve_bounty TX (dry-run only)
 * 4. SealClient.decrypt → plaintext
 *
 * Requires: viewer receipt already minted (use buildMintViewerReceipt PTB first).
 */
export function useSealDecrypt() {
  const dAppKit = useDAppKit();
  const client = useCurrentClient() as SealCompatibleClient;
  const account = useCurrentAccount();

  const [isPending, setIsPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Cache session key per address to avoid re-signing within TTL
  const sessionKeyRef = useRef<{ address: string; key: SessionKey } | null>(null);

  // Invalidate cached session key when wallet address changes
  useEffect(() => {
    const cached = sessionKeyRef.current;
    if (cached && cached.address !== account?.address) {
      sessionKeyRef.current = null;
    }
  }, [account?.address]);

  const decrypt = useCallback(
    async (args: {
      encryptedData: Uint8Array;
      bountyId: string;
      viewerReceiptId: string;
    }): Promise<Uint8Array> => {
      if (!account) throw new Error('Wallet not connected');
      const address = account.address;

      setIsPending(true);
      setError(null);

      try {
        // 1. Get or create session key
        let sessionKey: SessionKey;
        const cached = sessionKeyRef.current;

        if (cached && cached.address === address && !cached.key.isExpired()) {
          sessionKey = cached.key;
        } else {
          sessionKey = await createSessionKey({ address, suiClient: client });

          // 2. Sign the session key's personal message via wallet
          const personalMessage = sessionKey.getPersonalMessage();
          const { signature } = await dAppKit.signPersonalMessage({
            message: personalMessage,
          });
          await sessionKey.setPersonalMessageSignature(signature);

          sessionKeyRef.current = { address, key: sessionKey };
        }

        // 3-4. Decrypt (builds seal_approve TX internally)
        const plaintext = await sealDecrypt({
          suiClient: client,
          encryptedData: args.encryptedData,
          sessionKey,
          bountyId: args.bountyId,
          viewerReceiptId: args.viewerReceiptId,
        });

        return plaintext;
      } catch (e) {
        const msg = e instanceof Error ? e.message : 'Decryption failed';
        setError(msg);
        throw e;
      } finally {
        setIsPending(false);
      }
    },
    [dAppKit, client, account],
  );

  return {
    decrypt,
    isPending,
    error,
    clearError: () => setError(null),
  };
}
