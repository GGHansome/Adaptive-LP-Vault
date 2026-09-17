## 问题 1
你的文档中关于Deposit 实际只转入 d0/d1 两种币的数量，而这两个数量按什么比例计算，在文档存在两处不同的规定：§1.1（产品定义概述）说按整个 Vault 全部资产（闲置 + 仓位合计，即 T0:T1）的比例；§5.3（详细公式）说按当前 LP 仓位本金（principal0:principal1）的比例。你本次修改（Debug 23）把详细公式从前者换成了后者，但只改了 §5.3，忘了同步修改 §1.1 的概述，导致同一份文档对同一行为给出两个互相矛盾的基准。比如：仓位内是 1 WETH : 2000 USDC，但 Vault 闲置中还有 500 USDC 未投（如手续费归集）→ 仓位比例 1:2000，总资产比例 1:2500，两者不同。实现者/前端若按 §1.1 理解，与按 §5.3 实现的合约行为对不上，同一笔存款的预期存入组合不同。

> 原因：§1.1 的概述沿用了旧的总资产比例表述，未同步 Debug 23 将 Deposit 比例改为当前 Active Position 本金比例的修改。

修改：
- 将 `PRODUCT_SPEC.md` §1.1 的“用户按 Vault 存款前的总资产比例提供两种资产”改为“后续 Deposit 按当前 Active Position 的本金比例提供两种资产，实际转入数量按 §5.3 的公式计算”。
- 明确后续 Deposit 的实际 `d0/d1` 按 `principal0:principal1` 计算；Vault 总资产比例 `T0:T1` 继续仅用于总资产、NAV、share price 和 Idle 健康度等相关计算。

## 问题 2
在 SPEC §10.3 的权限表里，renounceRole(DEFAULT_ADMIN_ROLE, ...) 单独占了一行，这看起来像其他行一样可以直接调用。但 OpenZeppelin 的实际行为是：想放弃根管理员，必须先调 beginDefaultAdminTransfer(address(0))，等 delay 过期，再由当前 admin 调 renounceRole 才能成功；跳过第一步直接调，必定回滚 AccessControlEnforcedDefaultAdminDelay。表格没有写这个前置。这样对比之下， 转移给新管理员 拆成了 begin/accept 两行分别列出， 放弃 却只有一行，把第一步吞进了注释里。后期如果按这直接写测试或前端，必然失败。

> 原因：§10.3 只引用了 `AccessControlDefaultAdminRules` 的“标准流程”，但没有把根管理员放弃所需的零地址转移计划和延迟条件写入入口契约，导致该行可被误读为单步操作。

修改：
- 在 `PRODUCT_SPEC.md` §10.3 将根管理员转移、取消、接受和放弃拆分为独立入口，并明确 `beginDefaultAdminTransfer(address(0))` 表示计划放弃根管理员。
- 明确当前 Default Admin 必须等待 `pendingDefaultAdminSchedule` 生效，再以自身地址作为 `callerConfirmation` 调用 `renounceRole(DEFAULT_ADMIN_ROLE, msg.sender)`；直接调用或延迟尚未生效时以 `AccessControlEnforcedDefaultAdminDelay` 回滚。
- 明确放弃成功后 `defaultAdmin()` 返回零地址；`ARCHITECTURE.md` 禁止通过普通 `grantRole`、`revokeRole` 或自定义入口重新指定根管理员。
- 同步产品验收清单和架构安全测试矩阵，覆盖零地址转移计划、延迟、调用者确认、直接放弃回滚和成功后的零管理员状态。

## 问题 3
你文档中关于紧急退出只把 activeVenue 置为 IDLE，不会写 activeAdapter。按存储表，activeAdapter 的写入时机只有「Bootstrap/Rebalance」，所以退出后它一直保留退出前的旧地址。这个旧地址在 IDLE 期间代表什么，在你的文档中没有定义：应该清零、保留，还是声明「只在 activeVenue != IDLE 时有意义」？三种选择都没写。

> 原因：`activeVenue` 已能通过 Bootstrap 后冻结的 Registry 唯一确定当前 Adapter，另存 `activeAdapter` 形成了冗余状态；Emergency Exit 未同步更新该缓存，使两个状态源可能不一致。

修改：
- 删除 Vault 的 `activeAdapter` 持久化字段，以 `activeVenue` 作为当前资产位置的唯一状态源。
- 明确 `activeVenue != IDLE` 时，当前 Adapter 由 `getAdapter(activeVenue)` 从冻结后的 Registry 绑定派生；`activeVenue == IDLE` 时 `getAdapter(IDLE) == address(0)`，且不得调用任何 Adapter。
- 明确 `totalAssets()` 仅在非 IDLE 时读取 `activeVenue` 对应 Adapter 的快照；IDLE 时 Position 资产为零且不读取 Adapter。
- `PositionSnapshot.adapter` 继续用于标识快照来源，不作为 Vault 的当前 Adapter 持久状态。

