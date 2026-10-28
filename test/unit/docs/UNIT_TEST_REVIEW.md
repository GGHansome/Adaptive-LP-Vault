# 单元测试函数目录

本文逐函数说明“什么情况下执行什么操作，以及应得到什么结果”。共 20 个文件、344 个测试函数，按源码定义位置列出；继承的函数不重复列出，初始化和辅助函数不计入。

## 先了解几个名称

- Vault 是资金库；用户存入资产后获得 shares（份额），赎回时销毁份额、取回对应资产。永久锁定份额不会被普通用户赎回。
- Control 管理角色、暂停和适配器注册；Adapter（适配器）连接具体协议；Router 执行换币；Oracle（预言机）提供价格和健康状态。
- Manager 是业务管理人，Guardian 可收紧控制和紧急退出，Keeper 可执行换币迁移；根管理员负责角色管理，不自动拥有这些业务权限。
- token0、token1 是按地址排序的两种资产。V2 的 Pair、V3 的 Pool 都是交易池；Factory 是创建、登记池子的工厂。
- V2 的 LP 代币代表流动性权益；V3 的 NFT 代表仓位，Position Manager 是管理 NFT 仓位的合约。V3 的 liquidity 是协议内部的仓位大小，不等于 Token 数量。
- IDLE 表示资产直接留在 Vault、不投入池子；Venue 表示使用哪个池或处于 IDLE；Regime 表示策略判断的市场状态。
- NAV 是按预言机价格计算的净资产价值；TWAP 是一段时间内的加权平均价格；Tick 是 V3 的价格位置编号，区间边界须按对应 Tick 间距对齐。
- “本金”是仓位中的资产，不含另外记录的待领手续费；“领取/归集手续费”是把已赚到的交易手续费转回 Vault。闲置资产是留在 Vault、尚未投入池子的资产；部署率是投入仓位的资产价值占总价值的比例。
- “原始单位”是 Token 的最小计数单位；“微量容差”是允许的极小取整差额。BPS 是基点，10000 基点等于 100%。
- “回滚”表示整笔调用失败，并撤销其中已发生的转账和状态修改。“回调”是外部合约在执行中再次调用其他合约；“重入”是借回调再次进入尚未结束的资产操作。
- “余额基线”指操作前已有的余额；要求恢复基线，表示不能留下本次操作新增的 Token。“快照”是某一时刻读取的一组资产或价格数据。
- 测试替身（Mock）用来人为指定依赖的行为；`testFuzz` 使用随机输入重复测试，`testGas` 测量 Gas（链上执行资源）消耗。下文写“检查”，指测试中的断言，不代表所有测试都连接真实 Uniswap。

## `unit/AdaptiveLPVault.t.sol`（17）

- `test_bootstrapOnlyManagerAndOnlyOnce`：只有 Manager 能初始化，成功后不能再次初始化；同时检查永久锁定份额数量。
- `testFuzz_bootstrapCommitsEachInitialRegime`：分别以四种市场状态首次初始化，检查选择的资产位置和保存的计划正确。
- `test_bootstrapSwapRequiredRollsBackAllState`：初始资产比例需要先换币时，初始化应失败；资产和状态都恢复到调用前。
- `test_depositUsesPrincipalRatioForBothLimitingSides`：分别让 token0、token1 的存款上限成为限制，检查实际输入按仓位本金比例计算并正确取整；额外捐赠不能改变这个比例。
- `test_depositMinSharesAndSeparateReceiver`：检查用户设置的最低份额要求是否生效，份额可发给不同于付款人的地址，存款事件也记录正确。
- `test_redeemOwnerDoesNotSpendSelfAllowance`：持有人赎回自己的份额时，不扣减他给自己设置的授权。
- `test_redeemFiniteAllowanceAndDistinctParties`：调用者、份额持有人和收款人不同时，检查代赎到账、有限授权扣减和事件都正确。
- `test_redeemInfiniteAllowanceIsNotDecremented`：使用无限授权代赎时，授权值保持不变。
- `test_redeemRejectsInsufficientAllowanceOrBalanceBeforeFees`：份额余额或代赎授权不足时，应在领取手续费之前拒绝赎回。
- `test_redeemSlippageRestoresAllowanceSharesAndPosition`：任一种 Token 达不到用户设置的最低到账量时，赎回应失败，授权、份额和仓位全部恢复。
- `test_idleRedeemNeverCallsAdaptersOrOracle`：IDLE 时赎回只分配 Vault 直接持有的资产，不调用适配器或预言机。
- `test_idleRedeemAllowsOneOrBothOutputsToRoundToZero`：IDLE 赎回量很小时，允许一种或两种 Token 的输出取整为零，前提是用户的最低到账要求允许。
- `testFuzz_allCirculatingSharesRedeemedPreservesLifecycleAndPlan`：在 V2、V3、IDLE 中赎回全部可流通份额后，检查永久锁定资产和计划仍保留，之后仍可继续操作。
- `test_redeemV2UsesNestedLpRounding`：V2 赎回先向下取整应退出多少 LP，再据此计算取回多少 Token，不能省略第一步取整。
- `test_redeemSlippageRestoresSynchronizedFeesAndAllowance`：手续费已经领取、授权已经扣减后，赎回仍可能因最低到账量不满足而失败；检查这些修改全部撤销，调整要求后重试可成功。
- `test_vaultBlocksAllAssetEntrypointReentryDuringBootstrap`：初始化建仓时让外部合约回调，尝试再次进入六个资产入口，全部应被拒绝。
- `test_vaultBlocksAllAssetEntrypointReentryDuringDeposit`：存款建仓时重复上述六种重入尝试，全部应被拒绝。

## `unit/AdaptiveLPVaultAssessment.t.sol`（24）

- `test_constructorReportsInvalidControlBinding`：组件工厂没有返回 Control 地址时，创建 Vault 应失败，并报告控制组件绑定错误。
- `test_constructorReportsInvalidExecutorBinding`：Control 正确但换币执行器为空时，创建 Vault 应失败，并报告执行器绑定错误。
- `test_constructorReportsOracleTokenDecimalsMismatch`：预言机记录的 token0 精度与 Token 实际精度不同时，错误应指出对应 Token 和精度。
- `test_constructorReportsToken1DecimalsMismatch`：对 token1 重复精度不一致检查，确认错误信息指向 token1。
- `test_planUsesConstructorPackedStrategyAndPreservesPublicConfig`：生成计划时使用构造阶段打包保存的策略参数；对外查询的配置仍与原始参数一致。
- `test_minDeployBpsIsDerivedAtConstruction`：创建合约时，根据允许的最大闲置比例，正确算出最低资产投入比例。
- `test_minDeployBpsAtConfigurationBounds`：最大闲置比例设为 0 或 9999 基点时，最低投入比例应分别为 10000 或 1 基点。
- `test_constructorRejectsIdleLimitAtOrAboveBps`：最大闲置比例达到或超过 10000 基点时，拒绝创建合约。
- `test_previewAtDeploymentThresholdUsesSingleAdapterPreviewWithoutUnusedValuation`：预计投入比例恰好达标时，应判定无需换币；适配器只预览一次，不再为剩余资产做无用估值。
- `test_fullDeploymentNeedsNoSwap`：资产全部可以投入仓位时，预览应返回无需换币，方向为无。
- `test_belowDeploymentThresholdReportsSwapRequiredWithoutRevertingPreview`：预计投入比例不达标时，预览应正常返回“需要换币”和方向，而不是直接失败。
- `test_dustDoesNotExemptMinimumDeploymentRatio`：即使剩余资产很少、在微量容差内，最低投入比例仍必须达标。
- `test_deploymentUsesRoundedDeployedValueRatherThanComplementOfIdle`：投入比例应由实际投入价值独立计算并取整，不能直接用 100% 减去已取整的闲置比例。
- `test_minimumDeploymentRatioRemainsStricterThanRoundedIdleLimit`：构造闲置比例取整后看似达标、实际投入比例却不足的情况，检查仍判定需要换币。
- `test_zeroNavRequiresSwapWithoutDividingByZero`：总净值为零时，返回需要换币，不触发除零错误。
- `test_idlePlanNeedsNoSwapWithoutAdapterOrValuationQueries`：目标是 IDLE 时直接返回无需换币，不查询适配器或估值接口。
- `testFuzz_minimumDeploymentRatioImpliesIdleLimit`：使用随机金额检查：只要最低投入比例达标，闲置比例就不会超限。
- `test_disabledTargetStillRevertsBeforePreview`：目标适配器被禁用时，在调用它的预览函数之前就拒绝操作。
- `test_adapterOveruseStillReverts`：适配器预览声称要使用超过任一种 Token 输入上限的金额时，应失败。
- `test_invalidPreviewRevertsBeforeOracleValuation`：预览报告超额使用，或两种 Token 都明显有剩余时，在调用预言机估值之前拒绝。
- `test_bothExcessTokensStillRevert`：两种 Token 的剩余都超过各自微量容差时，应拒绝该预览。
- `test_simulatedDeploymentStillChecksRatioBeforeOppositeDirection`：按最低允许成交量模拟后，若投入比例不足且剩余资产方向也反转，应优先报告投入比例不足。
- `test_simulatedDeploymentStillRejectsOppositeDirection`：模拟投入比例已达标，但换币后剩余资产方向反转时，仍应因换币过量而拒绝。
- `test_healthySimulatedDeploymentReachesSwapExecution`：最低允许成交量的模拟通过所有检查后，应继续调用换币执行器。

