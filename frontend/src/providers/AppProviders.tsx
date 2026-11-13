import { ConfigProvider, App as AntApp } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { WagmiProvider } from 'wagmi';
import { BrowserRouter } from 'react-router-dom';
import type { ReactNode } from 'react';
import { wagmiConfig } from '../config/web3';

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: true } },
});
export function AppProviders({ children }: { children: ReactNode }) {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <ConfigProvider
          locale={zhCN}
          button={{ autoInsertSpace: false }}
          theme={{
            token: {
              colorPrimary: '#167d6d',
              colorInfo: '#167d6d',
              borderRadius: 10,
              fontFamily: 'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
              colorText: '#162a34',
              colorBgLayout: '#f4f6f8',
            },
            components: {
              Button: { controlHeight: 40 },
              Card: { headerFontSize: 16 },
              Layout: { siderBg: '#0c1923', headerBg: '#ffffff' },
              Menu: {
                darkItemBg: '#0c1923',
                darkItemSelectedBg: '#1c3a3b',
                darkItemSelectedColor: '#c9f2e5',
                darkItemHoverBg: '#152833',
                darkItemColor: '#90a2ae',
              },
            },
          }}
        >
          <AntApp>
            <BrowserRouter>{children}</BrowserRouter>
          </AntApp>
        </ConfigProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
