import { lazy, Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import { Layout } from './components/layout/Layout';

const DashboardPage = lazy(() => import('./pages/DashboardPage'));
const CreateBountyPage = lazy(() => import('./pages/CreateBountyPage'));
const BountyDetailPage = lazy(() => import('./pages/BountyDetailPage'));
const MyActivityPage = lazy(() => import('./pages/MyActivityPage'));

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Suspense><DashboardPage /></Suspense>} />
        <Route path="create" element={<Suspense><CreateBountyPage /></Suspense>} />
        <Route path="bounty/:bountyId" element={<Suspense><BountyDetailPage /></Suspense>} />
        <Route path="activity" element={<Suspense><MyActivityPage /></Suspense>} />
      </Route>
    </Routes>
  );
}
