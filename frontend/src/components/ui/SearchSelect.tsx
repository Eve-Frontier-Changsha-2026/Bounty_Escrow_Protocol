// frontend/src/components/ui/SearchSelect.tsx
import { useState, useRef, useEffect, type ReactNode } from 'react';

interface SearchSelectProps<T> {
  items: T[];
  filterFn: (item: T, query: string) => boolean;
  renderItem: (item: T) => ReactNode;
  renderSelected: (item: T) => ReactNode;
  onSelect: (item: T | null) => void;
  selected?: T | null;
  placeholder?: string;
  label?: string;
  hint?: string;
  loading?: boolean;
  onQueryChange?: (query: string) => void;
}

export function SearchSelect<T>({
  items,
  filterFn,
  renderItem,
  renderSelected,
  onSelect,
  selected,
  placeholder = 'Search...',
  label,
  hint,
  loading = false,
  onQueryChange,
}: SearchSelectProps<T>) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const filtered = query.trim()
    ? items.filter((item) => filterFn(item, query))
    : items;

  useEffect(() => {
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const inputId = label?.toLowerCase().replace(/\s+/g, '-') ?? 'search-select';

  if (selected) {
    return (
      <div className="flex flex-col gap-1.5" ref={ref}>
        {label && (
          <label className="text-xs font-heading text-eve-sub tracking-[0.08em] uppercase">
            {label}
          </label>
        )}
        <div className="flex items-center gap-2 bg-eve-bg-2 border border-eve-panel-border rounded-lg px-3 py-2.5">
          <span className="text-sm text-eve-text flex-1">
            {renderSelected(selected)}
          </span>
          <button
            type="button"
            onClick={() => {
              onSelect(null);
              setQuery('');
            }}
            className="text-eve-sub hover:text-eve-danger text-xs transition-colors"
          >
            CLEAR
          </button>
        </div>
        {hint && <span className="text-xs text-eve-sub/70">{hint}</span>}
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-1.5" ref={ref}>
      {label && (
        <label
          htmlFor={inputId}
          className="text-xs font-heading text-eve-sub tracking-[0.08em] uppercase"
        >
          {label}
        </label>
      )}
      <div className="relative">
        <input
          id={inputId}
          type="text"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
            onQueryChange?.(e.target.value);
          }}
          onFocus={() => setOpen(true)}
          placeholder={loading ? 'Loading...' : placeholder}
          disabled={loading}
          className="w-full bg-eve-bg-2 border border-eve-panel-border rounded-lg px-3 py-2.5 text-sm text-eve-text font-body placeholder:text-eve-sub/50 focus:outline-none focus:border-eve-cyan/60 focus:shadow-[0_0_12px_rgba(102,203,255,0.2)] transition-all"
        />

        {open && filtered.length > 0 && (
          <ul className="absolute z-50 w-full mt-1 max-h-48 overflow-y-auto bg-eve-bg-2 border border-eve-panel-border rounded-lg shadow-lg">
            {filtered.map((item, i) => (
              <li key={i}>
                <button
                  type="button"
                  onClick={() => {
                    onSelect(item);
                    setQuery('');
                    setOpen(false);
                  }}
                  className="w-full text-left px-3 py-2 text-sm hover:bg-eve-cyan/10 transition-colors"
                >
                  {renderItem(item)}
                </button>
              </li>
            ))}
          </ul>
        )}

        {open && !loading && filtered.length === 0 && (
          <div className="absolute z-50 w-full mt-1 bg-eve-bg-2 border border-eve-panel-border rounded-lg px-3 py-2 text-xs text-eve-sub">
            No results found
          </div>
        )}
      </div>
      {hint && <span className="text-xs text-eve-sub/70">{hint}</span>}
    </div>
  );
}
