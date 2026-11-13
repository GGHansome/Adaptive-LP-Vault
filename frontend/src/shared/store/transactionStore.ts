import { create } from 'zustand';
import type { Address, Hash } from 'viem';

export type TransactionStage =
  | 'simulating'
  | 'signing'
  | 'confirming'
  | 'unconfirmed'
  | 'confirmed'
  | 'failed';
export type Transaction = {
  id: string;
  identity: string;
  label: string;
  stage: TransactionStage;
  hash?: Hash;
  error?: string;
};
type TransactionState = {
  busy: boolean;
  activeId?: string;
  transaction?: Transaction;
  acquire: (identity: string) => string;
  update: (id: string, transaction: Omit<Transaction, 'id' | 'identity'>) => void;
  release: (id: string) => void;
};
export const transactionIdentity = (chainId: number, instance: string, address: Address) =>
  `${chainId}:${instance}:${address.toLowerCase()}`;
export const useTransactionStore = create<TransactionState>((set, get) => ({
  busy: false,
  acquire(identity) {
    if (get().busy) throw new Error('已有交易正在执行，请等待确认');
    const id = crypto.randomUUID();
    set({
      busy: true,
      activeId: id,
      transaction: { id, identity, label: '交易准备', stage: 'simulating' },
    });
    return id;
  },
  update(id, transaction) {
    if (get().activeId === id)
      set((state) => ({
        transaction: { ...transaction, id, identity: state.transaction!.identity },
      }));
  },
  release(id) {
    if (get().activeId === id) set({ busy: false, activeId: undefined });
  },
}));
export const transactionStageLabels: Record<TransactionStage, string> = {
  simulating: '正在模拟交易',
  signing: '等待钱包签名',
  confirming: '等待链上确认',
  unconfirmed: '确认状态未知',
  confirmed: '交易已确认',
  failed: '交易失败',
};
