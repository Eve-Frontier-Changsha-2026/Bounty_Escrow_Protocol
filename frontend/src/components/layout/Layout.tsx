import { Outlet } from 'react-router-dom';
import { Navbar } from './Navbar';
import { Starfield } from './Starfield';

export function Layout() {
  return (
    <div className="min-h-screen flex flex-col">
      <Starfield />
      <div className="grid-overlay" />
      <div className="vignette" />
      <Navbar />
      <main className="relative z-10 flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 pt-[90px] pb-10">
        <Outlet />
      </main>
      <footer className="relative z-10 text-center py-4 text-eve-sub text-xs font-body border-t border-eve-panel-border/30">
        Bounty Escrow Protocol — EVE Frontier
      </footer>
    </div>
  );
}
