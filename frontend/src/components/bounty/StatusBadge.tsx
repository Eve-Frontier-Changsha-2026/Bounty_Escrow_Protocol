import { STATUS_LABEL, STATUS_COLOR, STATUS_BG } from '../../lib/constants';

export function StatusBadge({ status }: { status: number }) {
  const label = STATUS_LABEL[status] ?? 'UNKNOWN';
  const color = STATUS_COLOR[status] ?? 'text-eve-sub';
  const bg = STATUS_BG[status] ?? 'bg-eve-panel border-eve-panel-border';

  return (
    <span
      className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-heading tracking-wider border ${color} ${bg}`}
    >
      {label}
    </span>
  );
}
