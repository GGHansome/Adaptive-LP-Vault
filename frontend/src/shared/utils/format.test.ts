import { describe, expect, it } from 'vitest';
import { units, amount, minimum, addressInput, previewExpired } from './format';
describe('资产最小单位与保护', () => {
  it('使用 bigint 保留大额与不同 decimals 精度', () => {
    expect(units('123456789012345678.123456', 6)).toBe(123456789012345678123456n);
    expect(units('0.000000000000000001', 18)).toBe(1n);
    expect(amount(1234567n, 6)).toBe('1.23456');
  });
  it('拒绝负数、指数、超精度以及地址错误', () => {
    for (const x of ['-1', '1e8', 'NaN', '0.0000001']) expect(() => units(x, 6)).toThrow();
    expect(() => addressInput('0x' + '0'.repeat(40))).toThrow();
  });
  it('最低输出向下舍入并约束滑点', () => {
    expect(minimum(101n, 50)).toBe(100n);
    expect(() => minimum(10n, 10001)).toThrow();
  });
  it('超时或链时间回退的预览均失效', () => {
    expect(previewExpired(100, 160)).toBe(false);
    expect(previewExpired(100, 161)).toBe(true);
    expect(previewExpired(100, 99)).toBe(true);
  });
});
