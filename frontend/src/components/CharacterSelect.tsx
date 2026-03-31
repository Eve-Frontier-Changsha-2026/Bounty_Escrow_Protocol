import { SearchSelect } from './ui/SearchSelect';
import type { EveCharacter } from '../lib/eve-api';

interface CharacterSelectProps {
  label: string;
  characters: EveCharacter[];
  loading: boolean;
  value: string | null;         // selected Character Object ID
  onChange: (id: string | null) => void;
  hint?: string;
}

export function CharacterSelect({
  label,
  characters,
  loading,
  value,
  onChange,
  hint,
}: CharacterSelectProps) {
  const selected = characters.find((c) => c.id === value) ?? null;

  return (
    <SearchSelect<EveCharacter>
      items={characters}
      filterFn={(c, q) => c.name.toLowerCase().includes(q.toLowerCase())}
      renderItem={(c) => (
        <>
          <span className="text-eve-text">{c.name}</span>{' '}
          <span className="text-eve-sub text-xs">({c.tribeName})</span>
        </>
      )}
      renderSelected={(c) => (
        <>
          {c.name}{' '}
          <span className="text-eve-sub text-xs">({c.tribeName})</span>
        </>
      )}
      onSelect={(c) => onChange(c ? c.id : null)}
      selected={selected}
      placeholder="Search by name..."
      label={label}
      hint={hint}
      loading={loading}
    />
  );
}
