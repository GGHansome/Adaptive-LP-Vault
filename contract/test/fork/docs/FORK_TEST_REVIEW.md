# Fork 测试函数目录

本目录解释主网分叉测试中每个函数“先做什么、检查什么”。按源码直接定义的函数统计，共 31 个测试，分布在 6 个测试合约中；辅助环境不定义测试函数，测试合约之间不继承用例。

Fork 是把某个历史区块的主网状态复制到本地，测试中的转账和交易不会广播到主网。Vault 是项目资金库，用户持有 shares（份额）；V2 的 LP 代币表示流动性权益，V3 的 NFT 表示仓位。低费率、高费率 V3 池分别收取 0.05%、0.3% 交易手续费。IDLE 是资产直接留在 Vault、不投入池子的状态。

TWAP 是一段时间内的加权平均价格，Tick 是 V3 的价格位置编号；“净值”是按测试价格算出的资产价值。“回滚”表示整笔调用失败，并撤销其中已经发生的转账和状态修改。网络地址、资金准备、策略参数、运行命令和覆盖限制见 [Fork 测试说明](README.md)。以下路径均相对于 `test/fork/`。

## `DependenciesOracle.t.sol`（5）

- `test_realDeploymentsAndPoolBindings`：检查主网依赖地址确实有合约代码，USDC/WETH 精度和顺序正确，V2/V3 池确实登记在指定 Factory（池工厂）中；再核对池费率、Tick 间距和流动性，以及换币路由器、仓位管理器和预言机的绑定。
- `test_realHistoryMatchesIndependentMeanTicks`：直接读取池的历史累计 Tick，独立算出长、短窗口的平均 Tick，再核对预言机快照、价格偏离和观察时间；默认区块下还要与已知 Tick 值相同。
- `test_mixedDecimalSpotQuotesAgreeWithRawPoolPrice`：用池直接提供的平方根价格计算两种方向的现价报价，再与预言机按 Tick 计算的报价比较。允许一个 Tick 对应的价格差，同时检查向上取整与向下取整最多差一个输出最小单位。
- `test_insufficientRealHistoryIsUnhealthyWithoutMocks`：给预言机设置一个超过真实池已有历史长度的观察窗口，检查它返回不健康；不通过替身伪造历史读取失败。
- `test_timePassageUsesRealPoolObservations`：不做新交易，只让时间超过观察窗口；检查长、短平均 Tick 都变成当前现价 Tick，偏离归零。

## `DepositRedeem.t.sol`（3）

- `test_lowFeeRealTokenMultiUserLifecycle`：在低费率 V3 中，用真实 USDC/WETH 初始化，让多用户存款、部分赎回和授权代赎；检查授权正确扣减，全部可流通份额赎回后仍保留永久锁定份额，并能再次存入和赎回。
- `test_highFeeRealTokenMultiUserLifecycle`：换成高费率 V3，重复上述真实资产的存入、赎回和再次使用流程。
- `test_v2RealTokenMultiUserLifecycle`：换成 V2，重复同一流程，检查 LP 仓位下也能正确存入和赎回。

三个场景都检查实际支付和到账、独立组合计算的份额价格、两种 Token 各自的前后总量、只能有一个活跃仓位，以及操作结束后临时授权清零。

## `FeeAccounting.t.sol`（4）

- `test_lowFeeAccrualIsPricedBeforeNewSharesAndPaidOnExit`：先通过真实双向交易，让低费率 V3 赚到 USDC 和 WETH 手续费，再让新用户存款。检查这些已赚收益先计入份额价格，新用户不能按“只算本金”的低价获得更多份额；费用领完后原仓位标识不变，新老用户可以赎回，没有新交易时再次存款不会重复记入同一笔手续费。
- `test_highFeeAccrualIsPricedBeforeNewSharesAndPaidOnExit`：换成高费率 V3，重复上述费用计价、领取、赎回和不重复记账检查。
- `test_redeemSlippageRestoresRealFeesLiquidityAndShareAllowance`：故意把赎回最低到账量设得过高，让代赎失败。检查费用领取、仓位变化、池余额、用户份额、总份额和授权扣减全部撤销；降低要求后重试应成功。
- `test_v2RealTradesIncreaseReserveProductAndLpEquity`：在真实 V2 池做双向交易，检查两侧储备数量的乘积增加，Vault 的 LP 对应净值也增加；V2 没有 V3 式单独待领费用，两种待领费用字段应为零，之后仍能存入和赎回。

## `Rebalance.t.sol`（5）

