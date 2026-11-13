import { lazy, Suspense } from 'react';
import { useConnection } from 'wagmi';
import { Routes, Route, Navigate } from 'react-router-dom';
import { deployment } from './config/web3';
import { ShellContainer } from './features/containers/ShellContainer';
const OverviewContainer = lazy(() =>
  import('./features/containers/OverviewContainer').then((m) => ({
    default: m.OverviewContainer,
  })),
);
const PortfolioContainer = lazy(() =>
  import('./features/containers/PortfolioContainer').then((m) => ({
    default: m.PortfolioContainer,
  })),
);
const RebalanceContainer = lazy(() =>
  import('./features/containers/RebalanceContainer').then((m) => ({
    default: m.RebalanceContainer,
  })),
);
const GuardianContainer = lazy(() =>
  import('./features/containers/GuardianContainer').then((m) => ({
    default: m.GuardianContainer,
  })),
);
const ManagerContainer = lazy(() =>
  import('./features/containers/ManagerContainer').then((m) => ({
    default: m.ManagerContainer,
  })),
);
const AdminContainer = lazy(() =>
  import('./features/containers/AdminContainer').then((m) => ({ default: m.AdminContainer })),
);
export function App() {
  const { address, chainId } = useConnection();
  const identity = `${address?.toLowerCase()}:${chainId}:${deployment?.instanceId}`;
  return (
    <ShellContainer>
      <Suspense fallback={<p>正在加载页面…</p>}>
        <Routes>
          <Route path="/" element={<Navigate to="/overview" replace />} />
          <Route path="/overview" element={<OverviewContainer />} />
          <Route path="/portfolio" element={<PortfolioContainer key={identity} />} />
          <Route path="/rebalance" element={<RebalanceContainer key={identity} />} />
          <Route path="/guardian" element={<GuardianContainer key={identity} />} />
          <Route path="/manager" element={<ManagerContainer key={identity} />} />
          <Route path="/admin" element={<AdminContainer key={identity} />} />
          <Route path="*" element={<Navigate to="/overview" replace />} />
        </Routes>
      </Suspense>
    </ShellContainer>
  );
}
