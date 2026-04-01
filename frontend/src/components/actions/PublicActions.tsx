import { Button } from '../ui/Button';
import { useTransactionExecutor } from '../../hooks/useTransactionExecutor';
import { buildExpire } from '../../lib/ptb/expire';
import { BountyStatus } from '../../lib/constants';
import { bpsToPercent } from '../../lib/format';
import type { ParsedBounty, Toast } from '../../lib/types';

const INVALIDATE_KEYS = [['bountyDetail'], ['bountyList']];

interface PublicActionsProps {
  bounty: ParsedBounty;
  onToast: (t: Toast) => void;
}

export function PublicActions({ bounty, onToast }: PublicActionsProps) {
  const { execute, isPending } = useTransactionExecutor(INVALIDATE_KEYS);

  const isActive = bounty.status === BountyStatus.OPEN || bounty.status === BountyStatus.CLAIMED;
  const gracePeriodEnd = bounty.deadline + bounty.gracePeriod;
  const canExpire = isActive && Date.now() > gracePeriodEnd;

  if (!canExpire) return null;

  async function handleExpire() {
    try {
      const tx = buildExpire({ bountyId: bounty.id, coinType: bounty.coinType });
      const digest = await execute(tx);
      onToast({ type: 'success', message: 'Bounty expired! Cleanup reward collected.', digest });
    } catch (err) {
      onToast({ type: 'error', message: err instanceof Error ? err.message : 'Expire failed' });
    }
  }

  return (
    <div className="space-y-3">
      <h3 className="font-heading text-xs text-eve-sub tracking-wider">PUBLIC ACTIONS</h3>
      <Button variant="secondary" disabled={isPending} onClick={handleExpire} className="w-full">
        {isPending ? 'EXPIRING...' : `EXPIRE BOUNTY (earn ${bpsToPercent(bounty.cleanupRewardBps)} cleanup reward)`}
      </Button>
    </div>
  );
}
