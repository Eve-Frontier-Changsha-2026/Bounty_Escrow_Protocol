import { useState } from 'react';
import { useSystemSearch } from '../../hooks/useSystemSearch';
import { SearchSelect } from './SearchSelect';
import type { SolarSystemResult } from '../../lib/eve-eyes-api';

interface SolarSystemSearchProps {
  label?: string;
  hint?: string;
  value: string;
  onChange: (solarSystemId: string) => void;
  required?: boolean;
}

export function SolarSystemSearch({
  label = 'Solar System',
  hint,
  value,
  onChange,
}: SolarSystemSearchProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const { data: results = [], isLoading } = useSystemSearch(searchQuery);

  const selectedSystem: SolarSystemResult | null = value
    ? { id: Number(value), name: `System #${value}` }
    : null;

  return (
    <SearchSelect<SolarSystemResult>
      items={results}
      filterFn={() => true}
      renderItem={(s) => (
        <>
          <span className="text-eve-text">{s.name}</span>{' '}
          <span className="text-eve-sub text-xs">({s.id})</span>
        </>
      )}
      renderSelected={(s) => (
        <>
          <span className="text-eve-text">{s.name}</span>{' '}
          <span className="text-eve-sub text-xs">({s.id})</span>
        </>
      )}
      onSelect={(s) => {
        onChange(s ? String(s.id) : '');
        setSearchQuery('');
      }}
      onQueryChange={setSearchQuery}
      selected={selectedSystem}
      placeholder="Search system name..."
      label={label}
      hint={hint}
      loading={isLoading}
    />
  );
}
