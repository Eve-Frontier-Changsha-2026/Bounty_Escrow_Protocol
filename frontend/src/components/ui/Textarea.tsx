import type { TextareaHTMLAttributes } from 'react';

interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  label: string;
  hint?: string;
}

export function Textarea({ label, hint, className = '', id, ...props }: TextareaProps) {
  const textareaId = id ?? label.toLowerCase().replace(/\s+/g, '-');
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={textareaId} className="text-xs font-heading text-eve-sub tracking-[0.08em] uppercase">
        {label}
      </label>
      <textarea
        id={textareaId}
        className={`bg-eve-bg-2 border border-eve-panel-border rounded-lg px-3 py-2.5 text-sm text-eve-text font-body placeholder:text-eve-sub/50 focus:outline-none focus:border-eve-cyan/60 focus:shadow-[0_0_12px_rgba(102,203,255,0.2)] transition-all resize-y min-h-[80px] ${className}`}
        {...props}
      />
      {hint && <span className="text-xs text-eve-sub/70">{hint}</span>}
    </div>
  );
}
