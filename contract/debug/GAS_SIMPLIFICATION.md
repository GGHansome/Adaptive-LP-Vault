# Gas 优化后的简化记录

- 日期：2026-10-12
- 状态：简化完成，行为回归通过；部分调用 Gas 和运行时代码尺寸增加，主网发布仍阻塞
- 前一版：[第一轮历史记录](GAS_OPTIMIZATION_ROUND1.md)
- 原始测量：[simplification-results.json](gas/simplification-results.json)

## 1. 目标和边界

本次按用户确认的可读性、可审计性优先取舍，收缩第一轮为少量余额查询收益引入的深层参数传递。保留仓位快照、估值和 V3 数学复用，不修改公共接口、事件签名、存储字段、权限、会计舍入、非重入、暂停、截止时间或滑点规则。

这是复杂度简化，不是一次所有指标都下降的 Gas 优化。基线为本次修改前的第一轮工作区实现，并在修改前重新测量；没有把原始 Git HEAD 当作第一轮实现。历史数值不覆盖。

## 2. 当前数据流

### 余额与资产快照

- 删除 `TokenBalances`、`_vaultBalances`，以及 `_assetAndPositionSnapshot` 的余额参数重载。
- 退出、Swap、Adapter 存款在自身内部读取操作前后余额，不接受外部余额基线，不向后续步骤返回余额缓存。
- 会计入口读取当前余额。`_assetAndPositionSnapshot()` 只有一个版本，获取并验证仓位后，交给 `_assetSnapshotFromPosition()` 组装资产。
- `_assetSnapshotFromPosition()` 只复用同阶段已验证仓位，余额和 shares 总量由函数自己读取。调用方的验证紧邻使用处，不沿长调用链传递余额。

### 手续费同步

- `_synchronizeFees(adapter)` 始终返回收取后的 `PositionSnapshot`，删除 `includeAssets` 参数和条件填充的资产返回值。
- 手续费清零检查仍无条件执行；有手续费时，验证身份/金额后用同一仓位生成 `FeesSynchronized`。
- 存款、迁移准备、紧急退出在使用返回仓位会计前显式校验，再组装资产快照。
- 赎回不缓存手续费事件读取的余额，也不再用 `totalShares != 0` 判定缓存有效性。零手续费赎回仍保留原来的收取后手续费清零检查，操作后完整仓位校验照常执行。

### 校验与事件

- `_validatePositionSnapshot()` 显式接收 expected venue 和 adapter，只比较身份与金额，不隐式依赖 `activeVenue`。
- `_validateActivePosition()` 自己查询 Registry 地址，验证身份、金额、有效性与 V3 区间；消除先取 `position.adapter` 再与自身比较的形式校验。
- `_validatePositionState()` 编排主动仓位与非主动 V3 检查，保留原来 V2 → low V3 → high V3 的检查顺序。
- 实际 V3 区间验证与 Plan 一致后，Bootstrap/再平衡事件使用 Plan 区间；事件函数删除 `established` 仓位参数。实际仓位验证没有删除。

## 3. 测试结果

完整测试 **219 项通过、0 项失败**，包含继承复用的捐赠测试；完整隔离执行也通过。原有 V3 差分 fuzz 默认 256 次随全套执行，本次未修改 V3 数学实现，第一轮的 4,096 次扩展运行保留为历史证据。

保留仓位调用次数、异常身份/金额/区间、未收完手续费、捐赠、舍入、损失上限和资产守恒测试。余额调用次数测试改为确认会计边界的现读：有手续费存款每种代币 7 次、有手续费紧急退出每种代币 5 次，不再强制跨步骤缓存。

新增回归验证：

- 仅 token1 有手续费时事件和 shares 定价正确。
- 零手续费赎回不产生手续费同步事件。
- 实际建立的区间不符合 Plan 时仍在提交前回滚；使用 Plan 发事件不能掩盖实际仓位错误。

