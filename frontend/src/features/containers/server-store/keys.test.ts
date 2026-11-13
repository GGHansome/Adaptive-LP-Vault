import { QueryClient } from '@tanstack/react-query';
import { expect, it } from 'vitest';
import { accountKey, affectedKeys, vaultKey } from './keys';
import { address, otherAddress, deployment } from '../../test/fixtures';
it('查询键隔离链、部署与账户，公共键不包含账户或轮询区块', () => {
  expect(vaultKey(deployment, 'snapshot')).not.toEqual(
    vaultKey({ ...deployment, instanceId: 'reset' }, 'snapshot'),
  );
  expect(vaultKey(deployment, 'snapshot')).not.toEqual(
    vaultKey({ ...deployment, chainId: 1 }, 'snapshot'),
  );
  expect(accountKey(deployment, 'account', address)).not.toEqual(
    accountKey(deployment, 'account', otherAddress),
  );
  expect(vaultKey(deployment, 'members')).toEqual(vaultKey(deployment, 'members'));
});
it('代币授权仅刷新所属账户和事件，不失效公共快照或其他账户', async () => {
  const client = new QueryClient();
  const mine = accountKey(deployment, 'account', address),
    other = accountKey(deployment, 'account', otherAddress),
    snapshot = vaultKey(deployment, 'snapshot');
  for (const key of [mine, other, snapshot]) client.setQueryData(key, { value: true });
  await Promise.all(
    affectedKeys(deployment, address, 'approval').map((queryKey) =>
      client.invalidateQueries({ queryKey }),
    ),
  );
  expect(client.getQueryState(mine)?.isInvalidated).toBe(true);
  expect(client.getQueryState(other)?.isInvalidated).toBe(false);
  expect(client.getQueryState(snapshot)?.isInvalidated).toBe(false);
  client.clear();
});
it('角色变化刷新权限和成员，不刷新余额', () => {
  const keys = affectedKeys(deployment, address, 'roles');
  expect(keys).toContainEqual(vaultKey(deployment, 'access'));
  expect(keys).toContainEqual(vaultKey(deployment, 'members'));
  expect(keys).not.toContainEqual(vaultKey(deployment, 'account'));
});