## `unit/AdaptiveLPVaultBootstrapBounds.t.sol`（5）

- `test_bootstrapMinimumNavOneBelowBoundaryRevertsAcrossPrecisions`：在 18/18、6/18、18/6、6/6 四种精度组合下，初始净值比最低要求少一个单位时，初始化应完整失败并撤销修改。
- `test_bootstrapMinimumNavExactBoundaryMintsExpectedSharesAcrossPrecisions`：四种精度组合下，初始净值恰好达标时，检查份额换算、锁定量、接收人和初始化事件正确。
- `test_bootstrapGrossSharesEqualLockedRevertsAcrossPrecisions`：初始总份额恰好只够永久锁定、没有剩余给接收人时，应拒绝初始化；资产、授权和状态不变。
- `test_bootstrapGrossSharesOneAboveLockedSucceedsAcrossPrecisions`：初始总份额比锁定量多一个最小份额单位时，应成功，接收人获得这一单位。
- `testFuzz_bootstrapScalesFractionalRawAmounts`：随机生成原始输入金额和 6/18 位精度，按独立公式核对估值取整与初始份额换算。

## `unit/AdaptiveLPVaultCallbackSafety.t.sol`（12）

使用生产 Vault、Control 和换币执行器，其他依赖由能实际转账的测试替身提供。每个重入场景都会尝试六个资产入口，并检查返回规定的重入保护错误。

- `test_bootstrapTokenTransfersBlockAllAssetEntrypoints`：初始化时，分别在两种 Token 转入的回调中尝试重入，全部应失败；正常资产转入、锁定份额和初始化结果仍正确。
- `test_depositUserAndAdapterTokenPullsBlockAllAssetEntrypoints`：分别在用户转入 Vault、Vault 转入适配器两个阶段，让两种 Token 回调尝试重入；全部应被拒绝，正常转账的有限授权仍正确扣减。
- `test_feeTransferCallbacksBlockAllAssetEntrypoints`：在存款、赎回、普通迁移、换币迁移和紧急退出中，领取任一种 Token 手续费时的回调都不能重入。
- `test_partialWithdrawalCallbackBlocksAllAssetEntrypoints`：部分赎回调用适配器退出时，回调不能重入；回调发生时份额还未销毁，最终到账仍应正确。
- `test_fullExitCallbacksBlockAllAssetEntrypoints`：普通迁移、换币迁移和紧急退出全部退出旧仓时，回调都不能重入。
- `test_exitTokenTransfersBlockAllAssetEntrypoints`：部分赎回及三类完整退出，把任一种 Token 转回 Vault 时，Token 回调都不能重入。
- `test_routerCallbacksBlockAllAssetEntrypointsInBothDirections`：两个换币方向中，在 Router 已拿走输入、尚未交付输出时尝试重入，应被拒绝；最终余额和授权仍正确。
- `test_swapInputRouterPullAndOutputCallbacksBlockAllAssetEntrypoints`：两个换币方向中，分别在 Vault 把输入交给执行器、Router 拿走输入、输出转入 Vault 三个阶段尝试重入，均应被拒绝。
- `test_receiverTransferCallbacksObserveBurnedSharesAndBlockReentry`：赎回把任一种 Token 转给收款人时，回调应看到份额已经销毁，不能再次重入；收款人实际到账正确。
- `test_revertingReceiverTransferRestoresFeesBurnAndSpentAllowance`：向收款人转账时故意失败，检查此前的费用领取、仓位退出、份额销毁和代赎授权扣减全部撤销。
- `test_postSwapFailureRestoresStateAfterAllReentryAttempts`：Router 回调中的六种重入都被拒绝后，再让最终资产总量检查失败；余额、仓位、授权和计划仍须全部恢复。
- `test_guardReleasesAfterReceiverCallbackAndAllowsLaterRedemption`：正常收款回调结束后，重入保护锁应释放；下一笔独立赎回仍能成功。

## `unit/AdaptiveLPVaultControl.t.sol`（7）

- `testFuzz_threePauseFlagsGateOnlyTheirOwnEntrypoints`：检查三个暂停开关的八种组合；每个开关只限制自己的入口，预览和退出仍可使用。
- `test_oracleUnhealthyBlocksValueSensitiveOperationsButAllowsExit`：预言机返回不健康数据时，依赖价格的操作应被阻止；无论不健康还是调用直接失败，用户仍能退出。
- `test_disabledActiveAdapterBlocksDepositBeforeFeesButAllowsAccountingAndExit`：当前适配器禁用后，存款应在领取费用前失败；但资产查询、赎回和迁出仍可执行。
- `test_disabledTargetBlocksPreviewPlainAndSwapBeforeExit`：目标适配器禁用时，预览、普通迁移和换币迁移都应失败，且不会先退出旧仓。
- `test_redeemIgnoresSingleSidedPrincipalHighIdleAndDisabledAdapter`：即使本金只剩一种 Token、闲置比例过高、适配器禁用、入口暂停和预言机故障同时存在，用户仍能赎回。
- `test_idleEmergencyExitIsStrictlyIdempotent`：IDLE 时紧急退出不调用适配器、不修改历史计划；首次调用只设置全部暂停，之后重复调用不再发事件或改变状态。
- `test_rootHasNoImplicitBusinessPrivilegesAndRevocationIsImmediate`：检查根管理员不能自动使用业务权限，普通迁移允许公开调用，Guardian 可以紧急退出；业务角色撤销后立即失去对应权限。

## `unit/AdaptiveLPVaultDonations.t.sol`（38）

名称含 `WhenPreviewIsMocked` 或 `WhenSimulatedPreviewIsMocked` 的用例，会人为修改预览返回值，只验证流程末尾的投入比例检查。它们不代表相同资金比例在正常预览下也能迁移成功。正常预览会拒绝的情况，以及调整换币金额后成功的情况，另有用例检查。