## 问题 4
FeesSynchronized：文档规定五类入口（存款、赎回、两种 rebalance、紧急退出）都要先调 syncFees()，但事件什么时候发没有定义。V2 的 syncFees() 按规定就是返回零费用 那 V2 状态下这个事件是每次都发（大量零值空事件），还是只在有实际费用时发？两种读法都成立，实现会分叉。

V3RangeChanged：bootstrap 建仓、Venue 迁移、Recenter 都会改变 Range，Deposit 只加流动性不改变 Range——这些场景哪些发、哪些不发，文档没有列举。还有一个边界没写：从一个 V3 池迁到另一个 V3 池时，如果新旧 Range 的数值恰好相同（两个池的对齐边界可以重合），算不算「改变」？

链下索引和审计依赖事件语义稳定，这两处不定，不同实现重建出来的历史就不一样。

> 原因：事件 ABI 只定义了字段，没有定义零值同步、首次建仓、跨 Venue 迁移和退出等分支的唯一发射条件，产品流程、架构时序与事件测试也未形成完整闭环。

修改：
- 明确 `FeesSynchronized` 只表示实际发生的 V3 手续费归集：仅当 `fee0 != 0 || fee1 != 0` 时由 Vault 发出一次；V2、IDLE、V3 双零以及最终回滚均不发出。
- 明确事件中的 `fee0/fee1` 使用 Vault 同步前后余额增量，`total0/total1` 使用费用到账、Position 快照重读及同步后校验完成后，且后续 Deposit、Withdraw、Swap 或建仓前的总资产快照。
- 明确 `V3RangeChanged` 在 Bootstrap 建立 V3、V2/IDLE 迁入 V3、同 Venue Recenter 和两个 V3 Venue 之间迁移时发出；此前不存在 V3 Position 时 old Tick 使用 `0/0`，跨 V3 Venue 即使新旧 Tick 数值相同也必须发出。
- 明确 Deposit、Redeem、费用同步、目标为 V2/IDLE 的 Rebalance 和 Emergency Exit 不发出 `V3RangeChanged`；迁出 V3 由 `RebalanceExecuted.targetVenue` 或 `EmergencyExit` 表示 Range 失效。
- 将事件定义和触发条件统一保留在 `ARCHITECTURE.md` §8；`PRODUCT_SPEC.md` 仅在 Bootstrap、Deposit、Redeem、两类 Rebalance 和 Emergency Exit 的执行步骤中列出应发出的事件，不再重复解释事件语义。Swap 数学不改变目标 Range，因此 `SWAP_REBALANE_MATH.md` 无需修改。

## 问题 5
先说个背景。Vault 判断价格用的始终是 canonical Pool，偏离度、NAV、Swap 最低输出全部按这个池的 TWAP 计算；但真正执行换币的池子是另一个独立配置项 swapPool。文档允许两者不是同一个池，部署时对 swapPool 的校验只有两条：是合法的 V3 池、Token 对得上。对池子流动性深度没有任何要求。

这带来两个问题：

第一，攻击成本变低。定价和成交分离在两个池子，攻击者只需操纵 swapPool 这一个池：把价格单边推到刚好卡在协议允许的最差成交价上，Vault 就会照单成交，攻击者赚走价差。全程不用碰 canonical Pool——偏离度不会升、TWAP 历史不会被污染、所有监控指标一片安静。如果规定两个池必须是同一个，攻击者推价时会同时推高 canonical 的现价，动静和成本都大得多。

第二，部署没有质量门槛。如果 swapPool 流动性很差，正常的换币修复操作会频繁因滑点超限而失败——关键的自救路径被卡死；或者每次都在限额内白白承受损失。文档对部署脚本没有任何预检要求。

损失有上界：攻击者最多赚走协议允许的最大滑点以内的价差，不是无限损失，所以定级 Medium 而不是 High。

修改：
- v1 强制 `ControlledSwapExecutor.swapPool() == CanonicalV3Oracle.canonicalPool()`；Token 对相同不能替代 Pool 地址相等，Vault 在构造及 Bootstrap 最终绑定校验时发现不一致即以 `InvalidSwapPool()` 回滚。
- 保留现有 `protocolMinOut`、只能收紧保护的 `keeperMinAmountOut` 和 `maxMigrationLossBps` 作为运行时损失边界，不新增 `maxSwapStartDeviationBps`。
- 新增 `DEPLOYMENT.md`，作为部署顺序、部署前检查、流动性预检、Bootstrap 操作和部署证据的唯一权威来源；产品、架构和数学文档只保留协议约束并引用该文档。
- 部署前必须针对 canonical/Swap 同一 Pool，使用最终 Router、Fee Tier、固定方法和显式 `liquidityTestAmount0/1` 执行双向报价；两个方向均须满足部署价格影响阈值并不低于 `protocolMinOut`，且在固定 Mainnet Fork 区块完成完整 `rebalanceWithSwap` 模拟。
- 明确部署报价只证明记录区块与测试金额下的流动性，运行期流动性退化时由 `protocolMinOut` 保证安全，并通过暂停 Swap Rebalance、无 Swap 退出到 IDLE 和双资产 Redeem 保留恢复与退出路径。

