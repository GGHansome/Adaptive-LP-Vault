export function units(input: string, decimals: number): bigint {
  if (!/^\d+(\.\d*)?$/.test(input) || (input.split('.')[1]?.length ?? 0) > decimals)
    throw new Error(`请输入非负数字，最多 ${decimals} 位小数`);
  const [whole, part = ''] = input.split('.');
  return BigInt(whole) * 10n ** BigInt(decimals) + BigInt(part.padEnd(decimals, '0') || '0');
}
export function positive(input: string, decimals: number) {
  const value = units(input, decimals);
  if (!value) throw new Error('金额必须大于零');
  return value;
}
export function amount(value: bigint | undefined, decimals: number, digits = 5): string {
  if (value === undefined) return '—';
  const sign = value < 0n ? '-' : '';
  const n = value < 0n ? -value : value;
  const unit = 10n ** BigInt(decimals);
  const tail = (n % unit).toString().padStart(decimals, '0').slice(0, digits).replace(/0+$/, '');
  return `${sign}${(n / unit).toLocaleString('en-US')}${tail ? '.' + tail : ''}`;
}
export function inputAmount(value: bigint, decimals: number) {
  const unit = 10n ** BigInt(decimals);
  return `${value / unit}.${(value % unit).toString().padStart(decimals, '0')}`;
}
export function previewExpired(createdAt: number, now: number, ttl = 60) {
  return now < createdAt || now - createdAt > ttl;
}
export function short(value?: string) {
  return value ? `${value.slice(0, 6)}…${value.slice(-4)}` : '未连接';
}
export function minimum(value: bigint, bps: number) {
  if (!Number.isInteger(bps) || bps < 0 || bps > 1000) throw new Error('滑点须为 0–1000 基点');
  return (value * BigInt(10000 - bps)) / 10000n;
}
export function addressInput(value: string): `0x${string}` {
  if (!/^0x[0-9a-fA-F]{40}$/.test(value) || /^0x0{40}$/i.test(value))
    throw new Error('请输入有效的非零以太坊地址');
  return value as `0x${string}`;
}