- `test_bootstrapV3IgnoresPreexistingV2Donation`：初始化选择 V3 时，不把未使用的 V2 适配器已有 LP 捐赠计入资产。
- `test_bootstrapIdleIgnoresPreexistingV2DonationAndRedeemsOnlyIdle`：初始化选择 IDLE 时，也不计入 V2 LP 捐赠；赎回只分配 Vault 直接持币。
- `test_bootstrapV2RecognizesDonationWithoutMintingExtraShares`：初始化选择 V2 时，已有 LP 捐赠会计入资产，但不会因此多发初始份额。
- `test_bootstrapStillRejectsManagedV3Position`：已经存在由适配器管理的 V3 仓位时，即使另有 V2 捐赠，也不能重新初始化。
- `test_nonActiveV2DonationDoesNotAffectDepositPricingOrRedeem`：正在使用 V3 时，向未使用的 V2 适配器捐 LP，不应改变新用户份额价格或用户赎回结果。
- `test_nonActiveV2DonationDoesNotBlockV3MigrationOrIdle`：未使用的 V2 适配器收到 LP 捐赠，不妨碍 V3 迁移或退出到 IDLE；直到切换到 V2 才计入资产。
- `test_nonActiveV2DonationDoesNotBlockEmergencyExitAndRemainsUnrecognized`：V3 紧急退出不计入未使用的 V2 LP 捐赠；退出后全部入口暂停，再次退出不增加版本。
- `test_nonActiveManagedV3PositionStillBlocksDeposit`：未被选为当前仓位的 V3 适配器如果仍有受管理仓位，存款应因“只能有一个活跃仓位”而失败。
- `test_plainActivationRecognizesDonationAndEventIncludesFullAssets`：普通迁移切换到 V2 后，已有 LP 捐赠计入总资产，迁移事件金额也应包含它。
- `test_usersEnteringBeforeActivationShareDonationAndLaterDepositsAreFair`：切换到 V2 前持有份额的用户，共享切换时计入的捐赠收益；之后入金的用户按已增加的净值获得份额，不能低价分走已有收益。
- `test_activeV2DonationIsImmediatelyRecognizedAndExitedOnMigration`：当前使用 V2 时，新收到的 LP 捐赠立即计入资产，迁出 V2 时连同原 LP 一起全部退出。
- `test_emergencyExitFromV2ClearsRecognizedDonations`：V2 紧急退出时，包括已计入资产的捐赠在内，所有 LP 都应清空。
- `test_idleActivationRecognizesDonation`：从 IDLE 切换到 V2 时，此前未计入份额价格的 LP 捐赠应开始计入资产。
- `test_swapActivationRecognizesDonationWithoutCorruptingAccountingSnapshot`：把 token0 换成 token1 并迁入 V2 后，资产快照和 LP 余额都应正确包含已有捐赠。
- `test_donationCanOffsetExcessiveSwapMigrationLossAndMigrationSucceeds`：换币本身损失较大，但新增计价的捐赠足以补上差额时，最终净值达标，迁移应允许成功。
- `test_insufficientDonationDoesNotMaskExcessiveSwapMigrationLoss`：虽然名称提到捐赠不足，本用例实际没有转入捐赠；检查换币损失超限时，资产和版本全部恢复。
- `test_plainMigrationUsesCompleteSnapshotForAssetConservation`：普通迁移完成后，用包含所有应计资产的完整快照，分别检查两种 Token 前后总量。
- `test_bootstrapUsesCompleteSnapshotForAssetConservation`：初始化结束时实际资产不足，应完整失败；新增份额撤销，但调用前已有的捐赠不能丢失。
- `test_donationDoesNotBypassBootstrapSwapRequirement`：正常预览只能投入 75% 资产时，即使已有大量 LP 捐赠，初始化仍应以 `SwapRequired` 拒绝；用户余额、份额、捐赠和授权保持原样。
- `test_donationDoesNotBypassPlainMigrationSwapRequirement`：正常预览判断必须先换币时，LP 捐赠不能让普通迁移绕过要求；失败后旧仓、历史计划、池余额和捐赠不变。
- `test_donationIsRecognizedAfterSwapPassesRealDeploymentAssessment`：不修改预览结果，而是选择合适换币量，通过最低成交量下的投入比例评估。迁入 V2 后，精确核对捐赠对应资产、闲置余额、LP 和换币余额。
- `test_finalBootstrapDeploymentCountsDonationWhenPreviewIsMocked`：故意让预览高报可投入金额，以单独检查初始化结束时的实际投入比例会包含捐赠；同时精确核对仓位和闲置资产。
- `test_finalPlainMigrationDeploymentCountsDonationWhenPreviewIsMocked`：同样高报预览，单独检查普通迁移结束时会把捐赠计入实际投入比例；不代表正常预览下这笔迁移会成功。
- `test_finalPlainMigrationRejectsLowDeploymentWithoutDonationWhenPreviewIsMocked`：使用相同高报预览，但不给捐赠；实际投入比例不足时，最后一道检查仍应拒绝，并恢复旧仓和资产。
- `test_preexistingDonationCannotStandInForNewlyMintedLiquidity`：适配器完全不投入本次新资产时，已有捐赠仍不足以满足初始化要求，初始化应失败。
- `test_reportedLiquidityMustMatchActualLpIncrease`：Pair 声称铸造了 LP，实际 LP 余额却没有增加时，初始化应失败，临时授权也撤销。
- `test_v2DepositRejectsMintMismatchAndRollsBack`：V2 存款中，报告的 LP 铸造量与实际增加量不符时，用户余额、份额、LP 和授权全部恢复。
- `test_v2PlainMigrationRejectsMintMismatchAndRestoresOldPosition`：普通迁入 V2 时遇到 LP 铸造量不符，应失败并恢复旧 V3 仓位和已有捐赠。
- `test_v2SwapMigrationRejectsMintMismatchAndRestoresOldPosition`：换币后迁入 V2 时遇到 LP 铸造量不符，旧仓、Router 余额和已有捐赠都应恢复。
- `test_nonActiveV2IsNotQueriedForTopologyEvenWhenSnapshotFails`：未使用的 V2 适配器即使读取快照会失败，也不应被查询而影响 V3 初始化、存款、迁移或紧急退出。
- `test_reverseSwapActivationRecognizesDonation`：把 token1 换成 token0 并迁入 V2 后，同样应把已有捐赠计入正确的总资产。
- `test_donationDoesNotBypassInsufficientSwapDeploymentAssessment`：换币量太少，无法把资产比例调整到要求时，即使有大量捐赠，预览仍应拒绝；迁移失败且 Router 余额不变。
- `test_finalSwapMigrationDeploymentCountsDonationWhenSimulatedPreviewIsMocked`：人为改写换币后模拟预览，使流程走到最后，单独检查最终投入比例包含捐赠；正常预览会拒绝这个换币量。
- `test_swapLossExactlyAtCapSucceedsAndDonationIsStillFullyRecognized`：存在捐赠且换币损失恰好达到配置允许边界时，迁移仍可成功，捐赠完整计入资产。
- `test_allCirculatingSharesRedeemedRetainsLockedShareOfConfirmedDonation`：全部可流通份额赎回后，仍应保留永久锁定份额对应的资产，其中也包括已确认捐赠的相应部分。
- `test_completeSnapshotStillEnforcesSwapTokenConservation`：即使存在捐赠，换币后任一种 Token 的总量不符合“原数量减输入、加输出”，仍应失败。
- `testFuzz_activationConfirmsExactlyThePreexistingLp`：随机生成 LP 捐赠量；切换到 V2 前不计入价格，切换后精确计入已有 LP 对应资产，不增发份额。
- `testFuzz_nonActiveDonationNeverChangesV3Assets`：随机向未使用的 V2 适配器捐 LP，检查 V3 计价资产不变，正常存款和紧急退出也不受影响。

## `unit/AdaptiveLPVaultErrors.t.sol`（13）

另继承执行 `AdaptiveLPVaultDonations.t.sol` 的 38 个测试，下面不重复列出。

