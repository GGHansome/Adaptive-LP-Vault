# 集成测试函数目录

本目录按测试函数说明“先做什么，再检查什么”。共 6 个测试文件、32 个测试函数，按函数在源码中的定义位置列出；继承的函数不重复列出，初始化和辅助函数也不计入。部分测试会用四种 Token 精度组合重复执行，因此 Foundry 实际执行 44 个测试实例；随机输入测试的每次采样不单独计数。

## 先了解几个名称

- Vault 是资金库；用户存入资产后获得 shares（份额），赎回时销毁份额、取回对应资产。
- Control 管理角色、暂停开关和适配器注册；Adapter（适配器）负责连接具体的 Uniswap 池。
- Manager 是业务管理人，Guardian 是可暂停和紧急退出的守护角色，Keeper 是可执行换币迁移的角色；根管理员负责角色管理，不自动获得这些业务权限。
- token0、token1 是按地址排序的两种资产。下文的“手续费”是提供流动性赚到的交易手续费，“领取手续费”是把它从协议转回 Vault。
- V2 用 LP 代币表示流动性权益；V3 用 NFT 表示仓位。低费率 V3 池的手续费率是 0.05%，高费率池是 0.3%。
- IDLE 表示资产直接留在 Vault、不投入池子；Venue 表示当前使用哪个池或处于 IDLE；Regime 表示策略判断的市场状态。
- NAV 是按测试定价规则算出的净资产价值；TWAP 是一段时间内的加权平均价格；Tick 是 Uniswap V3 表示价格的位置编号。
- “原始单位”是 Token 的最小计数单位。例如，6 位精度 Token 的 1 个原始单位是 0.000001 枚。“容差”是测试允许的取整误差，不是任意亏损额度。
- `testFuzz` 表示使用随机输入重复测试。“回滚”表示整笔调用失败，调用中已发生的转账和状态修改也一起撤销。

以下文件路径均相对于 `test/`。协议版本、依赖安装和运行命令见 [集成测试说明](README.md)。新增、删除或改变测试检查内容时，应同步更新本文。

## `integration/DeploymentLifecycle.t.sol`（3）

使用项目生产合约和本地部署的官方 Uniswap 合约，测试部署、配置后的业务流程；不直接运行部署脚本。

- `test_deployConfigureBootstrapAndFirstUserRoundTrip`：先检查 Control、换币执行器、预言机和仓位管理器是否绑定正确，以及真实预言机初始数据是否健康。再从未初始化、没有份额的状态开始，依次完成低费率 V3 初始化、用户首次存入和赎回、迁入高费率 V3、管理人部分赎回；核对初始化发行的总份额和永久锁定份额。
- `test_bootstrapFreezesIdentityConfiguration`：完成初始化后，尝试重新配置适配器和再次初始化，两者都应被拒绝；资产记录仍应正确。
- `test_rolesRemainSeparatedAcrossBusinessLifecycle`：根管理员只有根角色时不能代替 Manager 初始化。Guardian 暂停、Manager 解除暂停后，用户可以继续存款；普通迁移可以完成，Guardian 紧急退出后用户也可以赎回。

## `integration/DepositRedeem.t.sol`（6）

前四个函数定义在抽象基类 `DepositRedeemScenarios` 中，分别用 18/18、6/18、18/6、6/6 位 Token 精度执行。后两个函数只在默认 18/18 位环境执行。因此本文件共执行 18 个测试实例，并不是六个场景都测试了四种精度。

- `test_multiUserRoundTripV2`：在真实 V2 仓位中，让两个用户分别设置两种 Token 的存入上限，再部分赎回、赎回全部可流通份额。检查每种 Token 的存入与取回差额都不超过 20 个原始单位；最后仍留有永久锁定份额及其对应资产，而且新用户还能再次存入和赎回。
- `test_multiUserRoundTripLowFeeV3`：换成低费率 V3 仓位，重复上述流程；检查由哪一种 Token 的上限限制实际存入量、部分和全部赎回，以及只剩锁定份额后能否再次存入和赎回。
- `test_multiUserRoundTripHighFeeV3`：换成高费率 V3 仓位，重复上述存入、赎回流程；检查真实 V3 计算结果，以及只剩锁定份额后仍能继续使用。
- `test_separatePayerShareOwnerOperatorAndAssetReceiver`：让付款人、份额持有人、代赎人和收款人分别使用不同地址。检查付款人不会自动获得份额；两次代赎准确扣减有限授权；最终用户份额和授权都用完，两种 Token 都到达指定收款人。
- `test_depositAndRedeemEventsMatchActualTransfers`：在 V2 存款时，独立计算付款人、份额接收人、两种 Token 的实际输入和份额，核对事件。赎回时先记录实际到账，再恢复测试检查点并重做同一次赎回，确认事件金额与真实转账相同。
- `testFuzz_depositRedeemAcrossRealVenues`：随机选择 V2、低费率 V3 或高费率 V3，并随机生成 `seed / 1000` 至 `seed * 5` 的双侧等量原始输入。完成存入和赎回后，检查每种 Token 的差额都不超过 20 个原始单位。

