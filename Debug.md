## 问题 1
你现在的文档中有三处正文与结构体说明均要求调用者提交 Swap 方向确认值并由 Vault 复核 看着像是为了 防陈旧方向的乐观并发控制 ，但你 §6.1 接口定义只有 4 个参数，方向确认值无处传入；§6.1 入口规则表 与时序图 同样遗漏。按 4 参接口实现，Vault 目前只能自证自算的 zeroForOne，无法与调用者预期比对，error InvalidSwapDirection()（ARCH §7 已定义）在该路径下永无触发条件，方向陈旧保护整体悬空。

> 原因: expectedZeroForOne为我后续添加的功能，后未能及时同步架构文档当值出现歧义。

修改:
- `ARCHITECTURE.md` §6.1 的 `rebalanceWithSwap` 增加 `bool expectedZeroForOne`，接口由 4 个参数改为 5 个参数。
- `expectedZeroForOne` 必须与 Vault 重算出的方向一致。
- Swap Rebalance 时序图补充 `expectedZeroForOne`，并明确 Vault 将其与推导方向进行比较。
- `expectedZeroForOne` 仅用于校验调用者预期方向是否陈旧；实际执行方向仍由 Vault 根据最新余额和 `previewDeposit` 推导，方向不匹配时回滚 `InvalidSwapDirection()`。

## 问题 2
minimumInitialNav 与 bootstrapRatioToleranceBps 无配置字段承载 
这两个 Bootstrap 前置检查参数在两个配置结构体中均无字段。SPEC §10.2 把它们列为"可由 Admin 在硬边界内更新"的治理参数（需发 ParameterUpdated 事件），但 ARCH 没有为它们定义存储归属、更新入口和边界校验位置。实现时无处安放。

> 原因：Bootstrap 专用参数在配置类型设计中遗漏，且其生命周期没有与“仅使用一次”的语义对齐。

修改：
- `minimumInitialNav` 与 `bootstrapRatioToleranceBps` 纳入 `VaultConfig`，不再单独定义 `BootstrapConfig`；`VaultConfig` 只作为部署构造输入和内存传参结构，不作为整体状态变量写入普通 storage。
- 两个字段在部署前完成校准，并在 Vault 构造时执行协议硬边界和字段关系校验；随后分别写入 Vault 的 Solidity `immutable` 状态变量。它们只在唯一一次 `bootstrap()` 中读取，调用者不能覆盖。
- 删除 `BootstrapConfig`、`updateBootstrapConfig`、`bootstrapConfig()` 查询及对应的 `ParameterUpdated` 语义；这两个字段不是治理参数，部署后永久不可修改。如需采用不同值，必须部署新的 Vault。
- `bootstrapRatioToleranceBps` 后续按问题 17 删除；上述配置和生命周期结论最终仅适用于 `minimumInitialNav`。

## 问题 3
Adapter Registry 封存时序矛盾：Bootstrap 前还是 Bootstrap 后
你的 SPEC 说封存发生在 Bootstrap 成功之后 ARCH 的 Bootstrap 时序图要求在 bootstrap 调用内部校验 Registry 已处于 sealed 状态 即封存必须发生在 Bootstrap 之前 。两种读法下系统行为不同 按 SPEC，bootstrap 成功瞬间才 seal 谁调用？bootstrap 内部自动 seal？ ；按 ARCH，Admin 必须先另行调用 seal() 才能通过 bootstrap 的第一步校验。seal() 的调用者、调用时机、bootstrap 与 seal 之间的窗口期行为 谁能在此窗口新增 Adapter 均未定义。

> 原因：Registry 从独立部署改为由 Vault 继承后，旧的独立 `seal()` 生命周期、接口和系统图未同步删除。

修改：
- `AdapterRegistry` 是由 `AdaptiveLPVault` 继承并内部集成的源码模块，负责 Vault 内的地址簿、绑定校验和 operational 状态；不单独部署、没有独立地址，也不再作为系统图中的跨合约调用节点。绑定使用单一的 `_adapterByVenue` Mapping。
- 删除手动 `seal()`、`sealed()`、独立 `sealed` 状态、`RegistrySealed` 错误和封存事件契约。`initialized` 是唯一的生命周期冻结边界：`initialized == false` 时 Manager 可以配置或修正绑定；`bootstrap()` 只在完整校验和全部资产/Position 操作成功后将其从 `false` 设置为 `true`，失败不会冻结；`VaultBootstrapped` 是绑定成功冻结的链上信号。
- Bootstrap 前由 Manager 显式调用 `configureAdapter(VenueType venue, address adapter)` 注册已独立部署的非 `IDLE` Adapter；`bootstrap()` 不会自动部署或配置 Adapter。配置入口读取并校验 Adapter 的 Pool、Token 顺序、Fee Tier 和 `tickSpacing` 绑定，成功时将 `enabled` 初始化为 `true` 并缓存已验证的 `tickSpacing`，再发出 `AdapterConfigured`。

## 问题 4
Market Regime 滞后状态无持久化机制，Hysteresis 正确性依赖未声明的隐式假设
Hysteresis 状态机的转移规则以 当前状态 为前提，但该状态既不在 Vault 存储中，也不在 Strategy 接口入参中。唯一候选来源是 positionPlan.marketRegime 上次成功执行的计划的 regime ，但这要求 Venue 和 Regime 严格双射 IDLE 和 EXTREME、V2 与 HIGH、V3高费 与 MEDIUM、V3低费 与 LOW）才能从 activeVenue 复原状态。该双射假设未写入任何不变量（INV-01~12 无此条），且被两条真实路径打破：  Guardian emerge ncyExitToIdle() 置 activeVenue = IDLE 但不经过任何计划（此时 regime 未必是 EXTREME）； 
全部流通 shares 赎回触发的 IDLE 同样无计划。这两条路径后，"从哪个滞后状态恢复"未定义。