## 问题 6

tickLower/tickUpper 参与 planHash 的计算，但 HIGH 与 EXTREME 两档计划根本没有 Range 的概念——V2 是全价格区间流动性，IDLE 不持有任何仓位。这两档计划里这两个字段该填什么，文档没有规定：填 0/0、填 MIN/MAX_TICK，还是沿用当前 twap 的对齐值？不同选择算出的 planHash 不同。

缺口其实有两层。第一层是填充约定：字段值没有规定。第二层更根本：生成端规则也没有——§9.1.3 只定义了 LOW 和 MEDIUM 两档的 Range 计算规则，Strategy 生成 V2 或 IDLE 计划时如何设置这两个字段，全文没有任何条文。两层叠加的结果是：单一实现内部自洽（生成与校验同源），但跨实现无法复算。前端或 Keeper 想在链下复算一个 V2 计划的哈希，只能靠猜测实现者的填充约定；lastExecutedPlan 里存的历史计划哈希，第三方也无法独立验证。上轮 AUD-047 的 version 取值问题与此同族，但本条影响的是 HIGH/EXTREME 这些常态路径，直击 planHash「稳定可复算」的承诺。 

## 问题 7
在你本次修改（Debug 11）把部署率指标拆成了两个带阶段的名称：initialDeployBps（生成计划时算）和 simulatedDeployBps(x)（模拟最差 Swap 结果时算）。但建仓完成后的第三次校验，文档里仍用没有前缀的裸名 deployBps——它的公式和名字都没定义：分子用 Adapter 实际返回的 used0/used1 还是预估值？TWAP 用迁移前捕获的值还是重新读？

## 问题 8
§5.4 的公式说用户赎回 x 份 shares 能拿到 ⌊f×T⌋（按总资产一次取整）。但实际执行是分两步走的：先从仓位退出一部分（Adapter 自己取整），再从闲置资产分配一部分（Vault 再取整），两步各自向下取整后加起来。两次取整的结果可能比一次取整少 1~2 个最小单位。文档没说公式值是「保证拿到」还是「理论上限」，前端按公式预估的输出可能比用户实际到手的高一点，恰好卡在 minAmountOut 边界时就会出现预期外行为。

## 问题 9
PositionSnapshot 有四个字段是 V3 专属概念：liquidity、positionId、tickLower、tickUpper。V2 Adapter 返回快照时这四个字段填什么没有定义——liquidity 填 LP Token 余额还是 0？positionId 是不是恒 0？tick 边界用 0/0 还是 MIN/MAX？V2 是常态 ACTIVE Venue，策略逻辑和测试断言都需要这些字段有固定值。同族问题还有一处：IDLE 状态下调用 _getPlan 时，currentPosition 参数该传什么样的快照（全零值？）同样没有定义。

## 问题 10
Oracle 不健康时 snapshot() 不回滚、照常返回结构体，只是 healthy = false。但结构体里其他字段这时候填什么，没有定义：observe() 中途失败时，twapTick 是填 0 还是填已经算出来的那部分？特别是 deviationBps——如果填 0，任何不先检查 healthy 就直接消费这个字段的链下逻辑，会把 0 偏离误读成「市场平静、LOW 状态」。协议内部有强制门控不会用错，但测试断言和前端展示需要确定的填充规则。

## 问题 11
SPEC §10.3 说 deposit、redeem、rebalance、rebalanceWithSwap 都是「仅初始化后」可用。但 NotInitialized 错误的注释里列的适用场景只有四个入口（setPauseState、setAdapterEnabled、Emergency Exit、previewRebalance），漏了这四个。实现者在未初始化时调用这四个入口，该回滚什么错误就没有依据，可能各自选别的错误名，违反错误契约「名称固定」的要求。

## 问题 12
未初始化阶段 Manager 角色丢失导致 Vault 永久死壳
分两种情况。第一种：Default Admin 误把 MANAGER_ROLE 撤销了——这不是死局，Default Admin 还在，随时可以重新授予，只是恢复之前 Vault 没法 Bootstrap。第二种才是真死局：initialDefaultAdmin 本身失效（私钥丢失，或误填了零地址），这时未初始化的 Vault 永远无法 Bootstrap，只能当作部署成本扔掉——好在这个阶段还没有用户资金。另外，Bootstrap 之后如果 Manager 空缺，解暂停、恢复 Adapter 这些治理操作会冻结，但存款、赎回、任何人可调的 rebalance 都还开着，用户有退路。这本质上是运维风险而不是协议缺陷，但文档里连一条部署检查项都没有。
处理完这些 低风险问题之后你就可以开始开发了