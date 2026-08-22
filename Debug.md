## 问题 1
你现在的文档中有三处正文与结构体说明均要求调用者提交 Swap 方向确认值并由 Vault 复核 看着像是为了 防陈旧方向的乐观并发控制 ，但你 §6.1 接口定义只有 4 个参数，方向确认值无处传入；§6.1 入口规则表 与时序图 同样遗漏。按 4 参接口实现，Vault 目前只能自证自算的 zeroForOne，无法与调用者预期比对，error InvalidSwapDirection()（ARCH §7 已定义）在该路径下永无触发条件，方向陈旧保护整体悬空。

> 原因: expectedZeroForOne为我后续添加的功能，后未能及时同步架构文档当值出现歧义。

修改:
- `ARCHITECTURE.md` §6.1 的 `rebalanceWithSwap` 增加 `bool expectedZeroForOne`，接口由 4 个参数改为 5 个参数。
- §6.1 入口规则表补充：`expectedZeroForOne` 必须与 Vault 重算出的方向一致。
- Swap Rebalance 时序图补充 `expectedZeroForOne`，并明确 Vault 将其与推导方向进行比较。
- `PRODUCT_SPEC.md` 和 `SWAP_REBALANE_MATH.md` 已有五参数约定，因此无需修改。
- `expectedZeroForOne` 仅用于校验调用者预期方向是否陈旧；实际执行方向仍由 Vault 根据最新余额和 `previewDeposit` 推导，方向不匹配时回滚 `InvalidSwapDirection()`。

## 问题 2
minimumInitialNav 与 bootstrapRatioToleranceBps 无配置字段承载 
这两个 Bootstrap 前置检查参数在两个配置结构体中均无字段。SPEC §10.2 把它们列为"可由 Admin 在硬边界内更新"的治理参数（需发 ParameterUpdated 事件），但 ARCH 没有为它们定义存储归属、更新入口和边界校验位置。实现时无处安放。

## 问题 3
Adapter Registry 封存时序矛盾：Bootstrap 前还是 Bootstrap 后
你的 SPEC 说封存发生在 Bootstrap 成功之后 ARCH 的 Bootstrap 时序图要求在 bootstrap 调用内部校验 Registry 已处于 sealed 状态 即封存必须发生在 Bootstrap 之前 。两种读法下系统行为不同 按 SPEC，bootstrap 成功瞬间才 seal 谁调用？bootstrap 内部自动 seal？ ；按 ARCH，Admin 必须先另行调用 seal() 才能通过 bootstrap 的第一步校验。seal() 的调用者、调用时机、bootstrap 与 seal 之间的窗口期行为 谁能在此窗口新增 Adapter 均未定义。

## 问题 4
Market Regime 滞后状态无持久化机制，Hysteresis 正确性依赖未声明的隐式假设
Hysteresis 状态机的转移规则以 当前状态 为前提，但该状态既不在 Vault 存储中，也不在 Strategy 接口入参中。唯一候选来源是 positionPlan.marketRegime 上次成功执行的计划的 regime ，但这要求 Venue 和 Regime 严格双射 IDLE 和 EXTREME、V2 与 HIGH、V3高费 与 MEDIUM、V3低费 与 LOW）才能从 activeVenue 复原状态。该双射假设未写入任何不变量（INV-01~12 无此条），且被两条真实路径打破：  Guardian emergencyExitToIdle() 置 activeVenue = IDLE 但不经过任何计划（此时 regime 未必是 EXTREME）； 
全部流通 shares 赎回触发的 IDLE 同样无计划。这两条路径后，"从哪个滞后状态恢复"未定义。

## 问题 5
emergencyExitToIdle() 无最小输出参数，文档中承诺的滑点保护也无表达
你的 SPEC 承诺紧急退出使用"底层 AMM 的最小输出"作为成功判据，Adapter 接口也要求 minAmount0/minAmount1，但 Vault 层入口 emergencyExitToIdle() 不接受任何参数——最小输出值无来源。可选实现（内部常量、零值、配置参数）均未定义。若实现为零值，则该路径无任何输出下限保护；若为配置参数，则该参数未出现在任何配置结构体中