> 原因：`positionPlan.marketRegime` 虽保存了最近成功计划的 Regime，但现有 Strategy 接口没有接收该历史值；同时，资产位置和 Hysteresis 历史被隐式绑定，Emergency Exit 或全部流通 shares 赎回进入 IDLE 后无法唯一恢复上次策略状态。

修改：
- Vault 使用 `lastExecutedPlan` storage 保存最近一次成功执行的完整 Strategy 计划；`lastExecutedPlan.marketRegime` 是 Hysteresis 历史的唯一事实来源，不从 `activeVenue` 或 `lastExecutedPlan.targetVenue` 推导。
- `IMarketRegimeStrategy.getPlan` 接收 `MarketRegime lastCommittedRegime` 参数；Vault 在 Preview、普通 Rebalance 和带 Swap Rebalance 中将 `lastExecutedPlan.marketRegime` 作为该参数传入。
- `planVersion == 0` 是无历史计划的唯一标志。首次生成计划时 Strategy 忽略 `lastCommittedRegime` 参数的默认枚举值，按完整进入阈值直接分类；`planVersion > 0` 时使用传入的 `lastExecutedPlan.marketRegime` 执行 Hysteresis。
- 候选 `PositionPlan.version` 固定为当前 `planVersion + 1`。Bootstrap 或 Rebalance 成功执行策略计划后，将 `lastExecutedPlan` 写为执行计划，并将 `planVersion` 写为该计划的 `version`。
- Emergency Exit 在非 IDLE 时清空 Position 并递增 `planVersion`，但在 IDLE 时不改变 Position；`lastExecutedPlan` 始终保持不变。Oracle 不健康、Preview 和失败交易也不得覆盖该计划及其 `marketRegime`。
- 任一合法 `PositionPlan` 的 `targetVenue` 与 `marketRegime` 严格双射：`IDLE` ↔ `EXTREME_DEVIATION`、`UNISWAP_V2` ↔ `HIGH_DEVIATION`、`UNISWAP_V3_HIGH_FEE` ↔ `MEDIUM_DEVIATION`、`UNISWAP_V3_LOW_FEE` ↔ `LOW_DEVIATION`；该约束不要求非策略退出后的当前 `activeVenue` 与历史计划目标一致。
- Deposit、未清空 Position 的部分 Redeem、费用同步、Donation、暂停和 Adapter `enabled` 变化不属于 Position 结构变化，不递增 `planVersion`。

## 问题 5
emergencyExitToIdle() 无最小输出参数，文档中承诺的滑点保护也无表达
你的 SPEC 承诺紧急退出使用"底层 AMM 的最小输出"作为成功判据，Adapter 接口也要求 minAmount0/minAmount1，但 Vault 层入口 emergencyExitToIdle() 不接受任何参数——最小输出值无来源。可选实现（内部常量、零值、配置参数）均未定义。若实现为零值，则该路径无任何输出下限保护；若为配置参数，则该参数未出现在任何配置结构体中

> 原因：Adapter 的 Position 退出步骤与 Vault 的最终资产输出保护被混为一层。`redeem` 的 `minAmount0Out/minAmount1Out` 约束 Position 退出资产与用户按比例取得的 Idle 资产之和，不能直接作为 Adapter 局部退出的最低输出；Emergency Exit 的首要目标则是无条件清空全部 Position，不应由业务层最小输出阻塞。

修改：
- `IPositionAdapter.withdraw` 删除 `minAmount0/minAmount1`，只接收 `shares` 和 `totalShares`；`IPositionAdapter.withdrawAll` 删除两个最小输出参数，改为无参数完整退出。
- Vault 将按比例退出的 Position 资产与对应 Idle 资产合并为最终 `amount0Out/amount1Out` 后统一校验。
- `emergencyExitToIdle()` 保持无参数，并调用无参数 `withdrawAll()`；该路径不设置业务层最小输出，只以资产实际返回 Vault、旧 Position liquidity 清零和状态一致性作为成功条件。

## 问题 6
你的 §6 标题为接口契约，但只覆盖 LP 资产流。Guardian 暂停、Admin 参数更新、角色授予/撤销、Registry 的 setAdapterEnabled/seal 虽有独立接口但调用权限与 Vault 的关系未定义 全部没有签名。事件契约定义了这些状态变化的广播，却没有对应的状态变更入口。后面你实现的时候就必须自行发明整个治理函数面，且无法从文档得知 参数更新的边界校验位置、批量更新语义、角色常量标识。

> 合并范围：原问题 16 的角色标识与初始授权链，原问题 18 的 Bootstrap 前治理状态，原问题 36 的暂停写入问题，均属于同一运行时治理 ABI 缺失问题，在此统一处理。

> 原因：产品文档只描述了角色能力，架构文档却没有把角色、暂停和继承式 Registry 入口组合到 Vault 的外部 ABI。与此同时，数值配置和 Registry 生命周期已经分别改为部署固定与 Bootstrap 自动冻结，旧的参数更新和手动 `seal()` 假设没有同步从该问题中剔除。