- `test_realTwapConvergenceMigratesV2ToHighToLowAndBurnsOldNft`：不做新交易，等真实历史价格偏离归零，再按保留历史状态的策略规则，从 V2 逐步迁入高费率 V3、低费率 V3。检查退出的 LP、旧 NFT 被清理，用户份额不变且仍能赎回。
- `test_oldPlanIsRejectedAfterRealMigrationAndStateRemainsIntact`：先预览计划，再完成另一笔真实迁移。此后提交旧计划应被拒绝，当前资产和仓位不能变化；重新生成计划后可以继续迁移。
- `test_realPriceTradeDoesNotImmediatelyReplaceTwapRegime`：真实交易应立即改变现价 Tick，但在同一时间戳下，长短 TWAP 和偏离不应立刻变化；等一个短窗口后，短 TWAP 才反映新价格，长短平均值出现差异。
- `test_realOutOfRangePriceMoveRecentersLowFeeAndBurnsOldNft`：用更窄的测试区间建仓，再通过真实交易把价格推到旧区间之外。等历史观测更新、补足新区间所需的资产比例后，在同一个低费率池重建仓位；检查新 NFT 替换旧 NFT，之后仍能存入和赎回。
- `test_cooldownAndDeadlineProtectRealPosition`：完成真实迁移后，冷却期未结束时再次迁移应失败且选定状态不变；冷却结束后，使用已过期的截止时间也应被拒绝，资产记录仍正确。

## `SwapRebalance.t.sol`（10）

- `test_realUsdcToWethSwapMigratesV2ToHighFee`：把 USDC 换成 WETH，再从 V2 迁入高费率 V3。
- `test_realWethToUsdcSwapMigratesV2ToHighFee`：把 WETH 换成 USDC，再从 V2 迁入高费率 V3。
- `test_realUsdcToWethSwapReactivatesLowFee`：资产处于 IDLE 且 USDC 偏多时，先换成部分 WETH，再重新投入低费率 V3。
- `test_realWethToUsdcSwapReactivatesLowFee`：资产处于 IDLE 且 WETH 偏多时，先换成部分 USDC，再重新投入低费率 V3。
- `test_realUsdcToWethSwapReactivatesV2`：资产处于 IDLE 且 USDC 偏多时，换币调整比例，再投入 V2。
- `test_realWethToUsdcSwapReactivatesV2`：资产处于 IDLE 且 WETH 偏多时，向相反方向换币调整比例，再投入 V2。
- `test_routerSlippageRestoresOldPositionAndAllowsRetry`：USDC 换 WETH 时，故意设置无法满足的最低到账量，让真实 Router 失败。检查旧 V2 仓位、池状态和临时授权恢复；放宽要求后，用原计划重试应成功。
- `test_reverseRouterSlippageRestoresOldPositionAndAllowsRetry`：在 WETH 换 USDC 的方向重复上述失败、状态恢复和成功重试检查。
- `test_injectedTargetMintFailureRollsBackRealSwapAndAllowsRetry`：只让目标池建仓的 mint 调用失败，并确认此前确实调用过真实 Router；检查已完成换币和旧仓退出一起撤销，解除故障后重试应成功。
- `test_realCompetingTradeAfterPreviewStillRespectsExecutionBounds`：预览后先插入另一笔真实交易，让池状态发生变化。计划仍相同时，执行依然必须满足实际最低到账量、资产投入比例和最终净值损失上限。

成功场景都核对两种资产的变化、总份额、保存的计划、最低到账量、迁移损失和最大闲置比例。目标高费率池与换币池分开的场景，还会直接从换币池核对实际输入和输出。

## `EmergencyRecovery.t.sol`（4）

- `test_lowFeeExitPausedAndDisabledThenRedeemAndRecover`：低费率 V3 已赚到手续费时，暂停入口并禁用适配器，检查仍能赎回和紧急退出。退出后 NFT 销毁，再次退出不重复改变状态；重新启用后可以建仓、存入和赎回。
- `test_highFeeExitPausedAndDisabledThenRedeemAndRecover`：换成高费率 V3，重复上述故障状态下退出和恢复使用的流程。
- `test_v2ExitPausedAndDisabledThenRedeemAndRecover`：换成 V2，重复上述流程，并检查退出后 LP 全部清空。
- `test_injectedObservationFailureBlocksEntryButPreservesRealExit`：只让真实定价池的历史观测读取失败。检查生产预言机因此阻止新存款和迁移预览，但用户仍能赎回真实仓位，紧急退出也能完成。