## 问题 6
你的 §6 标题为接口契约，但只覆盖 LP 资产流。Guardian 暂停、Admin 参数更新、角色授予/撤销、Registry 的 setAdapterEnabled/seal 虽有独立接口但调用权限与 Vault 的关系未定义 全部没有签名。事件契约定义了这些状态变化的广播，却没有对应的状态变更入口。后面你实现的时候就必须自行发明整个治理函数面，且无法从文档得知 参数更新的边界校验位置、批量更新语义、角色常量标识。

## 问题 7
observe() 的窗口由 Oracle 使用，但窗口数值被放进可治理更新的 StrategyConfig。Oracle 若在部署/初始化时固化窗口，则 Admin 更新 StrategyConfig.twapWindowSeconds 后 Oracle 行为不变——治理更新是无操作，ParameterUpdated 事件发出但系统无变化；若 Oracle 每次从 StrategyConfig 读窗口，则违背"部署时固定"且 Oracle 需要引用 Vault 配置 。在两份文档共同作用下，窗口存在两个互斥的事实来源

## 问题 8
canEnter 是独立存储位还是 enabled 的视图派生 如 enabled && vaultInitialized 未定义；没有任何入口写它，但事件携带它。若为独立位，谁在何时置位/复位未定义；若为派生值，事件中包含冗余字段且结构体不应声明为存储配置。

## 问题 9
protocolMinOut 在 token1→token0 方向需要 Q0（token1 数量按 tick 报价为 token0 数量），但 Oracle 接口只定义了 quoteToken0InToken1。你在实现的时候要么自行实现反向报价 取整方向未规定——作为最小输出下限时必须保守向上，规格未说明 ，要么用 Q1 求逆

## 问题 10
事件契约中的 PlanGenerated 在系统里没有任何合法的发出点 预览是 view 不能发 执行成功时计划已被执行（RebalanceExecuted 携带 planHash） 执行失败即回滚（事件不存在）。若意图是在 RebalanceExecuted 之外补充 planHash→(venue, regime, requiresSwap) 的映射广播，则应说明与 RebalanceExecuted 的关系及是否在同一交易内成对发出。

## 问题 11
deployBps 同名指标在两处使用不同分母 NAV_1 vs NAV_after,sim ，分别用于策略标记 requiresSwap（执行前）与 Swap 路径校验（执行中），但你文档未声明二者是不同阶段的不同检查、也未给出关系（由于 Swap 滑点，NAV_after,sim ≤ NAV_1，故执行期比值 ≥ 策略期比值，非冗余）。这很容易将两公式混用或误判为矛盾。

## 问题 12
"Active Position 有效"在 Adapter 被禁用时的判定未定义
 Guardian 禁用当前 Active Adapter 后：仓位仍存在（禁用只阻止进入），但存款前置"Active Position 有效"是否因此为假？若 有效 含 Adapter enabled ，存款自动关闭 合理 若不含，用户资金继续注入一个被 Guardian 判定异常的 Adapter。规格未定义判定式。

## 问题 13
Guardian 在 IDLE 状态调用紧急退出 回滚则 Guardian 无法区分 失败因已安全 与 失败因异常 ；成功则发出 EmergencyExit 事件但无任何状态变化 。锁定 shares 全部赎回后的不可重启 IDLE 壳同理。

## 问题 14
previewRebalance() 边界行为未定义 与执行入口相同路径 在异常状态下意味着回滚，但你要考虑到前端调用方需要区分 不可执行原因 ；PositionPlan 结构含 MarketRegime 枚举值 ORACLE_UNHEALTHY，这里暗示可以返回该状态的计划而非回滚 两种设计并存于文档的暗示中，没有进行裁定。未初始化 Vault 的 preview（无仓位无配置）同样未定义。