修改：
- 手动 `seal()` 已由问题 3 删除，`initialized = true` 是唯一 Registry 身份冻结边界。
- `IAdaptiveLPVault` 在 Vault 同一地址上组合 OpenZeppelin Contracts v5 `IAccessControlDefaultAdminRules` 标准 ABI 与继承式 `IAdapterRegistry`。
- 删除自管理的 `ADMIN_ROLE`，将原业务 Admin 重命名为 `MANAGER_ROLE = keccak256("MANAGER_ROLE")`；`KEEPER_ROLE` 和 `GUARDIAN_ROLE` 保持不变。`DEFAULT_ADMIN_ROLE` 是唯一根角色，只负责业务角色授予/撤销和自身标准继任流程，不自动获得任何 Vault 业务权限。
- 新增 `AccessControlConfig(initialDefaultAdminDelay, initialDefaultAdmin)` 构造输入，并直接使用 `AccessControlDefaultAdminRules` 的单一 Default Admin、两阶段延迟转移、取消/接受和延迟调整流程。
- 新增 `setPauseState(PauseState)`：仅 Bootstrap 后开放；Manager 可暂停或解除暂停，Guardian 只能把暂停位从 false 改为 true；相同状态回滚 `NoStateChangeRequired()`，成功后原子更新并发出一次 `PauseStateChanged`。
- 未初始化阶段只开放 Manager 的 `configureAdapter`、`bootstrap`，以及 Default Admin 的标准角色和根管理员管理入口；`setPauseState`、`setAdapterEnabled`、Deposit、Rebalance 和 Emergency Exit 均以 `NotInitialized()` 回滚。暂停位初始全为 false，`bootstrap()` 不读取暂停状态。
- `PRODUCT_SPEC.md` §10 使用 Default Admin、Manager、Guardian、Keeper 权限表明确各入口的生命周期和成功结果；`SWAP_REBALANE_MATH.md` 中原 Keeper/Admin 表述同步改为 Keeper/Manager。

## 问题 7
observe() 的窗口由 Oracle 使用，但窗口数值被放进可治理更新的 StrategyConfig。Oracle 若在部署/初始化时固化窗口，则 Admin 更新 StrategyConfig.twapWindowSeconds 后 Oracle 行为不变——治理更新是无操作，ParameterUpdated 事件发出但系统无变化；若 Oracle 每次从 StrategyConfig 读窗口，则违背"部署时固定"且 Oracle 需要引用 Vault 配置 。在两份文档共同作用下，窗口存在两个互斥的事实来源

> 原因：TWAP 观察窗口同时出现在 Strategy 配置和 Oracle 使用路径中，且两者的可变性约定不一致，可能导致治理更新只改变配置而不改变 Oracle 行为。

修改：
- 将 `twapWindowSeconds` 和 `shortTwapWindowSeconds` 从 `StrategyConfig` 移至独立的 `OracleConfig`。
- 由 `CanonicalV3Oracle` 在构造时校验并写入 `immutable`；部署后不提供治理更新入口。
- `OracleSnapshot` 中的窗口字段仅作为 Oracle immutable 配置的只读回显，不得独立存储或由调用者提供；一致性测试在实现阶段补充。

## 问题 8
canEnter 是独立存储位还是 enabled 的视图派生 如 enabled && vaultInitialized 未定义；没有任何入口写它，但事件携带它。若为独立位，谁在何时置位/复位未定义；若为派生值，事件中包含冗余字段且结构体不应声明为存储配置。

> 原因：旧 `AdapterConfig` 同时包含 `enabled` 和 `canEnter`，但没有定义 `canEnter` 的存储位置、派生规则、写入入口和事件语义。

修改：
- 删除 `canEnter` 独立字段，`enabled` 作为 Adapter 的运行状态 storage 字段。
- `isEnterEnabled(venue)` 仅由 Adapter 已注册且 `enabled == true` 派生，不包含 `vaultInitialized`；初始化、暂停、Oracle 健康和 Position 一致性由 Vault 入口单独校验。
- `AdapterStatusChanged` 仅广播 `enabled`，不再携带没有独立来源的 `canEnter`。

## 问题 9
protocolMinOut 在 token1→token0 方向需要 Q0（token1 数量按 tick 报价为 token0 数量），但 Oracle 接口只定义了 quoteToken0InToken1。你在实现的时候要么自行实现反向报价 取整方向未规定——作为最小输出下限时必须保守向上，规格未说明 ，要么用 Q1 求逆

> 原因：双向报价接口与 `protocolMinOut` 的分阶段取整语义没有同步到架构和数学契约。

修改：
- `OracleConfig` 增加 `token0`、`token1` 和 `canonicalPool`；`CanonicalV3Oracle` 将其写入 immutable，并按 Vault Token 顺序提供 `quoteToken0InToken1` 和 `quoteToken1InToken0`，两者通过 `roundUp` 参数选择向下或向上取整。
- `protocolMinOut` 先取得向上取整的方向报价，再对 BPS 滑点折算向上取整；相对仅在最终结果处取整的精确有理数公式，结果相同或最多高一个输出 Token raw unit。
- 产品验收与架构测试矩阵补充双向报价、Token 顺序和两段取整测试。

## 问题 10
原事件契约中的 `PlanGenerated` 在系统里没有任何合法的发出点 预览是 view 不能发 执行成功时计划已被执行（RebalanceExecuted 携带 planHash） 执行失败即回滚（事件不存在）。若意图是在 RebalanceExecuted 之外补充 planHash→(venue, regime, requiresSwap) 的映射广播，则应说明与 RebalanceExecuted 的关系及是否在同一交易内成对发出。

修改：
- 将 `PlanGenerated` 重命名为 `PositionPlanCommitted`。
- Bootstrap、普通 Rebalance 和带 Swap Rebalance 成功提交 `lastExecutedPlan` 后发出 `PositionPlanCommitted`。

