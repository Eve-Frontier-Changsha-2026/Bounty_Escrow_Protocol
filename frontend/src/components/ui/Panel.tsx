import type { ReactNode } from 'react';

interface PanelProps {
  children: ReactNode;
  className?: string;
}

export function Panel({ children, className = '' }: PanelProps) {
  return (
    <div className={`eve-panel rounded-lg p-4 sm:p-6 ${className}`}>
      {children}
    </div>
  );
}
