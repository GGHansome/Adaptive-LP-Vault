import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, expect, it, vi } from 'vitest';
import { ActionForm } from './ActionForm';
import { PermissionNotice } from '../PermissionNotice';
afterEach(cleanup);
it('展示表单只经回调提交，不访问外部数据', async () => {
  const submit = vi.fn().mockResolvedValue(undefined);
  render(
    <ActionForm
      title="测试"
      fields={[{ name: 'amount', label: '数量', initial: '1' }]}
      submit="提交"
      onSubmit={submit}
    />,
  );
  fireEvent.click(screen.getByRole('button', { name: /提\s*交/ }));
  await waitFor(() => expect(submit).toHaveBeenCalledWith({ amount: '1' }));
});
it('失败后恢复提交并显示错误，忙碌或禁用时不能提交', async () => {
  const submit = vi.fn().mockRejectedValueOnce(new Error('用户拒签')).mockResolvedValue(undefined);
  const { rerender } = render(
    <ActionForm title="测试" fields={[]} submit="提交" onSubmit={submit} />,
  );
  fireEvent.click(screen.getByRole('button', { name: /提\s*交/ }));
  expect(await screen.findByText('用户拒签')).toBeInTheDocument();
  fireEvent.click(screen.getByRole('button', { name: /提\s*交/ }));
  await waitFor(() => expect(submit).toHaveBeenCalledTimes(2));
  rerender(<ActionForm title="测试" fields={[]} submit="提交" onSubmit={submit} disabled />);
  expect(screen.getByRole('button', { name: /提\s*交/ })).toBeDisabled();
});
it('未授权时明确说明角色边界', () => {
  render(<PermissionNotice />);
  expect(screen.getByText(/当前账户没有此页面/)).toBeInTheDocument();
});
