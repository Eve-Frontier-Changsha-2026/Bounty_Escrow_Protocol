import { useQuery } from '@tanstack/react-query';
import { jsonRpcClient } from '../lib/rpc';
import { ORIGINAL_PACKAGE_ID } from '../config/contracts';
import type { ParsedProofSubmission } from '../lib/types';

export function useProofSubmission(
  bountyId: string | undefined,
  hunterAddress: string | undefined,
) {
  return useQuery({
    queryKey: ['proofSubmission', bountyId, hunterAddress],
    queryFn: async () => {
      const result = await jsonRpcClient.getDynamicFieldObject({
        parentId: bountyId!,
        name: {
          type: `${ORIGINAL_PACKAGE_ID}::bounty::ProofKey`,
          value: { hunter: hunterAddress! },
        },
      });

      if (!result.data?.content || result.data.content.dataType !== 'moveObject') {
        return null;
      }

      const fields = result.data.content.fields as Record<string, unknown>;
      const value = fields.value as Record<string, unknown> | undefined;
      if (!value) return null;

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
    },
    enabled: !!bountyId && !!hunterAddress,
  });
}
