import type { Abi, Address, Hash } from 'viem';
import { useTransactionStore } from '../store/transactionStore';
import { describeError } from './errors';

export type ContractCall = {
  label: string;
  address: Address;
  abi: Abi;
  functionName: string;
  args?: readonly unknown[];
};
export type TransactionRuntime = {
  identity: string;
  assertIdentity: () => Promise<void>;
  simulate: (call: ContractCall) => Promise<() => Promise<Hash>>;
  receipt: (hash: Hash) => Promise<{ status: 'success' | 'reverted' }>;
  confirmed: (call: ContractCall) => Promise<void>;
};
class ConfirmationPendingError extends Error {}
// Execution resources stay outside the serializable UI store. There can be only one active transaction.
let pending:
  | { id: string; runtime: TransactionRuntime; call: ContractCall; hash: Hash; retrying: boolean }
  | undefined;
async function confirm(id: string, runtime: TransactionRuntime, call: ContractCall, hash: Hash) {
  const store = useTransactionStore.getState();
  let receipt: Awaited<ReturnType<TransactionRuntime['receipt']>>;
  try {
    receipt = await runtime.receipt(hash);
  } catch (error) {
    const message = `回执查询失败，交易可能仍在链上执行。请重新查询确认，勿重复提交：${describeError(error)}`;
    pending = { id, runtime, call, hash, retrying: false };
    store.update(id, { label: call.label, stage: 'unconfirmed', hash, error: message });
    throw new ConfirmationPendingError(message);
  }
  pending = undefined;
  if (receipt.status !== 'success') throw new Error('交易已回滚');
  await runtime.confirmed(call);
  store.update(id, { label: call.label, stage: 'confirmed', hash });
}
export async function retryTransactionConfirmation() {
  const entry = pending;
  if (!entry || entry.retrying || useTransactionStore.getState().activeId !== entry.id) return;
  entry.retrying = true;
  const store = useTransactionStore.getState();
  store.update(entry.id, { label: entry.call.label, stage: 'confirming', hash: entry.hash });
  try {
    await confirm(entry.id, entry.runtime, entry.call, entry.hash);
  } catch (error) {
    if (!(error instanceof ConfirmationPendingError))
      store.update(entry.id, {
        label: entry.call.label,
        stage: 'failed',
        hash: entry.hash,
        error: describeError(error),
      });
  } finally {
    if (pending?.id !== entry.id) store.release(entry.id);
  }
}
// All steps in a business sequence share one atomic lock, including Bootstrap's three signatures.
export async function executeTransaction<T>(
  runtime: TransactionRuntime,
  operation: (send: (call: ContractCall) => Promise<void>) => Promise<T>,
): Promise<T> {
  const store = useTransactionStore.getState();
  const id = store.acquire(runtime.identity);
  let lastCall: ContractCall | undefined;
  let hash: Hash | undefined;
  try {
    return await operation(async (call) => {
      lastCall = call;
      hash = undefined;
      store.update(id, { label: call.label, stage: 'simulating' });
      await runtime.assertIdentity();
      const write = await runtime.simulate(call);
      await runtime.assertIdentity();
      store.update(id, { label: call.label, stage: 'signing' });
      hash = await write();
      store.update(id, { label: call.label, stage: 'confirming', hash });
      await confirm(id, runtime, call, hash);
    });
  } catch (error) {
    if (!(error instanceof ConfirmationPendingError))
      store.update(id, {
        label: lastCall?.label ?? '交易准备',
        stage: 'failed',
        hash,
        error: describeError(error),
      });
    throw error;
  } finally {
    if (pending?.id !== id) store.release(id);
  }
}
