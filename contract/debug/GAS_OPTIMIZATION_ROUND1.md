# 第一轮 Gas 优化记录

> 历史记录：本轮之后已按可审计性优先的取舍收缩余额复用，并简化手续费同步和仓位校验。以下测量保留为第一轮历史基线，当前行为、Gas 与尺寸以 [简化记录](GAS_SIMPLIFICATION.md) 为准。

- 日期：2026-10-12
- 状态：本地基准已验证；主网发布仍受合约尺寸阻塞
- 优化前源码版本：`d3f48d95f6f87290ee07c6d6493aa9d690c69d6c`
- 数值证据：[round1-results.json](gas/round1-results.json)
- 范围：`AdaptiveLPVault` 内部读取与估值复用、`UniswapV3Adapter` 存款数学复用

## 1. 环境与测量边界

本轮不修改公共 ABI、事件、存储字段、角色、暂停、滑点、截止时间、会计规则或编译配置。环境为 Foundry `1.5.1-stable`、Solidity `0.8.24`、optimizer runs `200`、`via_ir = true`，有效 EVM 目标为 `cancun`。

目标部署网络为 Ethereum Mainnet，本次测试是本地模拟，未使用固定主网区块。Vault 基准使用真实 Vault、VaultControl、Executor 和 V2 Adapter；V2 Pair、V3 Adapter、Oracle 与 Router 使用本地测试实现。V3 数学基准使用真实 V3 Adapter，Pool、Position Manager 和 ERC20 使用测试实现。

测量使用 `--isolate` 和 `vm.snapshotGasLastCall`，只记录被测入口调用，排除 fixture 初始化、预览获取计划、断言和记录日志。它不是整个测试的 Gas，也不等同于含交易固有成本的主网交易费用；不能将模拟 V3 快照成本外推为真实 V3 快照成本。最终测试夹具已在独立的优化前源码工作副本中重新测量，基线与最初结果一致；优化后重复运行结果一致。

## 2. 修改与取舍

### 快照与地址

- 内部预览返回已校验的当前仓位，供状态变化比较和旧区间事件字段复用。
- `_synchronizeFees` 复用同步后的仓位，用于手续费清零检查、资产快照和 `FeesSynchronized`；需要完整会计的调用方直接使用返回快照。
- 零手续费赎回保留原有手续费清零检查，不额外要求完整资产快照。有手续费事件时复用其中已测量的闲置余额。
- 部署后的主动仓位只读取一次，用于会计、结构检查和 V3 区间事件；非主动 V3 仓位仍独立查询。
- 只检查 V3 时不查询未使用的 V2 地址。已校验的地址在局部调用链传递，建仓前仍调用 `requireEnterEnabled`。

这些修改共同调整快照数据流，作为一个耦合候选测量，不将收益单独归因给某个辅助函数。

### 估值、余额和数学

- 总资产净值供闲置比例、shares 定价、迁移损失检查和事件按阶段复用。闲置资产仍独立报价，不用总净值减已部署净值替代，保持逐项向下取整。
- 退出、Swap、存款返回已经实际测量并核验的余额，供后续部署或会计使用。用户双币入金后仍重读两种余额。
- Adapter/Executor 各自的实际到账、余额恢复核验与 Vault 核验保持独立。
- V3 存款预览只计算一次上下界平方根价格，供流动性和代币数量计算共用。本金向下取整、输入向上取整、uint128 上限检查不变。

## 3. 前后对比

全部 17 个场景的原始结果见 JSON。代表性结果：

- V3 无手续费存款：277,211 → 261,924，减少 15,287（5.51%）。
- V3 有手续费存款：318,380 → 289,993，减少 28,387（8.92%）。
- V2 存款：300,096 → 284,744，减少 15,352（5.12%）。
- V3 间再平衡：484,135 → 452,576，减少 31,559（6.52%）。
- V3 有手续费再平衡：503,450 → 464,408，减少 39,042（7.75%）。
- token0 → token1 Swap 再平衡：469,580 → 440,698，减少 28,882（6.15%）。
- token1 → token0 Swap 再平衡：469,175 → 440,308，减少 28,867（6.15%）。
- V3 有手续费紧急退出：224,932 → 205,806，减少 19,126（8.50%）。
- 真实 V3 Adapter 存款预览：12,159 → 9,778，减少 2,381（19.58%）。
- 真实 V3 Adapter 建仓：244,667 → 242,762，减少 1,905（0.78%）。

