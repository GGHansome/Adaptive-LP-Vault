import { Card, Form, Input, InputNumber, Button, Alert, Flex, Modal, Typography } from 'antd';
import { useState, useId, useRef } from 'react';
import type { ActionFormProps } from './interface';
export function ActionForm(p: ActionFormProps) {
  const id = useId();
  const [error, setError] = useState<string>();
  const [submitting, setSubmitting] = useState(false);
  const submittingRef = useRef(false);
  const [modal, contextHolder] = Modal.useModal();
  async function finish(values: Record<string, unknown>) {
    if (submittingRef.current || p.disabled || p.busy) return;
    submittingRef.current = true;
    setSubmitting(true);
    setError(undefined);
    try {
      if (
        p.confirm &&
        !(await modal.confirm({
          title: '确认高风险操作',
          content: p.confirm,
          okText: '确认执行',
          cancelText: '取消',
          okButtonProps: { danger: true },
        }))
      )
        return;
      await p.onSubmit(
        Object.fromEntries(Object.entries(values).map(([k, v]) => [k, String(v ?? '')])),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : '操作失败');
    } finally {
      submittingRef.current = false;
      setSubmitting(false);
    }
  }
  return (
    <Card title={p.title}>
      {contextHolder}
      <Flex vertical gap="middle">
        {p.description && (
          <Typography.Paragraph type="secondary">{p.description}</Typography.Paragraph>
        )}
        {p.notice && <Alert type="warning" showIcon title={p.notice} />}
        <Form
          name={id}
          layout="vertical"
          onFinish={finish}
          onValuesChange={(_, values: Record<string, unknown>) =>
            p.onValuesChange?.(
              Object.fromEntries(Object.entries(values).map(([k, v]) => [k, String(v ?? '')])),
            )
          }
          initialValues={Object.fromEntries(p.fields.map((f) => [f.name, f.initial ?? '']))}
        >
          {p.fields.map((f) => (
            <Form.Item
              key={f.name}
              name={f.name}
              label={f.label}
              extra={f.hint}
              rules={[{ required: true, message: `请填写${f.label}` }]}
            >
              {f.type === 'number' ? (
                <InputNumber
                  className="full-width"
                  stringMode
                  controls={false}
                  min="0"
                  placeholder={f.placeholder}
                />
              ) : (
                <Input autoComplete="off" placeholder={f.placeholder} />
              )}
            </Form.Item>
          ))}
          <Flex vertical gap="middle">
            {p.children}
            {error && (
              <Alert
                type="error"
                showIcon
                title="操作未完成"
                description={error.length > 700 ? error.slice(0, 700) + '…' : error}
              />
            )}
            <Button
              htmlType="submit"
              type="primary"
              danger={p.danger}
              disabled={p.disabled}
              loading={p.busy || submitting}
              block
            >
              {p.submit}
            </Button>
          </Flex>
        </Form>
      </Flex>
    </Card>
  );
}
