// frontend/src/components/ui/SearchSelect.test.tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { SearchSelect } from './SearchSelect';

interface Item {
  id: string;
  name: string;
}

const items: Item[] = [
  { id: '1', name: 'Alpha' },
  { id: '2', name: 'Beta' },
  { id: '3', name: 'Gamma' },
];

const defaultProps = {
  items,
  filterFn: (item: Item, q: string) =>
    item.name.toLowerCase().includes(q.toLowerCase()),
  renderItem: (item: Item) => <span>{item.name}</span>,
  renderSelected: (item: Item) => <span>{item.name}</span>,
  onSelect: vi.fn(),
  placeholder: 'Search...',
  label: 'Test Select',
};

describe('SearchSelect', () => {
  it('renders label and placeholder', () => {
    render(<SearchSelect {...defaultProps} />);
    expect(screen.getByLabelText('Test Select')).toBeInTheDocument();
    expect(screen.getByPlaceholderText('Search...')).toBeInTheDocument();
  });

  it('shows filtered items on input', () => {
    render(<SearchSelect {...defaultProps} />);
    fireEvent.focus(screen.getByPlaceholderText('Search...'));
    fireEvent.change(screen.getByPlaceholderText('Search...'), {
      target: { value: 'alp' },
    });
    expect(screen.getByText('Alpha')).toBeInTheDocument();
    expect(screen.queryByText('Beta')).not.toBeInTheDocument();
  });

  it('calls onSelect when item clicked', () => {
    const onSelect = vi.fn();
    render(<SearchSelect {...defaultProps} onSelect={onSelect} />);
    fireEvent.focus(screen.getByPlaceholderText('Search...'));
    fireEvent.change(screen.getByPlaceholderText('Search...'), {
      target: { value: 'beta' },
    });
    fireEvent.click(screen.getByText('Beta'));
    expect(onSelect).toHaveBeenCalledWith(items[1]);
  });

  it('shows selected state with clear button', () => {
    const onSelect = vi.fn();
    render(
      <SearchSelect {...defaultProps} onSelect={onSelect} selected={items[0]} />,
    );
    expect(screen.getByText('Alpha')).toBeInTheDocument();
    expect(screen.getByText('CLEAR')).toBeInTheDocument();
  });

  it('clears selection on CLEAR click', () => {
    const onSelect = vi.fn();
    render(
      <SearchSelect {...defaultProps} onSelect={onSelect} selected={items[0]} />,
    );
    fireEvent.click(screen.getByText('CLEAR'));
    expect(onSelect).toHaveBeenCalledWith(null);
  });

  it('shows all items when input focused with empty query', () => {
    render(<SearchSelect {...defaultProps} />);
    fireEvent.focus(screen.getByPlaceholderText('Search...'));
    expect(screen.getByText('Alpha')).toBeInTheDocument();
    expect(screen.getByText('Beta')).toBeInTheDocument();
    expect(screen.getByText('Gamma')).toBeInTheDocument();
  });

  it('shows "No results" for unmatched query', () => {
    render(<SearchSelect {...defaultProps} />);
    fireEvent.focus(screen.getByPlaceholderText('Search...'));
    fireEvent.change(screen.getByPlaceholderText('Search...'), {
      target: { value: 'zzz' },
    });
    expect(screen.getByText('No results found')).toBeInTheDocument();
  });

  it('shows loading state', () => {
    render(<SearchSelect {...defaultProps} loading={true} items={[]} />);
    expect(screen.getByPlaceholderText('Loading...')).toBeInTheDocument();
  });

  it('displays hint text', () => {
    render(<SearchSelect {...defaultProps} hint="Pick one" />);
    expect(screen.getByText('Pick one')).toBeInTheDocument();
  });

  it('navigates items with arrow keys and selects with Enter', () => {
    const onSelect = vi.fn();
    render(<SearchSelect {...defaultProps} onSelect={onSelect} />);
    const input = screen.getByPlaceholderText('Search...');
    fireEvent.focus(input);

    // Arrow down to first item
    fireEvent.keyDown(input, { key: 'ArrowDown' });
    expect(screen.getByRole('option', { selected: true })).toHaveTextContent('Alpha');

    // Arrow down to second
    fireEvent.keyDown(input, { key: 'ArrowDown' });
    const opts = screen.getAllByRole('option');
    expect(opts[1]).toHaveAttribute('aria-selected', 'true');

    // Enter to select
    fireEvent.keyDown(input, { key: 'Enter' });
    expect(onSelect).toHaveBeenCalledWith(items[1]);
  });

  it('closes dropdown on Escape', () => {
    render(<SearchSelect {...defaultProps} />);
    const input = screen.getByPlaceholderText('Search...');
    fireEvent.focus(input);
    expect(screen.getByRole('listbox')).toBeInTheDocument();

    fireEvent.keyDown(input, { key: 'Escape' });
    expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
  });

  it('wraps around on ArrowDown past last item', () => {
    render(<SearchSelect {...defaultProps} />);
    const input = screen.getByPlaceholderText('Search...');
    fireEvent.focus(input);

    // Go to last item (Gamma at index 2)
    fireEvent.keyDown(input, { key: 'ArrowDown' }); // 0
    fireEvent.keyDown(input, { key: 'ArrowDown' }); // 1
    fireEvent.keyDown(input, { key: 'ArrowDown' }); // 2
    // Wrap to first
    fireEvent.keyDown(input, { key: 'ArrowDown' }); // 0
    const opts = screen.getAllByRole('option');
    expect(opts[0]).toHaveAttribute('aria-selected', 'true');
  });

  it('has proper ARIA attributes', () => {
    render(<SearchSelect {...defaultProps} />);
    const input = screen.getByPlaceholderText('Search...');
    expect(input).toHaveAttribute('role', 'combobox');
    expect(input).toHaveAttribute('aria-expanded', 'false');

    fireEvent.focus(input);
    expect(input).toHaveAttribute('aria-expanded', 'true');
    expect(input).toHaveAttribute('aria-controls');
  });
});