- `test_emergencyExitReportsPlanVersionOverflowAndRollsBack`：版本已经达到上限时，紧急退出应报告版本溢出，原仓位保持不变。
- `test_bootstrapDistinguishesLockedSharesFromMinimumNav`：初始份额不够覆盖永久锁定量时，应报告专门的份额错误，而不是最低净值错误。
- `test_bootstrapReportsTimestampOverflow`：初始化提交的时间戳超出 uint32 可表示范围时，初始化状态和新增份额全部撤销。
- `test_bootstrapReportsMissingActivePosition`：目标适配器最终没有仓位时，初始化应报告“缺少活跃仓位”。
- `test_depositReportsUncollectedFees`：要求领取手续费后，仍有待领费用时，应拒绝存款。
- `test_depositReportsMissingV3PositionId`：当前 V3 仓位 NFT 标识为零时，存款应失败，不能保留新增份额。
- `test_depositReportsRangeMismatchRatherThanInvalidRange`：实际区间本身合法、但与已保存计划不同，应报告“区间不匹配”，不是“非法区间”。
- `test_depositReportsZeroMintedSharesSeparatelyFromZeroAssets`：实际存入非零资产，但算出的份额取整为零时，应报告“零份额”，不是“零资产”。
- `test_redeemReportsMissingLiquidityRatherThanUnclearedPosition`：部分赎回后仓位流动性意外为零时，应报告“仓位缺失”，并撤销份额销毁。
- `test_bootstrapReportsShortTokenTransfer`：Token 的转账调用成功，但 Vault 实际收到的金额不足时，应报告实际转账量不匹配。
- `test_bootstrapReportsBalanceDecreaseWithoutArithmeticPanic`：应转入资产时，Vault 余额反而减少，应报告转账错误，不应先触发算术下溢。
- `test_swapReportsZeroOracleOutput`：预言机报价即使向上取整仍为零时，应报告“零换币输出”。
- `test_swapReportsInputBalanceIncreaseWithoutArithmeticPanic`：换币后输入 Token 的余额反而增加时，应报告余额不匹配，而不是算术下溢。

## `unit/AdaptiveLPVaultGas.t.sol`（29）

另继承执行捐赠套件的 38 个测试。以下前 15 项测量 Gas，其余检查减少重复查询后，业务结果是否仍正确。

- `testGas_bootstrapV3`：测量在 V3 初始化并建仓需要多少 Gas。
- `testGas_bootstrapV2`：测量在 V2 初始化并建仓需要多少 Gas。
- `testGas_bootstrapIdle`：测量初始化为 IDLE、不投入池子时需要多少 Gas。
- `testGas_depositV3NoFees`：测量 V3 没有待领手续费时，用户存款需要多少 Gas。
- `testGas_depositV3WithFees`：测量 V3 先领取手续费、再存款需要多少 Gas。
- `testGas_depositV2`：测量 V2 用户存款需要多少 Gas。
- `testGas_redeemV3NoFees`：测量 V3 没有待领手续费时，用户赎回需要多少 Gas。
- `testGas_redeemV3WithFees`：测量 V3 先领取手续费、再赎回需要多少 Gas。
- `testGas_redeemIdle`：测量 IDLE 用户赎回需要多少 Gas。
- `testGas_rebalanceV3ToV3`：测量从低费率 V3 迁入高费率 V3 需要多少 Gas。
- `testGas_rebalanceV3WithFees`：测量先领取手续费、再迁移 V3 仓位需要多少 Gas。
- `testGas_rebalanceToIdle`：测量把 V2 仓位退出到 IDLE 需要多少 Gas。
- `testGas_swapZeroForOne`：测量先把 token0 换成 token1、再迁移需要多少 Gas。
- `testGas_swapOneForZero`：测量先把 token1 换成 token0、再迁移需要多少 Gas。
- `testGas_emergencyV3WithFees`：测量 V3 带待领手续费进行紧急退出需要多少 Gas。
- `test_bootstrapReusesEstablishedSnapshotAndSkipsUnusedV2Address`：V3 初始化复用已取得的快照，不再查询用不到的 V2 地址。
- `test_depositReusesPostFeeAndPostDepositSnapshots`：存款复用领取费用后、建仓后的快照；检查份额价格、事件和闲置资产记录仍正确。
- `test_depositReadsFreshBalancesAtAccountingBoundaries`：存款在需要核对实际资产的关键步骤读取最新余额，读取次数应符合预期。
- `test_exitReadsFreshBalancesAtAccountingBoundaries`：紧急退出在领取费用、退出旧仓的前后读取最新余额，而不是使用过期数值。
- `test_singleTokenFeePreservesEventAndDepositPricing`：只有一种 Token 赚到手续费时，费用事件和新用户份额价格仍应正确。
- `test_zeroFeeRedeemDoesNotEmitFeeEvent`：没有手续费可领时，赎回不应发出费用同步事件。
- `test_feeSnapshotIncludesExistingIdleDonation`：Vault 原有闲置 Token 捐赠，应包含在费用事件相关资产快照和赎回分配中。
- `test_emergencyPreservesFeeAndExitEvents`：带手续费紧急退出时，领取费用、退出事件及最终余额都应正确。
- `test_sameVenueRecenterReusesPreviewAndPreservesRangeEvent`：同一个 V3 池内调整区间时可复用预览，但计划和区间变更事件仍须正确。
- `test_cachedSnapshotStillRejectsWrongRange`：即使复用快照，实际区间与计划不符时仍应拒绝。
- `test_cachedSnapshotStillRejectsUncollectedFees`：即使复用快照，手续费没有领完时仍应拒绝。
- `test_rebalanceRejectsUnchangedRangeUsingPreviewSnapshot`：目标资产位置和区间都与当前相同时，应拒绝这次没有实际变化的迁移。
- `test_rebalanceRejectsActualRangeMismatchBeforeCommit`：新仓实际区间与计划不符时，应在保存新版本前失败，保留原资产位置。
- `test_targetEnabledIsRecheckedAfterExitCallback`：旧仓退出回调中若把目标适配器禁用，建新仓前应重新发现禁用并撤销整笔迁移。

## `unit/AdaptiveLPVaultMigrationSafety.t.sol`（14）

提交时溢出的用例会在回调中人为推进测试时间，只用来检查防御分支。真实交易执行期间时间戳不会变化；正常调用若已超过 uint32 时间上限，会先被截止时间检查拒绝。

- `testFuzz_plainRebalanceUsesCapturedTwapAcrossCallbacks`：普通迁移中，让领取费用、退出或建仓回调改变预言机。检查整笔调用只读取一次快照，始终使用最初的 TWAP 和计划。
- `testFuzz_swapRebalanceUsesCapturedTwapAcrossCallbacks`：两个方向的换币迁移中，让费用、退出、Router 或建仓回调改变预言机。报价、模拟、净值和事件仍须使用最初的 TWAP。
- `testFuzz_bootstrapConservationDustBoundary`：初始化时故意少一种 Token；少的数量恰好等于微量容差可通过，多一个原始单位就应完整失败。
- `testFuzz_depositConservationDustBoundary`：存款时重复上述边界检查；超过容差后，用户余额、授权和份额都应恢复。
- `testFuzz_plainRebalanceExitDustBoundary`：普通迁移退出旧仓时，分别让两种 Token 出现小额损失，检查容差边界可通过、超限会完整撤销。
- `testFuzz_plainRebalanceDepositDustBoundary`：普通迁移建新仓时，对两种 Token 分别重复容差边界和超限撤销检查。
- `testFuzz_emergencyExitConservationDustBoundary`：紧急退出允许容差内的取整差额；超过容差时，仓位、版本、计划和暂停状态全部恢复。
- `testFuzz_swapExitConservationDustBoundary`：两个方向的换币迁移，在旧仓退出后分别核对两种 Token；超出容差时，应在调用 Router 前失败。
- `testFuzz_swapFinalConservationDustBoundary`：完成换币和建仓后，以“原资产减实际输入、加实际输出”为基准，检查两种 Token 的容差边界；超限则整笔撤销。
- `test_plainRebalanceAcceptsMaximumTimestamp`：时间戳恰好等于 uint32 最大值时，普通迁移仍可提交，版本和完整计划正确。
- `test_swapRebalanceAcceptsMaximumTimestamp`：同一时间边界下，换币迁移仍可提交，资产、版本和完整计划正确。
- `test_rebalancesPastMaximumTimestampRejectDeadlineBeforeAssets`：时间戳超过 uint32 上限后，普通和换币迁移都应在动用资产前报告截止时间已过。
- `test_plainRebalanceCommitTimestampOverflowRollsBack`：回调中人为把提交时间推到上限之外，检查普通迁移的资产、仓位、授权和全部历史恢复。
- `test_swapRebalanceCommitTimestampOverflowRollsBack`：换币和建仓完成后，再人为制造提交时间溢出；换币双方余额和全部历史仍应恢复。