## `integration/FeeAccounting.t.sol`（6）

V3 手续费通过真实 Router 双向交易产生，V2 收益通过真实 Pair 交易产生；测试不会直接修改协议中的费用记录。

- `test_realV3FeesArePricedBeforeNewSharesAndPaidOnRedemption`：先让低费率 V3 仓位赚到 token0 和 token1 手续费，再让新用户存款。检查计算新用户份额时已计入这些收益，因此发放的份额少于“忽略手续费、只算本金”的结果，避免新用户分走原持有人已有的收益。领取后待领手续费应为零，仓位 NFT 不变；原用户和新用户都能赎回；没有新交易时，再次存款不会把同一笔手续费重复记入。
- `test_realHighFeeV3FeesArePricedBeforeNewSharesAndPaidOnRedemption`：在高费率 V3 池重复上述测试：两种 Token 的手续费都计入新用户的买入价格，领取后不重复记账，用户仍能赎回。
- `test_realV3FeesAreCollectedAndOldNftBurnedDuringMigration`：低费率 V3 仓位赚到手续费后，迁入高费率 V3。检查旧仓位的 NFT 已销毁，新仓位仍能正常存入和赎回。
- `test_redeemSlippageRestoresRealFeeCollectionLiquidityAndAllowance`：让代赎人设置过高的最低到账量，使带手续费的赎回失败。检查已领取的费用、仓位、Vault 资产记录、总份额、用户份额、原池的两种 Token 余额和代赎授权都恢复到调用前。降低最低到账要求后重试，应成功并用完授权。
- `test_realV2TradingFeesIncreaseLpEquityWithoutSeparateFeeClaims`：在 V2 池做双向交易后，检查 Vault 持有 LP 对应的资产增加，但“待领手续费”字段仍为零，因为 V2 收益已经包含在 LP 权益里。新老用户仍能存入和赎回；迁入 V3 后，V2 LP 应全部退出。
- `test_nonActiveLpDonationIsRecognizedOnlyWhenV2IsActivated`：Vault 正在使用高费率 V3 时，向尚未使用的 V2 适配器捐入 LP，检查它暂不影响用户份额定价。切换到 V2 后，这笔捐赠才计入总资产：两种资产增加，总份额不增加，之后仍可存入和赎回。这里本来就应新增计价资产，因此不要求迁移前后资产近似相等。

## `integration/Rebalance.t.sol`（4）

多数策略切换通过测试指定预言机返回值来触发；旧仓退出和新仓创建仍由真实协议执行。

- `test_fullStrategyCycleAcrossAllVenuesAndBack`：依次经过低费率 V3、高费率 V3、V2、IDLE，再按相反顺序回到低费率 V3。每次离开 V3 都检查旧 NFT 已销毁；在 IDLE 时资产只留在 Vault；整个过程不改变用户份额，最后用户可以赎回。
- `test_previewThenAnotherExecutionMakesOldPlanStale`：一个调用者先执行预览得到的计划，另一个调用者再提交旧计划哈希时应失败。检查失败不改变资产、历史计划和版本；重新预览后可以继续迁移。
- `test_bothRebalanceEntrypointsRespectSharedCooldown`：完成一次普通迁移后，立即调用普通迁移和 Keeper 换币迁移，两者都应因同一个冷却期未结束而失败；等冷却期结束后，普通迁移可以成功。
- `test_realPriceMoveCanRecenterSameV3VenueAndClearOldNft`：先通过真实交易把低费率池价格推到旧区间之外，再把实际 Tick 传给受控预言机，并补足新区间所需的两种 Token。检查同一池内生成位置更高的新区间和新 NFT、旧 NFT 销毁，两种资产的前后差额在容差内。此用例只验证区间重建，不验证自动换币配比，也不模拟 TWAP 自然变化。

## `integration/SwapRebalance.t.sol`（8）

四个成功场景都先捐入一种 Token，故意造成资产比例不合适，再用真实预览确认换币方向。执行后，直接读取独立换币池的余额变化，核对实际花掉多少、换回多少；同时检查两种资产变化、用户份额不变、最终净值不低于允许下限、版本和完整历史计划正确，之后还能存入和赎回。Keeper 将最低到账要求从协议报价的 98% 提高到 98.5%；换币池手续费率为 1%。