最终测量场景均没有调用 Gas 回退；IDLE 赎回仅减少 64 Gas，不作为主要收益。中间版本曾增加其成本，最终把 IDLE 与非 IDLE 的手续费快照路径分开。

分阶段单独测量过估值、余额和 V3 数学改动。例如快照/地址阶段的有手续费 V3 存款为 293,562，加入估值复用后为 291,371，加入余额复用后为 289,993。真实 V3 预览只受数学改动影响，从 12,159 降至 9,778。内联和编译布局会联动，不将阶段差值解释为独立 opcode 成本。

## 4. 尺寸与发布阻塞

- Vault runtime：27,157 → 26,860 字节，减少 297。
- Vault initcode：34,864 → 34,532 字节，减少 332。
- V3 Adapter runtime：12,681 → 12,668 字节，减少 13。
- V3 Adapter initcode：15,063 → 15,050 字节，减少 13。

尺寸采用 `forge build src --sizes` 配合独立 out/cache 路径重新编译生产源码，避免把全测试构建缓存当成发布产物；Gas 数据采用完整测试构建。

生产编译通过，尺寸门禁仍失败：Vault runtime 超过 EIP-170 的 24,576 字节限制 **2,284 字节**。这是已有阻塞，本轮减少但未解决。测试通过不表示主网可部署。initcode 数值未包含具体 ABI 编码的构造参数；发布仍按 `docs/DEPLOYMENT.md` 验证最终输入。本轮没有调整 optimizer、提高尺寸限制或迁移更多逻辑到外部库。

## 5. 安全前提与验证

1. 缓存仅在当前调用内存中使用，不跨交易持久化。
2. 从测量到复用之间没有改变对应资产状态的调用；只读外部查询为 STATICCALL。
3. 收取手续费、退出、换币、存款和赎回转账后继续读取受影响的新状态。
4. Bootstrap 后 Adapter 身份冻结，但 `enabled` 可变，建仓前仍复查；Bootstrap 不跨入金回调复用初始化前身份。
5. 初始化后的 shares 总量非零，锁定 shares 保留。赎回中只有生成过手续费事件的完整快照含非零 `totalShares`，据此复用余额。
6. 主动仓位传入结构检查前，已校验注册地址/venue 和本金加手续费一致性。

新增回归覆盖仓位/余额读取次数、未使用 V2 地址、手续费和区间事件、闲置捐赠、无变化失败、身份/金额/区间错误、未收完手续费，以及退出回调禁用目标后仍拒绝建仓并原子回滚。已有捐赠、舍入、Swap 损失和守恒测试继续通过。

V3 数学与冻结的优化前计算路径做差分测试，覆盖随机价格/区间/输入、边界、零输入和极端有效区间；另扩大至 4,096 次 fuzz。未增加生产 assembly 或新 opcode 依赖。

新增结构体仅用于内存，存储字段及类型/顺序不变；`forge inspect` 确认生命周期字段仍位于 slot 5，`_lastExecutedPlan` 从 slot 6 开始。

## 6. 复现与测试结果

```bash
forge test --fuzz-seed 0x1234 --gas-snapshot-emit false
forge test --isolate --fuzz-seed 0x1234 --gas-snapshot-emit false
forge test --match-contract UniswapV3AdapterTest --fuzz-seed 0x1234 --fuzz-runs 4096 --gas-snapshot-emit false
forge test --match-test testGas_ --isolate --gas-snapshot-emit false -vv
forge build src --sizes --out /tmp/adaptive-lp-round1-prod-after --cache-path /tmp/adaptive-lp-round1-prod-after-cache
forge inspect AdaptiveLPVault storage-layout --json
```

完整测试 216 项通过，包括基准 suite 继承复用的捐赠测试；默认 fuzz 每项 256 次。完整隔离执行也通过，新增余额读取次数测试另在隔离 suite 中通过。生产尺寸门禁仍失败。现有 fork/invariant 文件未提供本轮真实主网或完整状态机验证证据，不将本地测试称为主网验收或安全审计。

复测优化前结果时，在独立副本中使用 baseline commit 的生产源码和本轮相同 `AdaptiveLPVaultGas.t.sol`、`UniswapV3Adapter.t.sol`、fixture、依赖和配置；不要在含未提交工作的目录直接回退源码。比较场景日志值，不比较 `forge snapshot` 中含多个调用和测试逻辑的总 Gas。

## 7. 后续边界

Vault 尺寸仍需缩减；固定主网区块上的真实 V2/V3 与两方向 Swap 基准待执行。`syncFees` 跨合约返回快照、取消独立到账核验和预览跨 Swap 复用不属于本轮。
