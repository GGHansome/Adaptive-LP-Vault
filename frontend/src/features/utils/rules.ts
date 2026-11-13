import type { Access } from '../types';
export function proportional(
  max0: bigint,
  max1: bigint,
  p0: bigint,
  p1: bigint,
): readonly [bigint, bigint] {
  if (p0 <= 0n || p1 <= 0n) throw new Error('当前仓位不支持双资产存款');
  return max0 * p1 <= max1 * p0 ? [max0, (max0 * p1) / p0] : [(max1 * p0) / p1, max1];
}
export function can(access: Access, page: string) {
  return page === 'admin'
    ? access.admin || access.pendingAdmin
    : page === 'manager'
      ? access.manager
      : page === 'guardian'
        ? access.manager || access.guardian
        : true;
}
export function depositReason(
  initialized: boolean,
  active: number,
  healthy: boolean,
  paused: boolean,
  enabled: boolean,
  singleSided: boolean,
  idleHealthy: boolean,
) {
  if (!initialized) return 'Vault 尚未初始化';
  if (paused) return '存款已暂停';
  if (!healthy) return '预言机不健康';
  if (active === 0) return 'IDLE 状态关闭存款';
  if (!enabled) return '当前适配器已禁用';
  if (singleSided) return '仓位为单边或本金为零';
  if (!idleHealthy) return '闲置资产比例超过限制';
  return undefined;
}
