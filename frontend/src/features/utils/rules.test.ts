import { describe, expect, it } from 'vitest';
import { proportional, can, depositReason } from './rules';
import type { Access } from '../types';
const access: Access = {
  admin: false,
  manager: false,
  guardian: false,
  keeper: false,
  pendingAdmin: false,
};
describe('权限与运行状态', () => {
  it('严格按活跃本金比例而非总资产比例估算', () => {
    expect(proportional(100n, 100n, 2n, 3n)).toEqual([66n, 100n]);
    expect(() => proportional(1n, 2n, 0n, 3n)).toThrow();
  });
  it('根管理员不隐含业务角色', () => {
    expect(can({ ...access, admin: true }, 'manager')).toBe(false);
    expect(can({ ...access, admin: true }, 'guardian')).toBe(false);
  });
  it('多角色权限取并集，候任者可接受交接', () => {
    expect(can({ ...access, manager: true, guardian: true }, 'guardian')).toBe(true);
    expect(can({ ...access, pendingAdmin: true }, 'admin')).toBe(true);
  });
  it('IDLE、单边、暂停和预言机异常阻止存款', () => {
    expect(depositReason(true, 0, true, false, true, false, true)).toContain('IDLE');
    expect(depositReason(true, 2, true, false, true, true, true)).toContain('本金');
    expect(depositReason(true, 2, false, false, true, false, true)).toContain('预言机');
    expect(depositReason(true, 2, true, true, true, false, true)).toContain('暂停');
    expect(depositReason(true, 2, true, false, true, false, true)).toBeUndefined();
  });
});