## `unit/AdaptiveLPVaultRebalance.t.sol`（9）

- `test_rebalancesShareNonzeroCooldownAndAcceptExactBoundary`：普通迁移和换币迁移共用同一个非零冷却期；恰好到结束时刻应允许执行。
- `test_rebalanceRejectsBadHashAndExpiredDeadlineInBothEntrypoints`：两个入口都拒绝零哈希、错误哈希、旧计划哈希和过期截止时间；恰好在截止时刻仍可执行。
- `test_swapRejectsNoneAndOppositeDirectionBeforeExit`：换币方向为无，或与计划要求相反时，应在退出旧仓前拒绝。
- `test_swapRejectsUnnecessarySwap`：计划本来不需要换币时，不能使用换币迁移入口。
- `test_protocolMinOutRoundsUpBothDirectionsAndKeeperOnlyRaisesIt`：两个方向都先向上取整预言机报价，再向上取整扣除允许滑点后的最低到账量；Keeper 只能提高这个最低值，不能降低。
- `test_swapMigrationLossExactBoundaryWithoutDonation`：没有捐赠补贴时，最终净值恰好达到允许的最低值，迁移仍可成功。
- `test_swapMigrationLossOneUnitBelowBoundaryRollsBackEverything`：最终净值比最低要求少一个最小单位时，余额、仓位、授权和完整计划全部恢复。
- `test_finalDeploymentFailureRollsBackSuccessfulSwap`：确认 Router 已被调用后，再让最终仓位检查失败；此前完成的换币也必须撤销。
- `test_emergencyExitIgnoresOracleCooldownAndPreservesFullHistory`：即使冷却未结束、入口暂停、适配器禁用、预言机不可用，仍可紧急退出；历史计划和上次迁移时间不变。

## `unit/AdaptiveLPVaultReturnValues.t.sol`（32）

另继承执行捐赠套件的 38 个测试。这里重点检查输入错误的拒绝顺序，以及返回值与实际资产不一致时以什么为准。

- `test_bootstrapRejectsZeroReceiverBeforeComponentValidation`：初始化接收人为零地址时，应在重新检查组件之前拒绝，资产和份额不变。
- `testFuzz_bootstrapRejectsZeroSeed`：初始化任一种 Token 的输入数量为零时，都应拒绝。
- `testFuzz_depositRejectsZeroMaximumBeforeDepositGate`：任一种 Token 的最大存入量为零时，应先报告输入错误，再检查暂停等存款条件。
- `test_depositRejectsBothZeroMaximumsBeforeDepositGate`：两种 Token 的最大存入量都为零时，也应先报告输入错误。
- `test_depositRejectsZeroReceiverBeforeDepositGate`：份额接收人为零地址时，应先拒绝，再检查暂停等存款条件。
- `test_depositStillRejectsRoundedZeroActualAmount`：两种 Token 的输入上限都非零，但按比例算出的某侧实际输入取整为零时，仍应拒绝存款。
- `test_depositChecksInitializationBeforeZeroInputs`：Vault 尚未初始化时，即使输入也为零，存款仍应优先报告“未初始化”。
- `test_redeemRejectsZeroReceiverBeforeFeeSync`：收款人为零地址时，赎回应在领取费用之前拒绝。
- `test_redeemRejectsZeroReceiverWhileIdle`：即使在 IDLE，Vault 也应主动拒绝零地址收款人。
- `test_redeemRejectsZeroOwnerWithSpecificError`：份额持有人为零地址时，应返回 ERC-20 规定的无效发送者错误。
- `test_redeemRejectsZeroSharesBeforeFeeSync`：赎回份额为零时，应在领取费用之前拒绝。
- `test_swapRejectsZeroInputBeforeOracleRead`：换币输入为零时，应在读取预言机前返回 `ZeroAmount` 错误。
- `test_depositRejectsV3SingleSidedPrincipalWithSpecificError`：V3 仓位只有一种 Token 的本金时，存款应返回单边仓位专用错误。
- `test_depositRejectsV3ZeroPrincipalWithSpecificError`：V3 两种 Token 的本金都为零时，应返回无效本金错误。
- `test_depositRejectsV2ZeroPrincipalWithSpecificError`：V2 两种 Token 的本金都为零时，应拒绝存款。
- `test_depositRejectsV2ZeroToken0PrincipalWithSpecificError`：V2 只有 token0 本金为零时，也应拒绝存款。
- `test_depositRejectsV2ZeroToken1PrincipalWithSpecificError`：V2 只有 token1 本金为零时，也应拒绝存款。
- `test_depositStillRejectsV2ZeroActualAmountWithZeroAmount`：V2 存款的最大输入为零时，仍应报告零数量错误。
- `test_depositStillEnforcesPreDepositIdleLimit`：有人直接向 Vault 捐 Token，使存款前闲置比例超限时，应拒绝新存款。
- `test_depositStillRequiresHealthyFinalDeployment`：适配器没有把新增资产投入仓位、导致最终投入比例不足时，存款应完整失败。
- `test_redeemCombinesAdapterReturnsWithPreWithdrawalIdleShare`：赎回到账应等于适配器实际退出量，加上用户应分得的原有闲置资产；同一笔资产不能分配两次。
- `test_redeemStillEnforcesActualMinimumOutputs`：任一种 Token 实际到账低于用户要求时，赎回应失败，份额和仓位恢复。
- `test_plainRebalanceIgnoresIncorrectWithdrawAllReturns`：普通迁移以退出后实际收到的资产为准，不相信适配器错误报告的退出量。
- `test_emergencyExitIgnoresIncorrectWithdrawAllReturns`：紧急退出也以 Vault 真实余额为准，忽略适配器错误返回量。
- `test_fullExitStillEnforcesConservation`：完整退出实际支付不足时，即使适配器夸大返回量，仍应被资产总量检查拒绝。
- `test_fullExitStillRequiresPositionCleared`：声称完整退出后仍残留仓位时，整笔调用应失败，恢复原资产位置。
- `test_swapUsesExecutorOutputWithoutDuplicateVaultOutputReads`：使用可信执行器确认的实际输出，避免 Vault 重复读输出余额；执行器原有余额应保留，Router 授权应清零。
- `test_swapStillEnforcesActualMinimumOutput`：实际输出达不到 Keeper 提高后的最低要求时，换币迁移仍应失败。
- `test_swapStillEnforcesExactVaultInputDecrease`：执行器退回部分输入，导致 Vault 实际花掉的数量少于指定输入时，应拒绝。
- `test_swapStillEnforcesExecutorInputBaseline`：执行器留下本次新增的输入 Token、没有恢复原余额时，应拒绝。
- `test_swapStillEnforcesExecutorOutputBaseline`：执行器留下本次新增的输出 Token、没有恢复原余额时，应拒绝。
- `test_swapStillRequiresRouterAllowanceCleared`：换币完成后执行器仍给 Router 留有授权时，应拒绝。

