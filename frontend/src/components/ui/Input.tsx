import type { InputHTMLAttributes } from 'react';

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label: string;
  hint?: string;
}

export function Input({ label, hint, className = '', id, ...props }: InputProps) {
  const inputId = id ?? label.toLowerCase().replace(/\s+/g, '-');
  return (
    <div className="flex flex-col gap-1.5">
      <label htmlFor={inputId} className="text-xs font-heading text-eve-sub tracking-[0.08em] uppercase">
        {label}
      </label>
      <input
        id={inputId}
        className={`bg-eve-bg-2 border border-eve-panel-border rounded-lg px-3 py-2.5 text-sm text-eve-text font-body placeholder:text-eve-sub/50 focus:outline-none focus:border-eve-cyan/60 focus:shadow-[0_0_12px_rgba(102,203,255,0.2)] transition-all ${className}`}
        {...props}
      />
      {hint && <span className="text-xs text-eve-sub/70">{hint}</span>}
    </div>
  );
}
