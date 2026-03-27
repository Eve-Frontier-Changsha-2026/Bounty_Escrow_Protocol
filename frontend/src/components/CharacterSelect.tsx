import { useState, useRef, useEffect } from 'react';
import type { EveCharacter } from '../lib/eve-api';

interface CharacterSelectProps {
  label: string;
  characters: EveCharacter[];
  loading: boolean;
  value: string | null;         // selected Character Object ID
  onChange: (id: string | null) => void;
  hint?: string;
}

export function CharacterSelect({ label, characters, loading, value, onChange, hint }: CharacterSelectProps) {
  const [search, setSearch] = useState('');
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  const selected = characters.find((c) => c.id === value);

  const filtered = search.trim()
    ? characters.filter((c) => c.name.toLowerCase().includes(search.toLowerCase()))
    : characters;

  // Close dropdown on outside click
  useEffect(() => {
    function handler(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, []);

  const inputId = label.toLowerCase().replace(/\s+/g, '-');

  return (
    <div className="flex flex-col gap-1.5" ref={ref}>
      <label htmlFor={inputId} className="text-xs font-heading text-eve-sub tracking-[0.08em] uppercase">
        {label}
      </label>

      {selected ? (
        <div className="flex items-center gap-2 bg-eve-bg-2 border border-eve-panel-border rounded-lg px-3 py-2.5">
          <span className="text-sm text-eve-text flex-1">
            {selected.name}{' '}
            <span className="text-eve-sub text-xs">({selected.tribeName})</span>
          </span>
          <button
            type="button"
            onClick={() => { onChange(null); setSearch(''); }}
            className="text-eve-sub hover:text-eve-danger text-xs transition-colors"
          >
            CLEAR
          </button>
        </div>
      ) : (
        <div className="relative">
          <input
            id={inputId}
            type="text"
            value={search}
            onChange={(e) => { setSearch(e.target.value); setOpen(true); }}
            onFocus={() => setOpen(true)}
            placeholder={loading ? 'Loading characters...' : 'Search by name...'}
            disabled={loading}
            className="w-full bg-eve-bg-2 border border-eve-panel-border rounded-lg px-3 py-2.5 text-sm text-eve-text font-body placeholder:text-eve-sub/50 focus:outline-none focus:border-eve-cyan/60 focus:shadow-[0_0_12px_rgba(102,203,255,0.2)] transition-all"
          />

          {open && filtered.length > 0 && (
            <ul className="absolute z-50 w-full mt-1 max-h-48 overflow-y-auto bg-eve-bg-2 border border-eve-panel-border rounded-lg shadow-lg">
              {filtered.map((c) => (
                <li key={c.id}>
                  <button
                    type="button"
                    onClick={() => { onChange(c.id); setSearch(''); setOpen(false); }}
                    className="w-full text-left px-3 py-2 text-sm hover:bg-eve-cyan/10 transition-colors"
                  >
                    <span className="text-eve-text">{c.name}</span>{' '}
                    <span className="text-eve-sub text-xs">({c.tribeName})</span>
                  </button>
                </li>
              ))}
            </ul>
          )}

          {open && !loading && filtered.length === 0 && search.trim() && (
            <div className="absolute z-50 w-full mt-1 bg-eve-bg-2 border border-eve-panel-border rounded-lg px-3 py-2 text-xs text-eve-sub">
              No characters found
            </div>
          )}
        </div>
      )}

      {hint && <span className="text-xs text-eve-sub/70">{hint}</span>}
    </div>
  );
}