## 问题 11
deployBps 同名指标在两处使用不同分母 NAV_1 vs NAV_after,sim ，分别用于策略标记 requiresSwap（执行前）与 Swap 路径校验（执行中），但你文档未声明二者是不同阶段的不同检查、也未给出关系（由于 Swap 滑点，NAV_after,sim ≤ NAV_1，故执行期比值 ≥ 策略期比值，非冗余）。这很容易将两公式混用或误判为矛盾。

> 原因：首次部署评估与最差 Swap 输出模拟复用了无阶段后缀的 `deployBps` 名称，容易使实现混用 `T0/T1` 与 `H0/H1` 的资产快照和分母。

修改：
- 首次部署评估结果命名为 `initialDeployBps`，输入为 `T0/T1`，用于生成 `requiresSwap` 和 `direction`。
- 最差 Swap 输出模拟结果命名为 `simulatedDeployBps(x)`，输入为 `H0(x)/H1(x)`，用于校验 Keeper 提交的 `amountIn`。
- 两者复用 `_assessDeployment` 的同一部署率公式，并在产品流程、数学公式和架构时序中分别标明阶段，满足`initialDeployBps < minDeployBps`和`simulatedDeployBps(x) >= minDeployBps`。
- 后续裁定：仅保留 `maxHealthyIdleBps` 作为配置；`minDeployBps` 不再进入 `StrategyConfig` 或 Vault storage，始终由 `BPS - maxHealthyIdleBps` 派生。

## 问题 12
"Active Position 有效"在 Adapter 被禁用时的判定未定义
 Guardian 禁用当前 Active Adapter 后：仓位仍存在（禁用只阻止进入），但存款前置"Active Position 有效"是否因此为假？若 有效 含 Adapter enabled ，存款自动关闭 合理 若不含，用户资金继续注入一个被 Guardian 判定异常的 Adapter。规格未定义判定式。

> 原因：旧规格把 Position 的结构有效性与 Adapter 的运行时进入权限混在“Active Position 有效”一句中，同时只说明禁用不阻止退出，没有裁定向现有 Position 增加 liquidity 是否属于进入。

修改：
- Active Position 的结构有效性不包含 Adapter `enabled`；禁用当前 Adapter 不改变资产计价、`activeVenue`、`planVersion`、`lastExecutedPlan` 或暂停 storage。
- `enabled` 统一表示是否允许建立或增加 liquidity。Deposit、迁入目标 Venue 和同 Venue V3 Recenter 在调用 `previewDeposit()`、`deposit()` 或转入用户 Token 前必须检查目标 Adapter，禁用时以 `AdapterDisabled()` 回滚。
- 已禁用的当前 Adapter 仍允许 `snapshot()`、`syncFees()`、Redeem、迁出和 Emergency Exit；非 IDLE 目标被禁用时 Preview 和两类 Rebalance 回滚，目标为 IDLE 时不检查 Adapter 状态。
- 产品验收与架构测试矩阵补充禁用后的 Deposit、计价、Redeem、迁出、目标建仓和状态不变测试；Swap 数学仅补充进入门控前置条件，公式不变。

## 问题 13
Guardian 在 IDLE 状态调用紧急退出 回滚则 Guardian 无法区分 失败因已安全 与 失败因异常 ；成功则发出 EmergencyExit 事件但无任何状态变化 。锁定 shares 全部赎回后的不可重启 IDLE 壳同理。

修改：
- `emergencyExitToIdle()` 仅在调用前 `activeVenue != IDLE` 时同步费用、完整撤仓、递增一次 `planVersion` 并发出 `EmergencyExit`；已在 IDLE 时跳过 Adapter，不改变 `activeVenue`、`planVersion`、`lastExecutedPlan` 或 `lastPositionChangeAt`，且不发出 `EmergencyExit`。
- 两个分支都将三个暂停位设为 true；仅暂停 storage 实际变化时发出 `PauseStateChanged`。
- 全部流通 shares 赎回不触发生命周期或资产位置转换；Redeem 仍按销毁前 `x/S` 部分退出 Position，保留 `minimumLockedShares` 对应的 Position 或 Idle 资产，`activeVenue`、`planVersion` 和 `lastExecutedPlan` 不变。
- 产品验收与架构测试覆盖 ACTIVE/IDLE 两种 Emergency Exit 分支、重复调用、事件和版本不变，以及全部流通 shares 赎回后的锚定资产保留行为。

## 问题 14
previewRebalance() 边界行为未定义 与执行入口相同路径 在异常状态下意味着回滚，但你要考虑到前端调用方需要区分 不可执行原因 ；PositionPlan 结构含 MarketRegime 枚举值 ORACLE_UNHEALTHY，这里暗示可以返回该状态的计划而非回滚 两种设计并存于文档的暗示中，没有进行裁定。未初始化 Vault 的 preview（无仓位无配置）同样未定义。

> 原因：`previewRebalance()` 的零参数接口只能根据 Vault 当前已提交的资产和 Position 状态预览下一次 Rebalance。未初始化时尚不存在这些状态，初始计划又依赖 Bootstrap 调用者尚未提交的 `amount0/amount1`，因此任何返回值都只能是无执行意义的占位计划。

修改：
- `previewRebalance()` 仅适用于已初始化 Vault，并且必须先检查 `initialized == true`；未初始化时以 `NotInitialized()` 回滚。
- `NotInitialized()` 检查早于 Oracle 读取和 Strategy 调用；该路径不得读取默认 `positionPlan`、生成 `planHash` 或返回占位 `PositionPlan`。
- 初始化后的 Oracle 不健康分支继续以 `OracleUnhealthy()` 回滚；前端可以通过两个不同的 custom error 区分未初始化与 Oracle 异常。

