import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CharacterSelect } from './CharacterSelect';
import type { EveCharacter } from '../lib/eve-api';

const mockCharacters: EveCharacter[] = [
  { id: '0x1', name: 'Alice', address: '0xa', tribeId: 1, tribeName: 'Alpha', tribeTicker: 'AL', createdAt: 1000 },
  { id: '0x2', name: 'Bob', address: '0xb', tribeId: 2, tribeName: 'Beta', tribeTicker: 'BE', createdAt: 2000 },
  { id: '0x3', name: 'AliceClone', address: '0xc', tribeId: 1, tribeName: 'Alpha', tribeTicker: 'AL', createdAt: 3000 },
];

describe('CharacterSelect', () => {
  it('renders label and search input', () => {
    render(
      <CharacterSelect
        label="Target Victim"
        characters={mockCharacters}
        loading={false}
        value={null}
        onChange={vi.fn()}
      />
    );
    expect(screen.getByLabelText(/target victim/i)).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Search by name...')).toBeInTheDocument();
  });

  it('shows loading placeholder when loading', () => {
    render(
      <CharacterSelect
        label="Target"
        characters={[]}
        loading={true}
        value={null}
        onChange={vi.fn()}
      />
    );
    expect(screen.getByPlaceholderText('Loading...')).toBeInTheDocument();
  });

  it('filters characters by search text', async () => {
    const user = userEvent.setup();
    render(
      <CharacterSelect
        label="Target"
        characters={mockCharacters}
        loading={false}
        value={null}
        onChange={vi.fn()}
      />
    );

    const input = screen.getByPlaceholderText('Search by name...');
    await user.click(input);
    await user.type(input, 'alice');

    // Should show Alice and AliceClone, not Bob
    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('AliceClone')).toBeInTheDocument();
    expect(screen.queryByText('Bob')).not.toBeInTheDocument();
  });

  it('calls onChange when a character is selected', async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(
      <CharacterSelect
        label="Target"
        characters={mockCharacters}
        loading={false}
        value={null}
        onChange={onChange}
      />
    );

    const input = screen.getByPlaceholderText('Search by name...');
    await user.click(input);
    await user.type(input, 'Bob');

    const bobButton = screen.getByText('Bob');
    await user.click(bobButton);
    expect(onChange).toHaveBeenCalledWith('0x2');
  });

  it('shows selected character with CLEAR button', () => {
    render(
      <CharacterSelect
        label="Target"
        characters={mockCharacters}
        loading={false}
        value="0x1"
        onChange={vi.fn()}
      />
    );

    expect(screen.getByText('Alice')).toBeInTheDocument();
    expect(screen.getByText('(Alpha)')).toBeInTheDocument();
    expect(screen.getByText('CLEAR')).toBeInTheDocument();
  });

  it('clears selection when CLEAR is clicked', async () => {
    const user = userEvent.setup();
    const onChange = vi.fn();
    render(
      <CharacterSelect
        label="Target"
        characters={mockCharacters}
        loading={false}
        value="0x1"
        onChange={onChange}
      />
    );

    await user.click(screen.getByText('CLEAR'));
    expect(onChange).toHaveBeenCalledWith(null);
  });

  it('shows hint text when provided', () => {
    render(
      <CharacterSelect
        label="Target"
        characters={[]}
        loading={false}
        value={null}
        onChange={vi.fn()}
        hint="Optional — pick one"
      />
    );
    expect(screen.getByText('Optional — pick one')).toBeInTheDocument();
  });

  it('shows "No results found" for empty search results', async () => {
    const user = userEvent.setup();
    render(
      <CharacterSelect
        label="Target"
        characters={mockCharacters}
        loading={false}
        value={null}
        onChange={vi.fn()}
      />
    );

    const input = screen.getByPlaceholderText('Search by name...');
    await user.click(input);
    await user.type(input, 'zzzznonexist');

    expect(screen.getByText('No results found')).toBeInTheDocument();
  });

  // --- Monkey Tests ---

  it('handles characters with special chars in names', async () => {
    const user = userEvent.setup();
    const specials: EveCharacter[] = [
      { id: '0xs1', name: '<script>alert(1)</script>', address: '0x', tribeId: 0, tribeName: 'XSS', tribeTicker: 'X', createdAt: 0 },
      { id: '0xs2', name: 'name"with"quotes', address: '0x', tribeId: 0, tribeName: 'Test', tribeTicker: 'T', createdAt: 0 },
    ];
    render(
      <CharacterSelect label="Target" characters={specials} loading={false} value={null} onChange={vi.fn()} />
    );
    const input = screen.getByPlaceholderText('Search by name...');
    await user.click(input);
    await user.type(input, '<script>');
    // React escapes HTML — should render as text, not execute
    expect(screen.getByText('<script>alert(1)</script>')).toBeInTheDocument();
  });

  it('handles empty characters array without crashing', async () => {
    const user = userEvent.setup();
    render(
      <CharacterSelect label="Target" characters={[]} loading={false} value={null} onChange={vi.fn()} />
    );
    const input = screen.getByPlaceholderText('Search by name...');
    await user.click(input);
    await user.type(input, 'test');
    expect(screen.getByText('No results found')).toBeInTheDocument();
  });

  it('handles value that does not match any character', () => {
    // value is set but no matching character — should show search input
    render(
      <CharacterSelect label="Target" characters={mockCharacters} loading={false} value="0xnonexist" onChange={vi.fn()} />
    );
    expect(screen.getByPlaceholderText('Search by name...')).toBeInTheDocument();
  });

  it('case-insensitive search', async () => {
    const user = userEvent.setup();
    render(
      <CharacterSelect label="Target" characters={mockCharacters} loading={false} value={null} onChange={vi.fn()} />
    );
    const input = screen.getByPlaceholderText('Search by name...');
    await user.click(input);
    await user.type(input, 'BOB');
    expect(screen.getByText('Bob')).toBeInTheDocument();
  });
});
