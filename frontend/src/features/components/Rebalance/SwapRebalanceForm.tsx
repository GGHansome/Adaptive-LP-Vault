import { Alert, Button, Form, Space, Typography } from 'antd';
import { useState } from 'react';
import { ActionForm } from '../../../shared/components/ActionForm';
import { units } from '../../../shared/utils/format';
import type { RebalanceProps } from './interface';

type Suggestion = {
  binding: string;
  request: symbol;
} & (
  | { status: 'loading' }
  | { status: 'ready'; amount: string }
  | { status: 'error'; message: string }
);

export function SwapRebalanceForm({
  p,
  disabled,
  revision,
}: {
  p: RebalanceProps;
  disabled: boolean;
  revision: number;
}) {
  const [form] = Form.useForm();
  const [minOut, setMinOut] = useState('0');
  const [state, setState] = useState<Suggestion>();
  const { preview, deployment: m } = p;
  const inputIsToken1 = preview?.direction === 2;
  const inputSymbol = inputIsToken1 ? m.symbol1 : m.symbol0;
  const outputSymbol = inputIsToken1 ? m.symbol0 : m.symbol1;
  const binding = JSON.stringify([
    p.suggestionScope,
    m.instanceId,
    m.vault,
    revision,
    disabled,
    preview?.plan.planHash,
    preview?.direction,
    preview?.at,
    minOut,
  ]);
  const suggestion = state?.binding === binding ? state : undefined;
  // Clear as soon as the binding changes; returning to the previous inputs must not revive old results.
  if (state && !suggestion) setState(undefined);
  const loading = suggestion?.status === 'loading';

  async function calculate() {
    if (disabled || loading) return;
    const request = Symbol();
    const base = { binding, request };
    setState({ ...base, status: 'loading' });
    try {
      units(minOut, inputIsToken1 ? m.decimals0 : m.decimals1);
      const amount = await p.onSuggestSwap(minOut);
      setState((current) =>
        current?.request === request ? { ...base, status: 'ready', amount } : current,
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : '请检查连接后重试';
      setState((current) =>
        current?.request === request ? { ...base, status: 'error', message } : current,
      );
    }
  }

  return (
    <ActionForm
      form={form}
      title="受控换币再平衡"
      description="仅 Keeper / Manager。建议金额基于当前链状态，不保证成交；提交时会重新模拟整笔迁移。"
      fields={[
        { name: 'amountIn', label: `换币输入（${inputSymbol}）`, type: 'number' },
        {
          name: 'minOut',
          label: `调用者最低输出（${outputSymbol}）`,
          initial: '0',
          type: 'number',
          hint: '协议最低输出仍然有效，即使此处填写 0。',
        },
      ]}
      notice={!p.allowedSwap ? '当前账户未确认持有 Keeper 或 Manager 角色' : undefined}
      submit="模拟并执行换币再平衡"
      busy={p.busy}
      disabled={disabled || loading}
      onValuesChange={(v) => setMinOut(v.minOut)}
      onSubmit={(v) => p.onSwap({ amountIn: v.amountIn, minOut: v.minOut })}
    >
      <Space wrap>
        <Button
          htmlType="button"
          disabled={disabled || loading}
          loading={loading}
          onClick={calculate}
        >
          计算建议金额
        </Button>
        {suggestion?.status === 'ready' && (
          <Button
            htmlType="button"
            onClick={() => form.setFieldValue('amountIn', suggestion.amount)}
          >
            填入建议金额
          </Button>
        )}
      </Space>
      {suggestion?.status === 'ready' && (
        <Typography.Text aria-live="polite">
          建议：{suggestion.amount} {inputSymbol}（已通过只读模拟）
        </Typography.Text>
      )}
      {suggestion?.status === 'error' && (
        <Alert type="warning" showIcon title="无法计算建议金额" description={suggestion.message} />
      )}
    </ActionForm>
  );
}