## 问题 15
getPlan 在 Oracle 不健康时的返回契约未定义 Strategy 是纯函数，MarketRegime 枚举含 ORACLE_UNHEALTHY，但 不生成可执行计划 未定义是 revert 还是返回带该枚举的计划。planHash 在该情形下如何计算 若返回结构体则必须有哈希，但该哈希不可用于执行 未定义。

> 原因：旧设计把“健康 Oracle 下的市场偏离分类”和“Oracle 数据不可用”混入同一个 `MarketRegime` 枚举，但 `PositionPlan` 又被定义为可执行候选计划。这样一来，不健康分支既没有合法的目标 Venue、Range 和 `requiresSwap`，又会迫使实现者为不可执行状态构造无意义的 `planHash`，导致“返回占位计划”与“直接回滚”两种互斥语义并存。

修改：
- 从 `MarketRegime` 删除 Oracle 不健康成员；该枚举只保留 LOW、MEDIUM、HIGH 和 EXTREME 四种健康市场状态。
- Oracle 健康性仅由 `OracleSnapshot.healthy` 表达，不作为 Hysteresis 状态，也不写入 `lastCommittedRegime`。
- Vault 在调用 `getPlan()` 前检查 Oracle 快照；`healthy == false` 时以 `OracleUnhealthy()` 回滚且不得调用 Strategy。
- Strategy 若防御性地收到 `healthy == false` 的快照，也必须以 `OracleUnhealthy()` 回滚，不返回 `PositionPlan`，不计算 `planHash`。
- 该失败路径不得修改 `positionPlan`、`lastCommittedRegime`、`planVersion`、`lastPositionChangeAt` 或资产位置。
- `previewRebalance()` 使用同一规则；Redeem 和 Emergency Exit 不依赖 Strategy，仍按各自规则开放。

## 问题 16
角色系统的两个基础问题无规格：
ADMIN_ROLE/KEEPER_ROLE/GUARDIAN_ROLE 的标识与是否采用 OZ AccessControl 风格；
初始授权链——部署者是否自动成为 Admin、Guardian 能否由 Admin 授予/撤销 SPEC §2 未说 Guardian 的管理者是谁 。VaultRoles.sol 是规划文件但无内容契约。

> 已并入问题 6 统一处理：采用 OpenZeppelin Contracts v5 `AccessControlDefaultAdminRules`；`DEFAULT_ADMIN_ROLE` 作为唯一根角色，原业务 Admin 重命名为 `MANAGER_ROLE`。构造函数显式接收 `initialDefaultAdmin` 与 `initialDefaultAdminDelay`，根角色使用基类的单账户、两阶段延迟转移和延迟调整流程，Default Admin 不自动取得业务权限。

## 问题 17
"比例容差"没有参照系。三种候选基准对同一组 (amount0, amount1) 的接受/拒绝结果不同
只要求价值匹配 TWAP（宽松）；
要求能被目标仓位吸收（可能很严，V3 窄区间比例倾斜）；
要求价值对半。

> 原因：`bootstrapRatioToleranceBps` 与现有部署率检查重复，并且没有唯一、独立的比例语义。

修改：
- 删除 `bootstrapRatioToleranceBps` 的配置字段、immutable 存储与 Bootstrap 前置条件，并删除 `InvalidBootstrapRatio()`。
- LOW、MEDIUM 和 HIGH 继续以 `initialDeployBps >= minDeployBps` 作为唯一 Bootstrap 部署率要求，不满足时以 `SwapRequired()` 回滚。
- `EXTREME_DEVIATION` 进入 IDLE，不执行比例或部署率检查；仍要求初始 token0/token1 均大于零且 `NAV1 >= minimumInitialNav`。

## 问题 18
Bootstrap 前的治理状态未定义 谁可暂停未初始化 Vault；bootstrap 遇 depositPaused 的行为

> 已并入问题 6 统一处理：未初始化阶段不允许写暂停或 Adapter operational 状态，暂停位保持默认全 false，`bootstrap()` 不读取暂停状态；该阶段只开放 Manager 的 Adapter 配置与 Bootstrap，以及 Default Admin 的标准角色和根管理员管理入口。

## 问题 19
observe() 调用形状术语表与规范正文不一致
你的术语表描述为两次独立二元素 observe，规范正文定义为单次三元素调用。数学上等价 observe 纯读 ，但调用形状是接口契约的一部分 gas、错误路径、secondsAgos 数组构造 ，验收清单  明确以三元素形状为测试对象。

修改：
- 统一以单次 `observe([twapWindowSeconds, shortTwapWindowSeconds, 0])` 作为 canonical V3 Pool 的调用契约。
- 更新 `PRODUCT_SPEC.md` 术语表：TWAP 使用 `tickCumulatives[2] - tickCumulatives[0]`，Short TWAP 使用 `tickCumulatives[2] - tickCumulatives[1]`；规范正文、架构正文和验收清单保持一致。

## 问题 20
PAUSED 作为伪状态混入生命周期状态表，与自身声明矛盾
你在同一节内先用状态表把 PAUSED 表述为与 IDLE/ACTIVE 并列的生命周期状态 含进入/退出条件 ，两行后又声明它不是状态而是独立维度。ARCH 状态图与后一种读法一致。表内 "PAUSED 的退出条件" 健康门控恢复 还引入了"自动解除暂停"的暗示，与 §10.1 暂停只能由角色操作 或入口检查式自动门控 的语义混淆。

