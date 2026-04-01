import { useQuery, useQueries } from '@tanstack/react-query';
import { useCurrentClient } from '@mysten/dapp-kit-react';
import type { SuiJsonRpcClient } from '@mysten/sui/jsonRpc';
import { V3_PACKAGE_ID } from '../config/contracts';
import type { ParsedProofSubmission } from '../lib/types';

type ReadClient = Pick<SuiJsonRpcClient, 'getDynamicFieldObject'>;

export async function fetchProofSubmission(
  client: ReadClient,
  bountyId: string,
  hunterAddress: string,
): Promise<ParsedProofSubmission | null> {
  const result = await client.getDynamicFieldObject({
    parentId: bountyId,
    name: {
      type: `${V3_PACKAGE_ID}::bounty::ProofKey`,
      value: { hunter: hunterAddress },
    },
  });

  if (!result.data?.content || result.data.content.dataType !== 'moveObject') {
    return null;
  }

  const fields = result.data.content.fields as Record<string, unknown>;
  // SUI JSON-RPC wraps nested struct values: value may be { fields: { ... } } or flat
  const rawValue = fields.value as Record<string, unknown> | undefined;
  if (!rawValue) return null;
  const value = (rawValue.fields as Record<string, unknown> | undefined) ?? rawValue;

  return {
    proofUrl: String(value.proof_url ?? ''),
    proofDescription: String(value.proof_description ?? ''),
    submittedAt: Number(value.submitted_at ?? 0),
    status: Number(value.status ?? 0),
    rejectionReason: String(value.rejection_reason ?? ''),
    disputeReason: String(value.dispute_reason ?? ''),
    resolvedBy: String(value.resolved_by ?? ''),
    resolvedAt: Number(value.resolved_at ?? 0),
    hasResubmitted: Boolean(value.has_resubmitted ?? false),
  } satisfies ParsedProofSubmission;
}

export function useProofSubmission(
  bountyId: string | undefined,
  hunterAddress: string | undefined,
) {
  const client = useCurrentClient();
  return useQuery({
    queryKey: ['proofSubmission', bountyId, hunterAddress],
    queryFn: () => fetchProofSubmission(client, bountyId!, hunterAddress!),
    enabled: !!bountyId && !!hunterAddress,
    staleTime: 30_000,
  });
}

/** Query proof status for multiple hunters at once */
export function useHunterProofs(
  bountyId: string | undefined,
  hunters: string[],
) {
  const client = useCurrentClient();
  return useQueries({
    queries: hunters.map(hunter => ({
      queryKey: ['proofSubmission', bountyId, hunter],
      queryFn: () => fetchProofSubmission(client, bountyId!, hunter),
      enabled: !!bountyId,
      staleTime: 30_000,
    })),
  });
}