## 问题 15
getPlan 在 Oracle 不健康时的返回契约未定义 Strategy 是纯函数，MarketRegime 枚举含 ORACLE_UNHEALTHY，但 不生成可执行计划 未定义是 revert 还是返回带该枚举的计划。planHash 在该情形下如何计算 若返回结构体则必须有哈希，但该哈希不可用于执行 未定义。

## 问题 16
角色系统的两个基础问题无规格：
ADMIN_ROLE/KEEPER_ROLE/GUARDIAN_ROLE 的标识与是否采用 OZ AccessControl 风格；
初始授权链——部署者是否自动成为 Admin、Guardian 能否由 Admin 授予/撤销 SPEC §2 未说 Guardian 的管理者是谁 。VaultRoles.sol 是规划文件但无内容契约。

## 问题 17
"比例容差"没有参照系。三种候选基准对同一组 (amount0, amount1) 的接受/拒绝结果不同
只要求价值匹配 TWAP（宽松）；
要求能被目标仓位吸收（可能很严，V3 窄区间比例倾斜）；
要求价值对半。

## 问题 18
Bootstrap 前的治理状态未定义 谁可暂停未初始化 Vault；bootstrap 遇 depositPaused 的行为

## 问题 19
observe() 调用形状术语表与规范正文不一致
你的术语表描述为两次独立二元素 observe，规范正文定义为单次三元素调用。数学上等价 observe 纯读 ，但调用形状是接口契约的一部分 gas、错误路径、secondsAgos 数组构造 ，验收清单  明确以三元素形状为测试对象。

## 问题 20
PAUSED 作为伪状态混入生命周期状态表，与自身声明矛盾
你在同一节内先用状态表把 PAUSED 表述为与 IDLE/ACTIVE 并列的生命周期状态 含进入/退出条件 ，两行后又声明它不是状态而是独立维度。ARCH 状态图与后一种读法一致。表内 "PAUSED 的退出条件" 健康门控恢复 还引入了"自动解除暂停"的暗示，与 §10.1 暂停只能由角色操作 或入口检查式自动门控 的语义混淆。

## 问题 21
narrow/wideRangeHalfWidth 的 "对齐 spacing" 校验对象未定义
半宽以通用 tick 数配置，但两个目标 V3 池的 tickSpacing 不同。 均可对齐 spacing 无法作为配置时校验这里对齐哪个？，只能在每次按目标池对齐时计算——参数表把它写成配置约束，实现者会尝试在 updateStrategyConfig 时校验并遇到歧义。

## 问题 22
redeem 接口无 owner 参数，"获授权 spender"入口规则无法实现
入口规则表允许"获授权 spender"代持有人赎回，但接口没有 owner 参数——spender 调用时 Vault 无从得知应对谁的 shares 余额销毁、检查谁的授权。ERC-4626 的标准解法是 redeem(shares, receiver, owner) 三地址参数；本接口的 4 参数形状只能支持 msg.sender 即持有人自赎。声称的权限模型与接口形状矛盾。

## 问题 23
Deposit 实际数量 d0/d1 的推导算法未定义双侧 max 的截断与舍入路径不唯一
目标关系只给出比例约束（1 参数解族），加上两个上限后仍存在多条合法推导路径：锚定 token0 侧（d0 = min(max0, ⌊max1 × T0/T1⌋)，d1 = ⌊d0 × T1/T0⌋）、锚定 token1 侧（对称）、或按 f = min(max0/T0, max1/T1) 等比缩放再各自向下取整。在比例非整除的输入下，这些算法给出不同的 (d0, d1)（差异在最小单位量级），且均满足"误差仅来自舍入"的字面要求——但 sharesMinted 与 InvalidDepositRatio 的触发边界随之不同。同一用户输入在不同实现下获得不同 shares，存款定价的确定性与公平性依赖实现者选择。

## 问题 24
"所有 AMM 操作包含最小输出和截止时间"与 bootstrap/deposit/Adapter 接口参数面不符