修改：
- 状态模型拆为三个独立维度：生命周期仅含 `UNINITIALIZED` 和已初始化的 `OPEN`；资产位置由 `activeVenue` 表达为 `IDLE` 或 `ACTIVE`；运行时控制包含三个暂停位和每个 Adapter 的 `enabled`。
- 删除 `PAUSED` 生命周期状态。暂停位只能由有权角色写入，自动门控不写暂停 storage；暂停位变化不得修改生命周期、资产位置、`planVersion` 或 `lastExecutedPlan`。
- `totalSupply() == minimumLockedShares` 只表示没有流通 shares，不改变 `OPEN` 生命周期，也不阻止后续按既定规则进行 Redeem、Rebalance 或 Deposit。
- 架构和产品文档分别描述生命周期、资产位置和暂停控制，并补充组合状态测试。

## 问题 21
narrow/wideRangeHalfWidth 的 "对齐 spacing" 校验对象未定义
半宽以通用 tick 数配置，但两个目标 V3 池的 tickSpacing 不同。 均可对齐 spacing 无法作为配置时校验这里对齐哪个？，只能在每次按目标池对齐时计算——参数表把它写成配置约束，实现者会尝试在 updateStrategyConfig 时校验并遇到歧义。

修改：
- 采用 spacing 步数语义，将 `narrowRangeHalfWidth` 和 `wideRangeHalfWidth` 重命名为 `narrowRangeHalfWidthSteps` 和 `wideRangeHalfWidthSteps`；它们分别表示低费率和高费率目标 Pool 的 spacing 间隔数量。
- Adapter 继续独立部署；`configureAdapter` 改为 `configureAdapter(VenueType venue, address adapter)`。Vault 从 Adapter 的 immutable 绑定读取并验证 Pool、Token、Fee Tier 和 `tickSpacing`，不再从调用者参数直接获取这些绑定值；spacing 不合法时以 `InvalidTickSpacing()` 回滚。
- `_adapterByVenue` 只缓存 Adapter 地址、`enabled` 和已验证的 `tickSpacing`；Pool 与 Fee Tier 继续由 Adapter 的 immutable binding 提供。Bootstrap 成功后 Adapter 身份和 spacing 缓存冻结，只有 `enabled` 可以改变。
- `lowHalfWidthTicks = narrowRangeHalfWidthSteps × lowFeeTickSpacing`，`highHalfWidthTicks = wideRangeHalfWidthSteps × highFeeTickSpacing`；LOW 和 MEDIUM 分别使用对应的有效半宽，且 Bootstrap 必须验证 `lowHalfWidthTicks < highHalfWidthTicks`。
- 对齐后的中心与有效半宽生成 Range；乘法溢出、非法 Tick 或超出 Uniswap V3 最小/最大 Tick 时回滚 `InvalidTickRange()`，不夹紧或移动目标中心。
- 原问题中关于 `updateStrategyConfig` 的假设不再适用；Range 步数是部署后不可修改的策略参数，涉及 spacing 的最终校验在 Adapter 配置和 Bootstrap 阶段完成。

## 问题 22
redeem 接口无 owner 参数，"获授权 spender"入口规则无法实现
入口规则表允许"获授权 spender"代持有人赎回，但接口没有 owner 参数——spender 调用时 Vault 无从得知应对谁的 shares 余额销毁、检查谁的授权。ERC-4626 的标准解法是 redeem(shares, receiver, owner) 三地址参数；本接口的 4 参数形状只能支持 msg.sender 即持有人自赎。声称的权限模型与接口形状矛盾。

修改：
- `IAdaptiveLPVault.redeem` 增加 `address owner`，形成 `redeem(shares, minAmount0Out, minAmount1Out, receiver, owner)`；`owner` 是被销毁 shares 的持有人，`msg.sender` 是实际调用者，`receiver` 是最终双资产接收者。
- `owner == msg.sender` 时执行持有人自赎；否则校验并消费 `allowance(owner, msg.sender)`，`type(uint256).max` allowance 按 ERC-20 语义保持不变；shares 始终从 `owner` 销毁，授权 spender 可以指定任意 `receiver`。
- 架构文档同步更新 `Redeem` 事件、ERC-20 余额/授权标准错误语义、赎回时序、不变量和集成测试要求；现有赎回数学、暂停/Oracle 门控和资产流不变。

## 问题 23
Deposit 实际数量 d0/d1 的推导算法未定义双侧 max 的截断与舍入路径不唯一
目标关系只给出比例约束（1 参数解族），加上两个上限后仍存在多条合法推导路径：锚定 token0 侧（d0 = min(max0, ⌊max1 × T0/T1⌋)，d1 = ⌊d0 × T1/T0⌋）、锚定 token1 侧（对称）、或按 f = min(max0/T0, max1/T1) 等比缩放再各自向下取整。在比例非整除的输入下，这些算法给出不同的 (d0, d1)（差异在最小单位量级），且均满足"误差仅来自舍入"的字面要求——但 sharesMinted 与 InvalidDepositRatio 的触发边界随之不同。同一用户输入在不同实现下获得不同 shares，存款定价的确定性与公平性依赖实现者选择。

> 原因：Deposit 的实际数量应匹配当前唯一 Active Position 的本金比例，而不是整个 Vault 的 `T0/T1`；双侧最大输入仍需要唯一的限制侧选择和整数舍入规则。

修改：
- 设当前 Active Position Snapshot 的 `p0 = principal0`、`p1 = principal1`，且 `p0 > 0`、`p1 > 0`。
- 当 `amount0Max × p1 <= amount1Max × p0` 时，取 `d0 = amount0Max`、`d1 = floor(amount0Max × p1 / p0)`。
- 否则取 `d1 = amount1Max`、`d0 = floor(amount1Max × p0 / p1)`。
- 乘除使用全精度 `mulDiv` 语义；`previewDeposit()` 与真实 `deposit()` 使用相同的公式和舍入路径。
- `d0`、`d1` 使用实际转入数量计算 shares；手续费不参与 Deposit 比例推导。

