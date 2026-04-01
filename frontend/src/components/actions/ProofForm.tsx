import { useState } from 'react';
import { Button } from '../ui/Button';
import { Input } from '../ui/Input';
import { Textarea } from '../ui/Textarea';
import { LIMITS } from '../../lib/constants';

interface ProofFormProps {
  mode: 'submit' | 'resubmit';
  isPending: boolean;
  onSubmit: (proofUrl: string, proofDescription: string) => Promise<void>;
}

export function ProofForm({ mode, isPending, onSubmit }: ProofFormProps) {
  const [proofUrl, setProofUrl] = useState('');
  const [proofDescription, setProofDescription] = useState('');
  const [open, setOpen] = useState(false);

  const proofUrlValid = proofUrl.trim().length > 0 && proofUrl.trim().length <= LIMITS.MAX_PROOF_URL;
  const proofDescValid = proofDescription.length <= LIMITS.MAX_PROOF_DESCRIPTION;
  const isResubmit = mode === 'resubmit';

  async function handleSubmit() {
    await onSubmit(proofUrl.trim(), proofDescription.trim());
    setProofUrl('');
    setProofDescription('');
    setOpen(false);
  }

  if (!open) {
    return (
      <Button variant="primary" onClick={() => setOpen(true)} className="w-full">
        {isResubmit ? 'RESUBMIT PROOF' : 'SUBMIT PROOF'}
      </Button>
    );
  }

  return (
    <div className="space-y-2 p-3 bg-eve-bg-2 rounded-lg border border-eve-panel-border/50">
      <Input
        label={isResubmit ? 'New Proof URL' : 'Proof URL'}
        value={proofUrl}
        onChange={(e) => setProofUrl(e.target.value)}
        placeholder="https://..."
        hint={`${proofUrl.length}/${LIMITS.MAX_PROOF_URL}`}
      />
      <Textarea
        label={isResubmit ? 'New Description (optional)' : 'Description (optional)'}
        value={proofDescription}
        onChange={(e) => setProofDescription(e.target.value)}
        placeholder={isResubmit ? 'Describe updated deliverable...' : 'Describe your deliverable...'}
        hint={`${proofDescription.length}/${LIMITS.MAX_PROOF_DESCRIPTION}`}
      />
      <div className="flex gap-2">
        <Button
          variant="primary"
          disabled={isPending || !proofUrlValid || !proofDescValid}
          onClick={handleSubmit}
          className="flex-1"
        >
          {isPending
            ? (isResubmit ? 'RESUBMITTING...' : 'SUBMITTING...')
            : (isResubmit ? 'RESUBMIT' : 'SUBMIT')}
        </Button>
        <Button variant="secondary" onClick={() => setOpen(false)}>CANCEL</Button>
      </div>
    </div>
  );
}
