import { Alert, Button, Card, Flex, Table, Tag, Typography } from 'antd';
import { ActionForm } from '../../../shared/components/ActionForm';
import { KeyValues } from '../../../shared/components/KeyValues';
import { PageTitle } from '../../../shared/components/PageTitle';
import { TwoColumns } from '../../../shared/components/TwoColumns';
import { short } from '../../../shared/utils/format';
import type { RoleMember } from '../../types';
import type { AdminProps } from './interface';

export function Admin(p: AdminProps) {
  const d = p.governance;
  const pending = !/^0x0{40}$/i.test(d.pendingAdmin.address);
  const delay = Math.max(0, d.pendingAdmin.acceptAt - d.blockTime);
  const disabled = !p.ready || p.busy;
  return (
    <Flex vertical gap="large">
      <PageTitle
        eyebrow="ACCESS & GOVERNANCE"
        title="角色与权限"
        description="根管理员只管理权限归属，不自动获得初始化、风控或资产操作权限。"
      />
      <TwoColumns
        left={
          <KeyValues
            title="管理员交接状态"
            items={[
              { label: '当前转移延迟', value: `${d.adminDelay} 秒` },
              {
                label: '候任管理员',
                value: pending ? (
                  <code className="hash-text">{d.pendingAdmin.address}</code>
                ) : (
                  '无（若已预约注销则目标为零地址）'
                ),
              },
              {
                label: '预约生效时间',
                value: d.pendingAdmin.acceptAt
                  ? new Date(d.pendingAdmin.acceptAt * 1000).toLocaleString('zh-CN')
                  : '无预约',
              },
              {
                label: '等待状态',
                value: d.pendingAdmin.acceptAt
                  ? delay
                    ? `剩余 ${delay} 秒`
                    : '可接受 / 执行'
                  : '—',
              },
              {
                label: '待生效延迟变更',
                value: d.pendingDelay.effectiveAt
                  ? `${d.pendingDelay.delay} 秒，生效时间 ${new Date(d.pendingDelay.effectiveAt * 1000).toLocaleString('zh-CN')}`
                  : '无',
              },
            ]}
          />
        }
        right={
          <Flex vertical gap="large">
            {p.access.pendingAdmin && (
              <ActionForm
                title="接受管理员交接"
                description="只有候任地址能够在链上等待期结束后完成交接。"
                fields={[]}
                submit="接受根管理员角色"
                disabled={disabled || delay > 0}
                busy={p.busy}
                confirm="接受后将成为唯一根管理员，原管理员失去根角色。"
                onSubmit={p.onAccept}
              />
            )}
            <Alert
              type="info"
              showIcon
              title="根角色不能通过普通 grantRole / revokeRole 转移。交接必须使用专用的两阶段流程。"
            />
          </Flex>
        }
      />
      {p.access.admin && (
        <>
          <TwoColumns
            left={
              <ActionForm
                title="授予业务角色"
                fields={[
                  { name: 'account', label: '目标钱包地址', type: 'address' },
                  { name: 'role', label: '角色：manager / guardian / keeper', initial: 'keeper' },
                ]}
                submit="授予角色"
                disabled={disabled}
                busy={p.busy}
                onSubmit={(v) => p.onGrant(v.account, v.role)}
              />
            }
            right={
              <ActionForm
                title="撤销业务角色"
                fields={[
                  { name: 'account', label: '目标钱包地址', type: 'address' },
                  { name: 'role', label: '角色：manager / guardian / keeper', initial: 'keeper' },
                ]}
                submit="撤销角色"
                disabled={disabled}
                busy={p.busy}
                danger
                confirm="撤销立即生效，请确认不会移除必要的运行权限。"
                onSubmit={(v) => p.onRevoke(v.account, v.role)}
              />
            }
          />
          <Card title="链上角色成员" extra={<Button onClick={p.onRefreshMembers}>刷新</Button>}>
            <Flex vertical gap="middle">
              {p.membersError ? (
                <Alert
                  type="error"
                  title="角色事件读取失败，成员列表尚未确认"
                  description={p.membersError}
                />
              ) : (
                <Table
                  loading={p.membersLoading}
                  rowKey="address"
                  pagination={{ pageSize: 8 }}
                  dataSource={p.members}
                  scroll={{ x: 480 }}
                  columns={[
                    {
                      title: '账户',
                      dataIndex: 'address',
                      render: (address: string) => <code title={address}>{short(address)}</code>,
                    },
                    {
                      title: '当前有效角色',
                      dataIndex: 'roles',
                      render: (roles: RoleMember['roles']) =>
                        roles.some((r) => r.has) ? (
                          roles.filter((r) => r.has).map((r) => <Tag key={r.role}>{r.role}</Tag>)
                        ) : (
                          <span>已无角色</span>
                        ),
                    },
                  ]}
                />
              )}
              <Typography.Text type="secondary">
                通过部署以来的 RoleGranted 事件发现地址，再使用 hasRole 核实当前权限。
              </Typography.Text>
            </Flex>
          </Card>
          <TwoColumns
            left={
              <Flex vertical gap="large">
                <ActionForm
                  title="预约根管理员交接"
                  fields={[{ name: 'newAdmin', label: '新管理员地址', type: 'address' }]}
                  submit="开始两阶段交接"
                  disabled={disabled}
                  busy={p.busy}
                  confirm="候任地址需要等待链上延迟并主动接受，才能完成交接。"
                  onSubmit={(v) => p.onBeginTransfer(v.newAdmin)}
                />
                <ActionForm
                  title="取消交接"
                  fields={[]}
                  submit="取消待处理交接"
                  disabled={disabled || !d.pendingAdmin.acceptAt}
                  busy={p.busy}
                  onSubmit={p.onCancelTransfer}
                />
              </Flex>
            }
            right={
              <Flex vertical gap="large">
                <ActionForm
                  title="预约转移延迟变更"
                  fields={[
                    {
                      name: 'seconds',
                      label: '新的延迟（整数秒）',
                      type: 'number',
                      initial: String(d.adminDelay),
                    },
                  ]}
                  submit="预约延迟变更"
                  disabled={disabled}
                  busy={p.busy}
                  onSubmit={(v) => p.onChangeDelay(v.seconds)}
                />
                <ActionForm
                  title="回滚待生效延迟变更"
                  fields={[]}
                  submit="回滚延迟变更"
                  disabled={disabled || !d.pendingDelay.effectiveAt}
                  busy={p.busy}
                  onSubmit={p.onRollbackDelay}
                />
              </Flex>
            }
          />
          <TwoColumns
            left={
              <ActionForm
                title="永久注销根管理员 · 第一步"
                description="预约向零地址转移；等待期后仍需主动放弃根角色。完成注销后将无法再授予任何业务角色。"
                fields={[]}
                submit="预约永久注销"
                disabled={disabled}
                busy={p.busy}
                danger
                confirm="此流程最终会永久移除根管理员。角色管理可能不可恢复，请仅在明确理解后继续。"
                onSubmit={p.onScheduleRenounce}
              />
            }
            right={
              <ActionForm
                title="永久注销根管理员 · 第二步"
                fields={[]}
                submit="永久放弃根管理员"
                disabled={disabled || pending || !d.pendingAdmin.acceptAt || delay > 0}
                busy={p.busy}
                danger
                confirm="此操作不可撤销。执行后将不再有根管理员，无法授予或撤销业务角色。"
                onSubmit={p.onRenounceAdmin}
              />
            }
          />
        </>
      )}
      <ActionForm
        title="放弃自己的业务角色"
        fields={[{ name: 'role', label: 'manager / guardian / keeper' }]}
        submit="放弃当前账户的该角色"
        disabled={disabled}
        busy={p.busy}
        danger
        confirm="你将立即失去该业务角色；只能由根管理员重新授予。"
        onSubmit={(v) => p.onRenounceRole(v.role)}
      />
    </Flex>
  );
}