## 问题 24
"所有 AMM 操作包含最小输出和截止时间"与 bootstrap/deposit/Adapter 接口参数面不符

> 原因：原文把最小输出和 `deadline` 写成所有 AMM 操作的统一要求，但 Bootstrap、Deposit、Adapter 资产变更方法和 Emergency Exit 没有对应参数；Redeem 与 Swap 的保护也分别位于 Vault 最终交付和 Swap 执行路径。

修改：
- 在 `PRODUCT_SPEC.md` §11.3 明确适用范围：Redeem 仅校验最终用户双资产输出，Swap 校验 `protocolMinOut`、`keeperMinAmountOut` 和 `deadline`；Bootstrap、Deposit、Adapter 资产变更方法和 Emergency Exit 不暴露业务层 `minOut` 或 `deadline`。
- 将 `ARCHITECTURE.md` 测试矩阵中 Adapter 的“最小输出”改为实际退出数量与余额变化，并将 Redeem 最小输出测试归入 Deposit/Redeem 集成测试。

## 问题 25
Swap 接收地址二义性："Vault 或受控 Executor"未裁定，余额增量校验对象随之不明
Swap 输出接收方在"Vault"与"受控 Executor"两个选项间未裁定。若接收方是 Executor 输出 token 滞留 Executor，后续 Adapter 建仓需要 Executor→Vault 的二次转账（该流程、授权与清理均未定义），且"实际余额增量"应度量 Executor 余额；若接收方是 Vault：增量度量 Vault 余额，MATH §6 "带 Swap 路径的 Executor 实际余额增量满足 minAmountOut" 的表述指代错位（增量发生在 Vault 而非 Executor）。两种读法下的后置校验位置、资金流与授权模型均不同。

> 原因：架构曾局部写明输出接收方为 Vault，但产品流程、数学规范、输入资金交付和局部校验时点没有同步闭环。

修改：
- 以 `PRODUCT_SPEC.md` §9.4 作为业务事实来源：Vault 向固定 Executor 转入精确 `amountIn`，Router 输出固定发送到 Vault；Swap 后、Adapter 建仓前以 Vault 输出 Token 余额增量确定 `actualAmountOut`，并校验输入扣减、返回值、Executor 余额基线和 Router allowance。
- 在 `SWAP_REBALANE_MATH.md` §5—6 补齐对应余额公式，区分 Swap 局部校验与建仓后的完整迁移校验。
- `ARCHITECTURE.md` 只保留 Executor 的接口、存储和模块职责边界，并引用产品与数学规范；测试矩阵增加上述资产流和清理条件，不重复业务流程。

## 问题 26
 dustTolerance0/1 列于治理参数表但归入 ImmutableConfig，可更新性矛盾
dustTolerance0/1 出现在可由 Admin 更新的治理参数表中，但 ARCH 将其定义为不可变配置，两份文档对同一参数的可变性判定相反。且含混具有安全敏感性：守恒校验的容忍窗口若可治理调大，等于可放宽资产损失检查——与 自身声明的"不能用于放宽价值损失"冲突。

> 已并入问题 2 统一处理：删除可更新治理参数表、运行时参数更新入口及 `ParameterUpdated` 语义；`dustTolerance0/1` 作为 `VaultConfig` 构造输入分别写入 `immutable` 状态变量，部署后任何角色均不得修改。两者仅以 token0/token1 raw units 表示整数舍入、最小单位和 AMM 数学造成的微小容忍，不得通过治理调大以放宽资产守恒检查。

## 问题 27
IdleStateChanged 事件的触发点集合未定义

修改：
- 删除冗余的 `IdleStateChanged` 事件。
- `activeVenue` 的链下历史由动作事件完整覆盖：`VaultBootstrapped.initialVenue` 记录初始位置，成功的 `RebalanceExecuted.targetVenue` 记录 Rebalance 后位置，`EmergencyExit` 记录进入 `IDLE`。
- 同 Venue V3 Recenter 的 `previousVenue == targetVenue`，链下位置保持不变；已在 IDLE 的 Emergency Exit 不发出 `EmergencyExit`。
- Deposit、Redeem、费用同步、Donation、暂停和 Adapter 启停不改变 `activeVenue`，不需要额外的通用位置事件。

## 问题 28
治理参数更新后 positionPlan 陈旧且 planVersion 不递增，Deposit 继续按旧计划建仓

> 已并入问题 2 统一处理：将配置和策略参数改为部署时固定的 `immutable`，删除运行时参数更新入口及 `ParameterUpdated` 语义，因此不再存在治理参数更新后旧 `positionPlan` 继续执行的问题。若需使用不同参数，必须部署新的 Vault。

## 问题 29
token1Decimals > 18 无约束，份额锚定与取整粒度退化

修改：
- v1 同时要求 `token0Decimals <= 18` 和 `token1Decimals <= 18`。
- Vault 构造时读取两个 Token 的 `IERC20Metadata.decimals()`，配置值必须与链上返回值一致。
- 配置不一致或任一链上值大于 18 时，以 `InvalidTokenDecimals(token, configured, actual)` 拒绝部署，避免 `10^decimals` 无界和 Token 精度高于 18 位 shares 的额外粒度语义。

## 问题 30
单边实际存款为零时回滚错误未指定 ZeroAmount vs InvalidDepositRatio

修改：当 `activeVenue` 对应 V3 Adapter 且 Active Position 的 `principal0 == 0` 或 `principal1 == 0` 时，Deposit 前置检查以 `ActivePositionSingleSided()` 回滚。双边 Active Position 下，按 principal 比例计算后 `d0 == 0` 或 `d1 == 0` 时以 `ZeroAmount()` 回滚。