## 问题 25
Swap 接收地址二义性："Vault 或受控 Executor"未裁定，余额增量校验对象随之不明
Swap 输出接收方在"Vault"与"受控 Executor"两个选项间未裁定。若接收方是 Executor 输出 token 滞留 Executor，后续 Adapter 建仓需要 Executor→Vault 的二次转账（该流程、授权与清理均未定义），且"实际余额增量"应度量 Executor 余额；若接收方是 Vault：增量度量 Vault 余额，MATH §6 "带 Swap 路径的 Executor 实际余额增量满足 minAmountOut" 的表述指代错位（增量发生在 Vault 而非 Executor）。两种读法下的后置校验位置、资金流与授权模型均不同。

## 问题 26
 dustTolerance0/1 列于治理参数表但归入 ImmutableConfig，可更新性矛盾
dustTolerance0/1 出现在可由 Admin 更新的治理参数表中，但 ARCH 将其定义为不可变配置，两份文档对同一参数的可变性判定相反。且含混具有安全敏感性：守恒校验的容忍窗口若可治理调大，等于可放宽资产损失检查——与 自身声明的"不能用于放宽价值损失"冲突。

## 问题 27
IdleStateChanged 事件的触发点集合未定义

## 问题 28
治理参数更新后 positionPlan 陈旧且 planVersion 不递增，Deposit 继续按旧计划建仓

## 问题 29
token1Decimals > 18 无约束，份额锚定与取整粒度退化

## 问题 30
单边实际存款为零时回滚错误未指定 ZeroAmount vs InvalidDepositRatio

## 问题 31
Cooldown 与 Emergency Exit 的交互未显式对齐

## 问题 32
ParameterUpdated 事件的参数转型语义未定义int24 参数与 bytes32 标识

## 问题 33
 OracleSnapshot.observedAt 与三个价格字段的标度/参考量未定义
价格字段未定义标度：是 1 raw unit token0 的 token1 报价、还是 10^token0Decimals（1 整个 token0）的报价、还是 X96 定点——三种标度在同一字段名下均可行；observedAt 无任何使用处与语义说明。另外 AssetSnapshot.nav1 在 Oracle 不健康时（无法计算 TWAP 报价）的取值（回滚？零？）也未定义。

## 问题 34
getAdapter(IDLE) 的返回值未定义

## 问题 35
继承式 Registry 与系统图/接口的部署语义不一致
你的Registry 是继承进 Vault 的内部模块 无独立地址、无跨合约调用 ，但系统图与 §6.5 的完整外部接口形状 含 seal() 等入口 均按独立合约表达。图示的调用边在继承式实现中不存在；IAdapterRegistry 若仅由 Vault 自身实现，其接口语义 外部可调用性、权限边界 需重新说明。

## 问题 36
紧急退出"关闭 Deposit 和 Rebalance"的实现机制歧义
"关闭 Deposit 和 Rebalance"未说明是通过写入暂停位（depositPaused/plainRebalancePaused/swapRebalancePaused = true）实现，还是仅依赖 IDLE 状态自身的门控。若写暂停位：紧急退出产生未声明的暂停副作用，且后续 IDLE→ACTIVE 恢复 rebalance 前需要角色先解除暂停（额外恢复步骤未写入任何流程）；若不写：步骤 6 的"关闭"对 Deposit 是冗余描述（已由 IDLE 门控）。两种读法行为不同。

## 问题 37
Executor 在你的文档中被要求"验证计划哈希"，但它不接触 Strategy、不存储任何计划记录，也没有可对照的真值源——该哈希在 Executor 侧无法被有意义地验证 至多做非零检查，与"验证"语义不符 。真正有效的哈希校验发生在 Vault 侧（expectedPlanHash vs 重新生成计划）；Executor 侧的这条要求无实现语义。

## 问题 38
lastSuccessfulRebalanceAt 在 Bootstrap 成功时是否设置未定义

## 问题 39
Adapter withdraw 最小输出与用户 redeem 最小输出的映射规则未定义

## 问题 40
spotTick 声明的"安全检查 / Swap 风控"用途无实现

## 问题 41
getPlan 生成计划的 version 取值规则未定义
看一下这些问题 处理一下 完事之后可以 再找我