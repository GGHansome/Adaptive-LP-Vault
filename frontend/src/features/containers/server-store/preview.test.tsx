import { act, cleanup, renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { afterEach, expect, it, vi } from 'vitest';
import { usePreviewQuery } from './preview';
let client: QueryClient;
function wrapper({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
}
afterEach(() => {
  cleanup();
  client.clear();
});
it('显式预览之前不请求，身份或表单变化后忽略旧请求迟到的结果', async () => {
  client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  let finishOld!: (value: string) => void;
  const request = vi
    .fn()
    .mockImplementationOnce(
      () =>
        new Promise<string>((resolve) => {
          finishOld = resolve;
        }),
    )
    .mockResolvedValue('新账户结果');
  const { result, rerender } = renderHook(
    ({ identity, amount }) => usePreviewQuery(['preview', identity, amount], true, request),
    {
      wrapper,
      initialProps: { identity: 'old', amount: '1' },
    },
  );
  expect(request).not.toHaveBeenCalled();
  act(() => result.current.request());
  await waitFor(() => expect(request).toHaveBeenCalledTimes(1));
  rerender({ identity: 'new', amount: '2' });
  expect(result.current.data).toBeUndefined();
  await act(async () => finishOld('旧账户结果'));
  expect(result.current.data).toBeUndefined();
  act(() => result.current.request());
  await waitFor(() => expect(result.current.data).toBe('新账户结果'));
  act(() => result.current.clear());
  expect(result.current.data).toBeUndefined();
});
it('依赖未就绪时不能启动预览', () => {
  client = new QueryClient();
  const request = vi.fn();
  const { result } = renderHook(() => usePreviewQuery(['preview'], false, request), { wrapper });
  act(() => result.current.request());
  expect(request).not.toHaveBeenCalled();
});
