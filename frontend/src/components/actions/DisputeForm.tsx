import { useState } from 'react';
import { Button } from '../ui/Button';
import { Textarea } from '../ui/Textarea';
import { LIMITS } from '../../lib/constants';

interface DisputeFormProps {
  isPending: boolean;
  onSubmit: (reason: string) => Promise<void>;
}

export function DisputeForm({ isPending, onSubmit }: DisputeFormProps) {
  const [reason, setReason] = useState('');
  const [open, setOpen] = useState(false);

  const reasonValid = reason.trim().length > 0 && reason.trim().length <= LIMITS.MAX_REASON;

  async function handleSubmit() {
    await onSubmit(reason.trim());
    setReason('');
    setOpen(false);
  }

  if (!open) {
    return (
      <Button variant="danger" onClick={() => setOpen(true)} className="w-full">
        DISPUTE REJECTION
      </Button>
    );
  }

  return (
    <div className="space-y-2 p-3 bg-eve-bg-2 rounded-lg border border-eve-danger/30">
      <Textarea
        label="Dispute Reason"
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Explain why the rejection is unjust..."
        hint={`${reason.length}/${LIMITS.MAX_REASON}`}
      />
      <div className="flex gap-2">
        <Button
          variant="danger"
          disabled={isPending || !reasonValid}
          onClick={handleSubmit}
          className="flex-1"
        >
          {isPending ? 'FILING...' : 'FILE DISPUTE'}
        </Button>
        <Button variant="secondary" onClick={() => setOpen(false)}>CANCEL</Button>
      </div>
    </div>
  );
}
