import { NavLink } from 'react-router-dom';
import { ConnectButton } from '@mysten/dapp-kit-react/ui';

const links = [
  { to: '/', label: 'BOUNTY BOARD' },
  { to: '/create', label: 'CREATE' },
  { to: '/activity', label: 'ACTIVITY' },
] as const;

export function Navbar() {
  return (
    <header className="fixed top-0 left-0 right-0 z-20 h-[70px] flex items-center justify-between px-6 backdrop-blur-[10px] bg-[rgba(3,9,18,0.62)] border-b border-[rgba(130,167,237,0.28)]">
      <NavLink to="/" className="flex items-center gap-3">
        <div className="w-9 h-9 rounded-full border border-eve-gold/70 bg-[rgba(8,21,43,0.55)] flex items-center justify-center">
          <span className="font-heading text-eve-gold text-xs font-bold">BEP</span>
        </div>
        <span className="font-heading text-eve-text text-sm tracking-[0.1em] hidden sm:block">
          BOUNTY ESCROW
        </span>
      </NavLink>

      <nav className="flex items-center gap-1">
        {links.map(({ to, label }) => (
          <NavLink
            key={to}
            to={to}
            end={to === '/'}
            className={({ isActive }) =>
              `font-heading text-xs tracking-[0.08em] px-4 py-2 rounded-full transition-all duration-200 ${
                isActive
                  ? 'text-eve-gold border border-eve-gold/60 shadow-[0_0_16px_rgba(240,206,131,0.4)]'
                  : 'text-[#cfe3ff] hover:text-eve-text'
              }`
            }
          >
            {label}
          </NavLink>
        ))}
      </nav>

      <ConnectButton />
    </header>
  );
}