## 问题 31
Cooldown 与 Emergency Exit 的交互未显式对齐

修改：
- 普通 Rebalance 和带 Swap Rebalance 都必须满足同一 `minRebalanceCooldown`，未结束时以 `CooldownActive(availableAt)` 回滚。
- Emergency Exit 为保证紧急撤仓活性而跳过 Cooldown 检查，且不更新 `lastPositionChangeAt`，不会重新开始 Cooldown。
- Emergency Exit 后能否立即执行计划性 Rebalance，只取决于原有 `lastPositionChangeAt` 记录的 Cooldown 是否已经结束。
- 已在 IDLE 的幂等分支和失败交易不更新时间戳。

## 问题 32
ParameterUpdated 事件的参数转型语义未定义int24 参数与 bytes32 标识

> 已并入问题 2 统一处理：删除 `ParameterUpdated` 事件和参数更新路径，所有部署配置在部署时固定；运行时状态变化使用各自的类型化事件，因此不再需要定义 `int24` 参数或 `bytes32` 标识的通用转型语义。

## 问题 33
 OracleSnapshot.observedAt 与三个价格字段的标度/参考量未定义
价格字段未定义标度：是 1 raw unit token0 的 token1 报价、还是 10^token0Decimals（1 整个 token0）的报价、还是 X96 定点——三种标度在同一字段名下均可行；observedAt 无任何使用处与语义说明。另外 AssetSnapshot.nav1 在 Oracle 不健康时（无法计算 TWAP 报价）的取值（回滚？零？）也未定义。

## 问题 34
getAdapter(IDLE) 的返回值未定义

修改：
- 明确 `IDLE` 不代表 Adapter。
- Registry 的 Mapping Key 只允许三个非 IDLE Venue，`_adapterByVenue[IDLE]` 必须保持零值。
- `getAdapter(IDLE)` 固定返回 `address(0)`，`isEnterEnabled(IDLE)` 固定返回 `false`。

## 问题 35
继承式 Registry 与系统图/接口的部署语义不一致
你的Registry 是继承进 Vault 的内部模块 无独立地址、无跨合约调用 ，但系统图与 §6.5 的完整外部接口形状 含 seal() 等入口 均按独立合约表达。图示的调用边在继承式实现中不存在；IAdapterRegistry 若仅由 Vault 自身实现，其接口语义 外部可调用性、权限边界 需重新说明。

> 已并入问题 3 和问题 6 统一处理：`AdapterRegistry` 作为 `AdaptiveLPVault` 的继承式内部模块，`IAdapterRegistry` ABI 由 Vault 自身实现；系统图改为 Vault 直接连接 Adapter，删除独立 Registry、`seal()`/`sealed()` 及相关接口和事件，Bootstrap 成功时由 `initialized = true` 冻结身份字段。

## 问题 36
紧急退出"关闭 Deposit 和 Rebalance"的实现机制歧义
"关闭 Deposit 和 Rebalance"未说明是通过写入暂停位（depositPaused/plainRebalancePaused/swapRebalancePaused = true）实现，还是仅依赖 IDLE 状态自身的门控。若写暂停位：紧急退出产生未声明的暂停副作用，且后续 IDLE→ACTIVE 恢复 rebalance 前需要角色先解除暂停（额外恢复步骤未写入任何流程）；若不写：步骤 6 的"关闭"对 Deposit 是冗余描述（已由 IDLE 门控）。两种读法行为不同。

> 已随问题 6 解决：Emergency Exit 成功后显式将三个暂停位全部设为 true，暂停 storage 实际变化时发出 `PauseStateChanged`；后续恢复必须由 Manager 通过 `setPauseState` 显式解除所需暂停位。

## 问题 37
Executor 在你的文档中被要求"验证计划哈希"，但它不接触 Strategy、不存储任何计划记录，也没有可对照的真值源——该哈希在 Executor 侧无法被有意义地验证 至多做非零检查，与"验证"语义不符 。真正有效的哈希校验发生在 Vault 侧（expectedPlanHash vs 重新生成计划）；Executor 侧的这条要求无实现语义。

## 问题 38
lastSuccessfulRebalanceAt 在 Bootstrap 成功时是否设置未定义

修改：
- 将该字段重命名为 `lastPositionChangeAt`，初始值为 `0`。
- Bootstrap 成功时写入当前 `block.timestamp`。
- 两类 Rebalance 成功时更新；Emergency Exit 不更新。
- 该字段用于记录最近一次参与 Cooldown 计时的成功 Bootstrap 或计划性 Rebalance，因此 Bootstrap 后首次 Rebalance 也必须等待 Cooldown。

## 问题 39
Adapter withdraw 最小输出与用户 redeem 最小输出的映射规则未定义

> 已并入问题 5 统一处理：`IPositionAdapter.withdraw` 已删除 `minAmount0/minAmount1`，因此不再把用户的最终最小输出映射或透传给 Adapter。`redeem` 的 `minAmount0Out/minAmount1Out` 名称和接口保持不变；Vault 先合并按比例退出的 Position 资产与用户对应的 Idle 资产，得到最终 `amount0Out/amount1Out`，再统一执行最小输出校验。`withdrawAll()` 同样改为无参数完整退出。

## 问题 40
spotTick 声明的"安全检查 / Swap 风控"用途无实现

## 问题 41
getPlan 生成计划的 version 取值规则未定义

> 已并入问题 4 统一处理：`planVersion` 初始为 0，候选 `PositionPlan.version` 必须等于当前 `planVersion + 1`；成功的 Position 结构变化提交候选版本或将现有版本递增 1，失败交易和非结构变化不更新。

看一下这些问题 处理一下 完事之后可以 再找我