## `unit/CanonicalV3Oracle.t.sol`（21）

- `testConstructorBindsPoolTokensMetadataAndWindows`：创建预言机时，检查绑定的协议池、Token 顺序、精度以及长短观察窗口都正确。
- `testConstructorRejectsInvalidWindows`：长窗口为零、长短窗口相等或短窗口更长时，均应拒绝创建。
- `testConstructorRejectsInvalidExpectedFactory`：预期 Factory 地址没有合约代码时，应拒绝创建。
- `testConstructorRejectsInvalidPoolAddress`：池地址为零，或该地址没有合约代码时，应拒绝创建。
- `testConstructorRejectsUnregisteredPool`：池没有登记在预期 Factory 中时，应拒绝创建。
- `testConstructorRejectsSelfCertifiedPoolFromUnexpectedFactory`：池声称自己有效，但来自另一个 Factory 时，不能仅凭自报信息通过检查。
- `testConstructorRejectsInvalidTokenOrder`：池中两种 Token 的地址顺序反向时，应拒绝创建。
- `testConstructorRejectsMissingTokenMetadata`：读不到 Token 精度时，错误应指出是哪一种 Token 的元数据有问题。
- `testConstructorRejectsDecimalsAboveEighteen`：任一种 Token 精度超过 18 位时，应拒绝创建。
- `testBidirectionalQuotesAtTickZeroAreOneToOne`：Tick 为零时，两个换币方向按原始单位报价都应为 1:1。
- `testQuotesHonorExplicitRoundingDirection`：两个方向的报价不是整数时，都应按调用者指定的方向向上或向下取整。
- `testFuzzQuotesRoundUpByAtMostOne`：随机生成 Tick 和输入金额，检查同方向的向上、向下报价最多相差一个输出 Token 最小单位。
- `testQuotesRejectTicksOutsideV3Bounds`：Tick 超出 V3 允许范围时，报价应失败，错误信息包含该非法 Tick。
- `testSnapshotReturnsSpotLongAndShortTwapPrices`：读取快照后，检查现价、长短 TWAP、价格偏离、观察窗口和时间都正确。
- `testSnapshotRoundsNegativeMeanTicksTowardNegativeInfinity`：平均 Tick 为负数且不能整除时，应向负无穷取整，例如 -1.2 取为 -2。
- `testSnapshotNormalizesObserveFailureAndRecovers`：读取历史观测失败时，不返回正常价格，而是返回规定的不健康快照；解除故障后可恢复。
- `testSnapshotNormalizesSlot0FailureWithoutPartialResults`：读取现价状态失败时，返回完整的不健康快照，不能夹带部分看似正常的结果。
- `testSnapshotRejectsMalformedObservationArrays`：历史观测返回的数组长度不符合要求时，应返回不健康快照。
- `testSnapshotIsUnhealthyWhenCurrentLiquidityIsZero`：池当前可用流动性为零时，快照必须标为不健康。
- `testSnapshotIsUnhealthyWhenRequiredQuoteRoundsToZero`：健康检查所需报价向下取整为零时，快照必须标为不健康。
- `testSnapshotNormalizesLiquidityReadFailure`：读取池流动性直接失败时，也应转换成规定的不健康快照。

## `unit/ControlledSwapExecutor.t.sol`（24）

- `test_constructorStoresValidatedImmutableBindings`：创建执行器后，检查固定绑定的 Vault、Router、池、Token 和费率都正确。
- `test_componentFactoryDeploysComponentsBoundToCallingVault`：组件工厂创建的 Control 和执行器，应绑定发起创建的 Vault 以及指定依赖。
- `test_constructorAllowsFactoryToBindAnotherVault`：部署者可以给另一个 Vault 创建执行器，不要求执行器只能绑定部署者自己。
- `test_constructorRejectsZeroVault`：Vault 地址为零时，应拒绝创建执行器。
- `test_constructorRejectsRouterWithoutCode`：Router 地址没有合约代码时，应拒绝创建。
- `test_constructorRejectsPoolWithoutCode`：换币池地址没有合约代码时，应拒绝创建。
- `test_constructorRejectsExpectedFactoryWithoutCode`：预期 Factory 地址没有合约代码时，应拒绝创建。
- `test_constructorRejectsInvalidTokenOrder`：换币池的 Token 地址顺序反向时，应拒绝创建。
- `test_constructorRejectsUnregisteredPool`：池未在预期 Factory 登记时，应拒绝创建。
- `test_constructorRejectsSelfCertifiedPoolFromUnexpectedFactory`：池来自另一个 Factory 时，即使自报绑定有效也应拒绝。
- `test_constructorRejectsRouterFromAnotherFactory`：Router 关联的是另一个 Factory 时，应拒绝创建。
- `test_executeSwapRejectsNonVaultCaller`：只有绑定的 Vault 能调用执行器换币，其他地址都应被拒绝。
- `test_executeSwapRejectsNoneDirection`：没有指定换币方向时，应拒绝执行。
- `test_executeSwapRejectsZeroInput`：输入金额为零时，应拒绝换币。
- `test_executeSwapRejectsZeroMinimumOutput`：最低到账量为零时，应拒绝换币。
- `test_executeSwapRejectsExpiredDeadline`：截止时间已过时，应拒绝换币。
- `test_executeSwapRejectsInputAboveExecutorBalance`：指定输入超过执行器实际持币时，应报告需要多少、实际有多少。
- `test_executeSwapZeroForOneUsesFixedRouteAndActualVaultBalanceDelta`：token0 换 token1 时，使用固定路径并直接发给 Vault；返回值以 Vault 实际到账为准，Router 授权用后清零。
- `test_executeSwapOneForZeroUsesCanonicalReverseDirection`：token1 换 token0 时，Token 顺序应正确，指定输入被消耗，Router 授权用后清零。
- `test_executeSwapIgnoresUntrustedRouterReturnValue`：Router 即使夸大报告输出，也只能按 Vault 实际增加的余额计算到账。
- `test_executeSwapRejectsActualOutputBelowMinimum`：实际输出低于最低要求时，换币应失败，输入余额和授权恢复。
- `test_executeSwapRejectsVaultOutputBalanceDecrease`：换币期间 Vault 的输出 Token 余额反而减少时，应失败。
- `test_executeSwapRejectsRouterThatConsumesLessThanExactInput`：Router 实际拿走的输入少于指定数量时，应拒绝，不能把它当作完成了精确输入换币。
- `test_executeSwapRejectsOutputSentAnywhereButVault`：Router 把输出发给执行器而不是 Vault，导致执行器新增输出余额时，应拒绝。

## `unit/CoreModules.t.sol`（10）

- `test_modulesComposeIntoOneVaultInheritanceGraph`：把角色、暂停和注册模块组合起来，检查它们能共同工作，根管理员和基础查询结果正确。
- `test_rolesUseFixedIdentifiersWithoutImplicitBusinessPermissions`：检查角色标识、初始管理员和交接延迟正确；根管理员不会自动获得业务角色。
- `test_pauseChecksRoleBeforeLifecycleAndGuardianCannotRelax`：设置暂停时先检查权限、再检查是否初始化；Guardian 只能增加限制，Manager 可以解除暂停。
- `test_pauseInternalGuardsAndEmergencyPauseAreIndependent`：每个暂停位只限制自己的入口；紧急全部暂停后，再次全部暂停不会产生额外变化。
- `test_controlBindsVaultAndEnforcesVaultOnlyOperationalChecks`：Control 正确绑定 Vault 和资产；仅供 Vault 使用的检查接口拒绝其他调用者，并正确检查暂停和 Tick 间距。
- `test_registryConfiguresAndFreezesValidatedBindings`：三个适配器及 Tick 间距缓存注册正确；Vault 初始化后，不能再更换这些身份绑定。
- `test_registryRoleAndLifecycleOrderingAndGuardianStatusLimits`：适配器状态管理先检查权限、再检查初始化；Guardian 只能禁用，Manager 可以重新启用。
- `test_registryRejectsReversedAdapterTokenOrder`：适配器与池中两种 Token 的顺序不一致时，应拒绝注册。
- `test_registryRejectsSelfCertifiedPairFromUnexpectedFactory`：Pair 不属于预期 Factory 时，即使另一个工厂自行登记了它，也应拒绝。
- `test_registryRevalidationDetectsChangedSpacingCache`：最终复核时，实际 Tick 间距与绑定值或缓存不一致，应失败。