退出回调禁用目标后仍拒绝建仓、Registry 身份校验、非主动 V3 校验和独立到账核验均保留。生成存储布局确认生命周期字段仍在 slot 5、`_lastExecutedPlan` 从 slot 6 开始。

## 4. Gas 代价

环境和第一轮一致：Foundry 1.5.1、Solidity 0.8.24、optimizer runs 200、viaIR、Cancun。以 `--isolate` 的最后一次合约调用为准，fixture 为本地测试实现，不是主网分叉交易报价。

相对第一轮：

- V3 无手续费存款：261,924 → 264,092，增加 2,168（0.83%）。
- V3 有手续费存款：289,993 → 295,935，增加 5,942（2.05%）。
- V2 存款：284,744 → 286,656，增加 1,912（0.67%）。
- V3 间再平衡：452,576 → 458,523，增加 5,947（1.31%）。
- V3 有手续费再平衡：464,408 → 472,945，增加 8,537（1.84%）。
- token0 → token1 Swap 再平衡：440,698 → 449,067，增加 8,369（1.90%）。
- token1 → token0 Swap 再平衡：440,308 → 448,656，增加 8,348（1.90%）。
- 有手续费紧急退出：205,806 → 211,971，增加 6,165（3.00%）。
- 有手续费 V3 赎回：193,767 → 195,358，增加 1,591（0.82%）。
- V3 无手续费赎回减少 224，IDLE 赎回增加 38；V3 Adapter 预览和建仓 Gas 不变。

增量包含额外余额读取、独立 Registry 校验、函数组织和编译器内联变化，不全部归因于 `balanceOf()`。相对最初未优化版本，V3 有手续费存款仍减少 7.05%，有手续费再平衡减少 6.06%，正向 Swap 再平衡减少 4.37%。这些收益仍仅适用于同 fixture 的本地比较。

尝试过手续费事件直接计算两个总额而不组装资产结构体，但该候选使运行时代码额外增加 311 字节，只减少约数百 Gas 的手续费路径成本，因此撤回了这项微优化。

## 5. 尺寸与发布阻塞

独立生产源码构建：

- Vault runtime：26,860 → **27,109 字节**，增加 249。
- Vault initcode：34,532 → 34,802 字节，增加 270，未包含具体构造参数。
- V3 Adapter runtime/initcode 仍为 12,668 / 15,050 字节。

源码更短不保证优化器生成的字节码更小。本次没有声称缩减部署尺寸，也未更改编译配置或提高尺寸限制。Vault 仍超过 EIP-170 的 24,576 字节限制 **2,533 字节**，比第一轮更大；主网部署仍被阻止。相对最初实现的 27,157 字节仅减少 48 字节。

## 6. 复现命令

```bash
forge test --fuzz-seed 0x1234 --gas-snapshot-emit false
forge test --isolate --fuzz-seed 0x1234 --gas-snapshot-emit false
forge test --match-test testGas_ --isolate --gas-snapshot-emit false -vv
forge build src --sizes --out /tmp/adaptive-lp-simplify-selected --cache-path /tmp/adaptive-lp-simplify-selected-cache
forge build src --extra-output storageLayout --out /tmp/adaptive-lp-simplify-layout --cache-path /tmp/adaptive-lp-simplify-layout-cache
forge inspect AdaptiveLPVault storage-layout --json --out /tmp/adaptive-lp-simplify-layout --cache-path /tmp/adaptive-lp-simplify-layout-cache
```

尺寸构建会因超限返回非零，这是发布阻塞而非 Solidity 编译失败。独立 out/cache 用于避免混用全测试缓存或缺少 storageLayout 的产物。

本次改变的是内部组织，不需要前端或索引器适配。主网分叉基准和完整状态机 invariant 验证仍未执行；下一步若解决部署尺寸，应单独确定模块拆分边界，不能用删除安全检查解决。
