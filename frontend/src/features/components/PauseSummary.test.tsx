import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, expect, it } from 'vitest';
import { PauseSummary } from './PauseSummary';
afterEach(cleanup);
it('三个暂停状态各自展示，赎回不被列为暂停入口', () => {
  render(
    <PauseSummary
      pause={{ depositPaused: true, plainRebalancePaused: false, swapRebalancePaused: true }}
    />,
  );
  expect(screen.getByText('存款：已暂停')).toBeInTheDocument();
  expect(screen.getByText('普通再平衡：开放')).toBeInTheDocument();
  expect(screen.queryByText(/赎回.*暂停/)).not.toBeInTheDocument();
});