## `unit/UniswapV2Adapter.t.sol`（29）

- `test_constructorStoresAndExposesValidatedBindings`：创建后，查询到的 Vault、协议类型、Pair 和 Token 应正确；V2 的费率及 Tick 间距字段应为零。
- `test_constructorRejectsWrongAdapterKind`：协议类型填错，或给 V2 配置了不适用的仓位管理器时，应拒绝创建。
- `test_constructorRejectsReversedTokenOrder`：Pair 的 Token 地址顺序反向时，应拒绝创建。
- `test_constructorRejectsPairNotRegisteredByFactory`：Pair 没有在预期 Factory 登记时，应拒绝创建。
- `test_constructorRejectsSelfCertifiedPairFromUnexpectedFactory`：Pair 来自另一个 Factory 时，即使自报信息有效也应拒绝。
- `test_constructorRejectsExpectedFactoryWithoutCode`：预期 Factory 地址没有合约代码时，应拒绝创建。
- `test_snapshotIsCanonicalEmptySnapshotWithoutLpTokens`：适配器没有 LP 时，快照保留其身份信息，其余资产和流动性数量均为零。
- `test_previewRejectsPlanForAnotherVenue`：存款预览收到不属于当前适配器的协议目标时，应拒绝。
- `test_depositRejectsPlanForAnotherVenue`：实际存款也应拒绝面向其他协议的计划。
- `test_previewUsesToken1AsTheLimitingSide`：token1 的上限先用完时，按池储备比例算出可配套投入的 token0。
- `testFuzz_previewNeverExceedsEitherMaximum`：随机设置两种 Token 输入上限，预览出的实际使用量都不能超限。
- `test_previewAndDepositUseOnlyTheReserveRatio`：预览和实际存款都按池储备比例计算；只从 Vault 提取本次真正会投入的金额。
- `test_depositMeasuresLpIncreaseWithExistingPositionAndDonation`：已有 LP 和捐赠时，本次新增流动性只能算操作后的 LP 余额增量，不能把旧 LP 再算一次。
- `testFuzz_depositRejectsIncorrectMintReturnAndRollsBack`：Pair 报告的 LP 量比实际多一或少一时，存款应失败，Token 余额、LP 和储备全部恢复。
- `test_depositRejectsMintReturnWithoutActualLpIncrease`：Pair 报告铸造成功，但适配器 LP 余额没有增加时，应失败。
- `test_depositRejectsLpBalanceDecreaseWithAdapterError`：应新增 LP 时余额反而减少，应报告适配器余额错误。
- `test_depositBlocksCrossFunctionReentrancy`：Pair 铸造 LP 时，通过合法 Vault 调用链回调适配器退出函数，也应被重入保护拒绝。
- `test_previewUsesPoolReserveRatioEvenWhenPositionIsTiny`：适配器自己持有的 LP 很少时，预览仍应按整个池的储备比例计算。
- `test_snapshotReportsReserveEquityAndIncludesReserveGrowth`：按 LP 占比计算可取回的储备；储备增长中的手续费已经包含在权益内，不能重复计入。
- `test_snapshotIncludesDonatedLpAndRoundsReserveEquityDown`：LP 捐赠计入适配器资产，换算成两种 Token 时向下取整。
- `test_snapshotWithZeroLpDoesNotReadPairReservesOrSupply`：没有 LP 时，快照直接返回零金额，不额外读取 Pair 储备和 LP 总供应量。
- `test_syncFeesReturnsZeroAndDoesNotMoveAssets`：V2 没有单独领取手续费的步骤，费用同步应返回零且不转移资产。
- `test_withdrawBurnsFloorRoundedLpShareAndReturnsActualBalanceDeltas`：部分赎回先向下取整应销毁的 LP，再按 Vault 实际增加的余额返回到账金额。
- `test_withdrawRejectsZeroPreBurnShareSupply`：赎回量非零，但传入的赎回前总份额为零时，应拒绝。
- `test_withdrawRejectsSharesAbovePreBurnSupply`：赎回份额超过赎回前总供应量时，应拒绝。
- `test_withdrawReturnsZeroWhenProRataLpUnitsRoundToZero`：按份额算出的 LP 退出量取整为零时，应返回零，不退出资产。
- `test_withdrawAllClearsPositionAndReturnsActualBalanceDeltas`：完整退出后 LP 应为零，返回两种 Token 实际到账增量。
- `test_assetMutatingMethodsRejectNonVaultCaller`：四个会修改资产的方法，只允许绑定的 Vault 调用。
- `test_previewDepositRemainsPermissionless`：存款预览是只读接口，任何地址都可调用。

## `unit/UniswapV3Adapter.t.sol`（12）

- `test_constructorRejectsExpectedFactoryWithoutCode`：预期 Factory 地址没有合约代码时，应拒绝创建。
- `test_constructorRejectsSelfCertifiedPoolFromUnexpectedFactory`：池和仓位管理器来自其他 Factory 时，应拒绝这组配置。
- `test_previewRejectsLiquidityAboveUint128`：预览算出的 liquidity 超过 uint128 上限时，应失败。
- `test_depositRejectsInvalidMintedPositionOwner`：新仓 NFT 实际不归适配器所有时，应拒绝存款。
- `test_syncFeesRejectsRemainingClaimableFees`：领取手续费后仍有待领费用时，应报告手续费没有领完。
- `test_withdrawAllBubblesManagerNotClearedRevert`：完整退出后还有待领资产，仓位管理器因此拒绝销毁 NFT 时，应把该错误传给调用者。
- `test_withdrawAllBurnsClearedPosition`：完整退出后，空仓 NFT 应销毁，适配器记录的仓位标识归零。
- `testGas_v3Preview`：测量 V3 存款预览需要多少 Gas。
- `testGas_v3Mint`：测量新建 V3 NFT 仓位需要多少 Gas。
- `testFuzz_previewMatchesLegacyAcrossPricesAndRanges`：随机金额、价格和区间下，检查预览与保留的旧数学算法结果相同，且不超过输入上限。
- `test_previewMatchesLegacyAtBothRangeBoundariesAndZeroInputs`：价格位于区间上下边界，或输入为零、只有一种 Token 时，预览仍应与旧算法一致。
- `test_previewMatchesLegacyAtExtremeValidRanges`：区间接近 V3 合法 Tick 的极值时，预览仍应与旧算法一致。

## `unit/UniswapV3AdapterAccounting.t.sol`（14）

使用生产 V3 适配器，搭配能实际转账、记录流动性、把新增费用计入可领取金额的仓位管理器替身；不能代替连接真实协议的主网分叉测试。

