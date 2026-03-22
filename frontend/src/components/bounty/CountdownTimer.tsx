import { useState, useEffect } from 'react';
import { formatCountdown } from '../../lib/format';

interface CountdownTimerProps {
  targetMs: number;
  label?: string;
}

export function CountdownTimer({ targetMs, label }: CountdownTimerProps) {
  const [display, setDisplay] = useState(() => formatCountdown(targetMs));

  useEffect(() => {
    const interval = setInterval(() => {
      setDisplay(formatCountdown(targetMs));
    }, 1000);
    return () => clearInterval(interval);
  }, [targetMs]);

  const diff = targetMs - Date.now();
  const urgencyColor =
    diff <= 0 ? 'text-eve-danger' :
    diff < 600_000 ? 'text-eve-danger' :
    diff < 3_600_000 ? 'text-status-claimed' :
    'text-eve-cyan';

  return (
    <div className="flex items-center gap-1.5">
      {label && <span className="text-xs text-eve-sub">{label}</span>}
      <span className={`text-sm font-heading ${urgencyColor}`}>{display}</span>
    </div>
  );
}
