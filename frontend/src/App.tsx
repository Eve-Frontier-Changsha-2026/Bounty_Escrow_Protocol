import { lazy, Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import { Layout } from './components/layout/Layout';

const DashboardPage = lazy(() => import('./pages/DashboardPage'));
const CreateBountyPage = lazy(() => import('./pages/CreateBountyPage'));
const BountyDetailPage = lazy(() => import('./pages/BountyDetailPage'));
const MyActivityPage = lazy(() => import('./pages/MyActivityPage'));

function PageSpinner() {
  return (
    <div className="flex items-center justify-center py-24">
      <span className="w-6 h-6 border-2 border-eve-cyan border-t-transparent rounded-full animate-spin" />
    </div>
  );
}

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Suspense fallback={<PageSpinner />}><DashboardPage /></Suspense>} />
        <Route path="create" element={<Suspense fallback={<PageSpinner />}><CreateBountyPage /></Suspense>} />
        <Route path="bounty/:bountyId" element={<Suspense fallback={<PageSpinner />}><BountyDetailPage /></Suspense>} />
        <Route path="activity" element={<Suspense fallback={<PageSpinner />}><MyActivityPage /></Suspense>} />
      </Route>
    </Routes>
  );
}
