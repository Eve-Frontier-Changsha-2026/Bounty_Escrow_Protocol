import { useQuery, useQueries } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { V3_PACKAGE_ID } from '../config/contracts';
import type { ParsedProofSubmission } from '../lib/types';

export async function fetchProofSubmission(
  bountyId: string,
  hunterAddress: string,
): Promise<ParsedProofSubmission | null> {
  const result = await jsonRpcClient.getDynamicFieldObject({
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
  return useQuery({
    queryKey: ['proofSubmission', bountyId, hunterAddress],
    queryFn: () => fetchProofSubmission(bountyId!, hunterAddress!),
    enabled: !!bountyId && !!hunterAddress,
  });
}

/** Query proof status for multiple hunters at once */
export function useHunterProofs(
  bountyId: string | undefined,
  hunters: string[],
) {
  return useQueries({
    queries: hunters.map(hunter => ({
      queryKey: ['proofSubmission', bountyId, hunter],
      queryFn: () => fetchProofSubmission(bountyId!, hunter),
      enabled: !!bountyId,
    })),
  });
}
