import { useEffect } from 'react';

interface TransactionToastProps {
  type: 'success' | 'error';
  message: string;
  digest?: string;
  onClose: () => void;
}

export function TransactionToast({ type, message, digest, onClose }: TransactionToastProps) {
  useEffect(() => {
    const timer = setTimeout(onClose, 8000);
    return () => clearTimeout(timer);
  }, [onClose]);

  const borderColor = type === 'success' ? 'border-eve-success/60' : 'border-eve-danger/60';
  const glowColor = type === 'success'
    ? 'shadow-[0_0_20px_rgba(74,222,128,0.2)]'
    : 'shadow-[0_0_20px_rgba(255,107,107,0.2)]';
  const iconColor = type === 'success' ? 'text-eve-success' : 'text-eve-danger';

  return (
    <div
      className={`fixed bottom-6 right-6 z-50 eve-panel rounded-lg p-4 max-w-sm border ${borderColor} ${glowColor} animate-[slideUp_0.3s_ease]`}
    >
      <div className="flex items-start gap-3">
        <span className={`${iconColor} text-lg`}>
          {type === 'success' ? '\u2713' : '\u2717'}
        </span>
        <div className="flex-1 min-w-0">
          <p className="text-sm text-eve-text">{message}</p>
          {digest && (
            <a
              href={`https://suiscan.xyz/testnet/tx/${digest}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-eve-cyan hover:underline mt-1 block truncate"
            >
              {digest}
            </a>
          )}
        </div>
        <button onClick={onClose} className="text-eve-sub hover:text-eve-text cursor-pointer">
          &times;
        </button>
      </div>
    </div>
  );
}