- `test_snapshotSeparatesPrincipalOwedAndFeeGrowth`：把仓位本金、已记入可领取金额的费用、新产生但尚未记入的费用分开计算，检查没有重复加总。
- `test_feeGrowthInsideHandlesAllPriceRegionsAndWraparound`：价格在区间内、外和边界时，区间手续费增长都应算对；累计值越过 uint256 上限、从零继续计数时也应算对。
- `test_syncFeesCollectsActualDeltasAndPreservesPrincipal`：返回的已领费用必须等于实际到账，本金不变；没有新增费用时再次领取应返回零。
- `test_depositMintAndIncreaseUseActualAmountsAndClearAllowances`：新建和追加仓位都按实际投入量扣款；剩余款退回后，适配器回到原余额，临时授权清零。
- `test_depositRejectsManagerOveruseAndBalanceMismatchAtomically`：管理器报告超出任一种 Token 上限，或报告金额与真实余额不符时，资金、NFT 和授权一起恢复。
- `test_withdrawUsesFloorLiquidityAndActualTokenDeltas`：部分退出的 liquidity 向下取整；输出按实际到账算，不相信管理器报告量。
- `test_withdrawHandlesZeroUnitsAndInvalidShareSupply`：零份额、空仓或退出量取整为零时直接返回；不合法的总份额参数应拒绝。
- `test_withdrawAllTransfersAllOwedAndClearsManagedNft`：完整退出领取全部本金和手续费，销毁 NFT；再次退出应返回零。
- `test_withdrawAllCollectsOwedWithZeroLiquidity`：liquidity 已为零，但还有待领资产时，仍应领完资产并销毁 NFT。
- `test_assetMethodsRejectNonVaultCaller`：四个资产方法只允许绑定 Vault 调用，预览仍可公开调用。
- `test_managerCallbackBlocksCrossFunctionReentry`：仓位管理器经合法 Vault 调用链回调适配器的其他资产方法时，仍应被重入保护拒绝。
- `test_depositRejectsChangedRangeWithActiveLiquidity`：旧仓还有 liquidity 时，不能通过存款直接换成另一个区间。
- `test_depositReplacesOnlyClearedEmptyNft`：只有旧 NFT 的 liquidity 和待领资产都为零，才允许销毁它并新建仓位。
- `test_previewAndDepositRejectWrongVenueAndInvalidRanges`：预览和存款都拒绝错误协议目标，以及上下界反向、零宽度、未按 Tick 间距对齐或超出范围的区间。

## `unit/VaultDeploymentAssessment.t.sol`（5）

- `test_assessmentCallsLinkedLibraryAndPreservesQueryArguments`：检查确实调用外部评估库，传给适配器的参数和两次独立向下取整报价的参数都正确。
- `test_idleDoesNotQueryZeroAddressDependencies`：目标是 IDLE 时，不查询没有配置地址的依赖。
- `test_zeroNavAndMaximumNavWorkWithinStaticCall`：净值为零或最大可表示值时，都能在不修改状态的静态调用中安全计算。
- `testFuzz_matchesOriginalResultsAndReverts`：随机输入下，新评估实现的返回结果或错误数据，应与保留的旧参考算法相同。
- `testFuzz_validPreviewsMatchOriginalCalculation`：随机生成只有一种 Token 剩余的合法预览，核对投入比例要求和换币方向与参考公式一致。

## `unit/VaultRoles.t.sol`（5）

- `test_defaultAdminTransferCancelAndDelayedAcceptance`：检查根管理员交接可以发起、取消，接任者必须等延迟结束才能接受；业务角色不会随根权限自动转移。
- `test_defaultAdminRenounceRequiresScheduledZeroTransfer`：放弃根管理员权限前，必须先安排转移到零地址，并等待规定延迟。
- `test_defaultAdminDelayIncreaseDecreaseAndRollback`：检查管理员交接延迟的增加、减少、取消，以及新延迟恰好开始生效时的行为。
- `test_singleAdminRuleAndNonzeroInitialAdmin`：根管理员只能有一个账户，初始管理员不能是零地址。
- `test_businessRoleGrantRevokeAndSelfRenounce`：分别检查三种业务角色的授予、撤销、自愿放弃，以及无权操作时被拒绝。

## `unit/VaultStrategyMath.t.sol`（24）

- `test_externalLibraryIsDeployedAndCalledFromPureEntryPoint`：检查计划库确实部署，并可通过纯计算入口生成首次低偏离市场计划。
- `test_linkedLibraryCanExecuteWithinStaticCall`：外部链接的计划库可以在不修改状态的静态调用中执行。
- `test_bootstrapClassifiesAtCompleteEntryThresholds`：首次生成计划时，按各状态的完整进入阈值分类；分别检查阈值前、恰好到阈值和阈值后的结果。
- `test_hysteresisUsesInclusiveBoundariesAndOnlyOneTransition`：已有历史状态时，用不同的进入、退出阈值避免频繁切换；恰好到边界也算触发，但一次最多只切换一个相邻市场状态。
- `test_mediumRegimeUsesHighFeeSpacingAndWideRange`：市场处于中等偏离状态时，选择高费率 V3 池，使用对应 Tick 间距和更宽区间。
- `test_nonV3PlansNormalizeTicksAndDoNotNeedSpacing`：V2 和 IDLE 不需要 V3 区间，计划上下 Tick 都设为零，也不读取 V3 间距。
- `test_rangeRoundingHandlesBothSignsAndTiesDownward`：正负 Tick 都对齐到最近的合法间距；到上下两个位置距离一样时，选较低的位置。
- `test_sameVenueKeepsRangeWhenSpotIsInsideIncludingLowerBound`：仍使用同一个池，且现价在原区间内或恰好在下界时，保留旧区间。
- `test_spotOutsideKeepsRangeBelowRecenterThreshold`：现价虽已越出区间，但 TWAP 中心移动还不够大时，仍保留旧区间。
- `test_spotAtUpperBoundRecentersAtExactThreshold`：现价恰好到不包含在区间内的上界，且中心位移恰好达标时，应重建区间。
- `test_spotBelowLowerBoundRecentersAtExactThreshold`：现价低于下界，且中心位移恰好达标时，也应重建区间。
- `test_widthChangeRecentersEvenWithSpotInside`：原区间宽度不符合当前策略时，即使现价还在区间内，也应重建。
- `test_zeroLiquidityAndDifferentVenueDoNotRetainOldRange`：旧仓没有流动性，或目标已换成另一个池时，不沿用旧区间。
- `test_idleUsesHistoricalRegimeRatherThanCurrentVenue`：从 IDLE 继续生成计划时，使用之前保存的市场状态，不能因为当前闲置就丢掉状态历史。
- `test_rejectsNonPositiveSpacingAndZeroSteps`：Tick 间距不为正，或区间半宽步数为零时，不能生成 V3 区间。
- `test_rejectsOutOfBoundsRangeInsteadOfClamping`：算出的区间超出 V3 合法范围时，应失败，不能擅自把区间裁短到边界。
- `test_acceptsExactV3TickBounds`：区间边界恰好等于 V3 最小或最大合法 Tick 时，应允许。
- `test_maximumVersionRevertsAndPenultimateVersionSucceeds`：版本比上限少一时可以生成最后一个版本；已经到上限后，再生成计划应失败。
- `test_planInputsEncodeOnlyTwelveWords`：检查新计划输入编码占 12 个 ABI 数据字，而旧完整输入占 41 个数据字。
- `test_strategyUnpackingHasExactFieldBoundaries`：从打包参数中取回各字段时，不能互相串位；全零输入也应正确还原。
- `testFuzz_strategyUnpackingPreservesAllFieldBits`：随机打包值解码后，各字段的有效位全部保留，多余高位不影响结果。
- `testFuzz_packedStrategyMatchesLegacyForArbitraryFields`：随机策略参数下，打包实现与旧实现生成相同计划或相同失败；版本溢出的已知差异单独处理。
- `testFuzz_planMatchesPreExtractionAlgorithm`：随机市场状态、目标协议、Tick、区间和版本下，生成计划与代码抽取前的参考算法相同。
- `testFuzz_bootstrapRangesAreAlignedCoverTwapAndHaveStableHash`：首次 V3 区间应按间距对齐、包含 TWAP 位置且宽度正确；同样输入生成同样计划哈希，独立重算也应一致。
