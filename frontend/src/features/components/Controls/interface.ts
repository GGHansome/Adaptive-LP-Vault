import type { AdapterConfig, Pause } from '../../types';
export type ControlsProps = {
  pause: Pause;
  configs: AdapterConfig[];
  initialized: boolean;
  manager: boolean;
  ready: boolean;
  busy: boolean;
  onSetPause: (pause: Pause) => Promise<void>;
  onSetAdapter: (venue: number, enabled: boolean) => Promise<void>;
  onEmergencyExit: () => Promise<void>;
};
