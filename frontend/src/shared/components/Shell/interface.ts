import type { ReactNode } from 'react';
export type NavItem = { path: string; label: string };
export type ShellProps = {
  children: ReactNode;
  items: NavItem[];
  path: string;
  onNavigate: (path: string) => void;
  address?: string;
  connected: boolean;
  wrongChain: boolean;
  connecting: boolean;
  onConnect: () => void;
  onDisconnect: () => void;
  onSwitch: () => void;
  status: ReactNode;
  transaction: ReactNode;
};