- `test_swapToken0ToToken1AndMigrateIntoV3`：把 token0 换成 token1，再从低费率 V3 迁入高费率 V3，完成上述换币、资产和份额检查。
- `test_swapToken1ToToken0AndMigrateIntoV3`：把 token1 换成 token0，再迁入高费率 V3；按相反的资产增减方向核对结果。
- `test_swapToken0ToToken1AndMigrateIntoV2`：把 token0 换成 token1，再从高费率 V3 迁入 V2；检查实际获得 LP，之后仍能存入和赎回。
- `test_swapToken1ToToken0AndMigrateIntoV2`：把 token1 换成 token0，再迁入 V2；核对实际输入、输出和最终 LP 对应资产。
- `test_routerSlippageRevertsOldPositionAndEveryBalance`：把 token0 换 token1 的最低到账量设为输入量。真实 Router 因手续费和价格影响无法满足要求，整笔调用应失败；检查所记录状态全部恢复。放宽最低到账要求后，用同一个计划重试应成功。
- `test_reverseRouterSlippageRevertsOldPositionAndEveryBalance`：在 token1 换 token0 的方向重复上述失败、状态恢复和重试检查。
- `test_targetMintFailureRollsBackAnExecutedRealSwapAndAllowsRetry`：只让目标高费率池的 `mint()` 建仓调用失败，并确认此前确实调用过真实 Router。检查最终失败连同旧仓退出、已完成换币的可观察变化一起撤销；解除故障后重试应成功。
- `test_publicCallerCannotExecuteKeeperSwapButCanRedeemAfterFailure`：普通用户调用换币迁移应因没有 Keeper 权限而失败，已记录状态不变；之后管理人仍能把自己的份额赎回给指定收款人。

失败前后比较的状态包括：参与合约和池的两种 Token 余额、三种仓位快照、历史计划、版本、上次迁移时间、管理人份额、总供应量、V2 LP 和储备、换币池价格、Tick、费用增长及 Router 临时授权。测试只证明这些字段恢复，不代表比较了 EVM 的全部存储。

## `integration/EmergencyRecovery.t.sol`（5）

前三个函数使用同一流程：先禁用当前适配器、暂停三个入口，并让预言机读取直接失败；Guardian 仍应能在冷却期内把仓位全部退出到 IDLE。检查资产前后差额在允许范围内、用户份额不变、版本只增加一次、历史计划和上次迁移时间不变，三个入口保持暂停，用户仍可赎回。再次紧急退出应不发事件、资产不变。最后修复预言机、启用适配器、解除暂停，检查能重新建仓、存入和赎回。

- `test_lowFeeV3EmergencyExitRedeemAndRecovery`：先让低费率 V3 仓位赚到真实交易手续费，再执行上述故障、退出、重复退出和恢复流程。
- `test_highFeeV3EmergencyExitRedeemAndRecovery`：换成高费率 V3 仓位，带着真实手续费执行同一流程。
- `test_v2EmergencyExitRedeemAndRecovery`：持有真实 V2 LP 时执行同一流程；这个分支不额外做交易来产生手续费。
- `test_realOracleNormalizesObservationFailureWhileExitPathsRemainOpen`：只让参考池的 `observe()` 历史读取失败。检查生产预言机返回“不健康”快照，存款和迁移预览被阻止，但用户仍能从真实仓位赎回，Guardian 仍能紧急退出；解除故障后预言机恢复健康。
- `test_idleBootstrapCanRedeemThenActivateV2`：初始化时选择 IDLE，管理人先赎回一部分份额，再把资产投入 V2；检查此后用户仍能存入和赎回。

## 共用检查与覆盖限制

- `helpers/IntegrationTestFixture.sol` 的 `_deposit()` 检查用户实际扣款、增加的份额，以及按存入前净值计算的份额是否准确。`_redeem()` 检查实际到账、持有人和总份额的减少量；涉及每种资产的按份额分配和前后总量时，允许明确的原始单位取整误差。`_plain()` 检查普通迁移前后每种 Token 总量、版本、完整计划、时间戳和当前仓位。
- 这些辅助函数共用 `test/helpers/LocalUniswapFixture.sol` 部署真实协议并做基础资产检查。部分预期金额是根据操作前快照计算的；这不同于不变量测试直接读取协议状态、独立重算资产的参考模型。
- 多数场景使用 TWAP Tick 为零的价格，净值直接按两种 Token 的原始数量相加。混合精度测试检查单位换算和份额精度处理，不代表两种 Token 每整枚的市场价格相同。
- 普通策略切换只控制预言机 `snapshot()` 的输入，不替换适配器、仓位管理器或 Router。个别故障场景会故意让指定调用失败，已在各用例中说明；这些测试不证明真实市场一定会出现相同的状态变化。
- 本目录测试的是本地官方协议合约与项目合约一起工作时的行为，不覆盖主网真实地址、已有池深度和历史、部署脚本、非标准 Token、原生 ETH 或 NFT 元数据。长随机操作序列见 [不变量测试函数目录](../../invariant/docs/INVARIANT_TEST_REVIEW.md)。
