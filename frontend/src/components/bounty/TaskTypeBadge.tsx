import { TASK_TYPE_LABEL, TASK_TYPE_COLOR, TASK_TYPE_BG } from '../../lib/constants';

export function TaskTypeBadge({ taskType }: { taskType: number }) {
  const label = TASK_TYPE_LABEL[taskType] ?? 'UNKNOWN';
  const color = TASK_TYPE_COLOR[taskType] ?? 'text-eve-sub';
  const bg = TASK_TYPE_BG[taskType] ?? 'bg-eve-panel border-eve-panel-border';

  return (
    <span
      className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-heading tracking-wider border ${color} ${bg}`}
    >
      {label}
    </span>
  );
}
