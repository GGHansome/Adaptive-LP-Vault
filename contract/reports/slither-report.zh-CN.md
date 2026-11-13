# Slither 静态分析报告（中文译本）

> 原文：[slither-report.md](slither-report.md)。本译本保留原报告的检测项编号、分类、影响等级、置信度、代码表达式及源码行号；源码链接按本文件所在目录调整为 `../src/`。为便于阅读，省略了每条末尾与链接重复的纯文本源码位置及多余空行。
>
> 翻译说明：以下内容是 Slither 工具输出的中文翻译，并非人工复核结论。检测项可能包含误报，原文中的风险表述和等级均按原样保留，不能据此认定存在可利用漏洞。原报告更新后，应同步更新本译本。

**此检查清单并不完整。** 使用 `--show-ignored-findings` 可显示全部结果。

## 汇总

- [任意来源地址的 ERC-20 转账（arbitrary-send-erc20）](#arbitrary-send-erc20)：4 条，影响等级：高。
- [弱伪随机数生成器（weak-prng）](#weak-prng)：1 条，影响等级：高。
- [涉及余额读取的重入（reentrancy-balance）](#reentrancy-balance)：23 条，影响等级：高。
- [先除后乘（divide-before-multiply）](#divide-before-multiply)：20 条，影响等级：中。
- [不当的严格相等判断（incorrect-equality）](#incorrect-equality)：26 条，影响等级：中。
- [不涉及原生 ETH 转账的重入（reentrancy-no-eth）](#reentrancy-no-eth)：7 条，影响等级：中。
- [未初始化的局部变量（uninitialized-local）](#uninitialized-local)：47 条，影响等级：中。
- [未使用的返回值（unused-return）](#unused-return)：17 条，影响等级：中。
- [数值状态变更缺少事件（events-maths）](#events-maths)：1 条，影响等级：低。
- [循环中的外部调用（calls-loop）](#calls-loop)：7 条，影响等级：低。
- [良性重入（reentrancy-benign）](#reentrancy-benign)：2 条，影响等级：低。
- [时间戳相关比较（timestamp）](#timestamp)：14 条，影响等级：低。
- [圈复杂度过高（cyclomatic-complexity）](#cyclomatic-complexity)：9 条，影响等级：提示信息。
- [未使用的代码（dead-code）](#dead-code)：1 条，影响等级：提示信息。
- [命名约定（naming-convention）](#naming-convention)：34 条，影响等级：提示信息。
- [数字字面量位数过多（too-many-digits）](#too-many-digits)：3 条，影响等级：提示信息。

<a id="arbitrary-send-erc20"></a>
## 任意来源地址的 ERC-20 转账（arbitrary-send-erc20）

影响等级：高  
置信度：高

- [ ] ID-0

[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L233-L315) 在 `transferFrom` 中使用了任意来源地址 `from`：[IERC20(_TOKEN0).safeTransferFrom(_VAULT,address(this),desired0)](../src/adapters/UniswapV3Adapter.sol#L262)。

- [ ] ID-1

[UniswapV2Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV2Adapter.sol#L164-L184) 在 `transferFrom` 中使用了任意来源地址 `from`：[IERC20(_TOKEN0).safeTransferFrom(_VAULT,_POOL,used0)](../src/adapters/UniswapV2Adapter.sol#L176)。

- [ ] ID-2

[UniswapV2Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV2Adapter.sol#L164-L184) 在 `transferFrom` 中使用了任意来源地址 `from`：[IERC20(_TOKEN1).safeTransferFrom(_VAULT,_POOL,used1)](../src/adapters/UniswapV2Adapter.sol#L177)。

- [ ] ID-3

[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L233-L315) 在 `transferFrom` 中使用了任意来源地址 `from`：[IERC20(_TOKEN1).safeTransferFrom(_VAULT,address(this),desired1)](../src/adapters/UniswapV3Adapter.sol#L266)。

<a id="weak-prng"></a>
## 弱伪随机数生成器（weak-prng）

影响等级：高  
置信度：中

- [ ] ID-4

[UniswapV3Adapter._validateRange(int24,int24)](../src/adapters/UniswapV3Adapter.sol#L478-L485) 使用了弱伪随机数生成器（PRNG）：[tickLower < MIN_TICK || tickUpper > MAX_TICK || tickLower >= tickUpper || tickLower % _TICK_SPACING != 0 || tickUpper % _TICK_SPACING != 0](../src/adapters/UniswapV3Adapter.sol#L480-L481)。

<a id="reentrancy-balance"></a>
## 涉及余额读取的重入（reentrancy-balance）

影响等级：高  
置信度：中

- [ ] ID-5

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](../src/core/AdaptiveLPVault.sol#L404)
    - [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](../src/core/AdaptiveLPVault.sol#L777-L779)
- 调用前读取的余额：
  - [balance0 = IERC20(token0).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L390)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`finalNav`。

- [ ] ID-6

[AdaptiveLPVault._executeControlledSwap(SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L764-L796) 中存在重入：
- 允许重入的外部调用：
  - [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](../src/core/AdaptiveLPVault.sol#L777-L779)
- 调用前读取的余额：
  - [inputBefore = IERC20(input).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L770)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [inputAfter > inputBefore || inputBefore - inputAfter != amountIn](../src/core/AdaptiveLPVault.sol#L781)
    - 可能过期的变量：`inputBefore`。

- [ ] ID-7

[AdaptiveLPVault.emergencyExitToIdle()](../src/core/AdaptiveLPVault.sol#L434-L457) 中存在重入：
- 允许重入的外部调用：
  - [_exitActivePosition(adapter)](../src/core/AdaptiveLPVault.sol#L443)
    - [IPositionAdapter(adapter).withdrawAll()](../src/core/AdaptiveLPVault.sol#L732)
- 调用前读取的余额：
  - [position = _synchronizeFees(adapter)](../src/core/AdaptiveLPVault.sol#L441)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [planVersion == type()(uint64).max](../src/core/AdaptiveLPVault.sol#L449)
    - 可能过期的变量：`planVersion`。

- [ ] ID-8

[AdaptiveLPVault.redeem(uint256,uint256,uint256,address,address)](../src/core/AdaptiveLPVault.sol#L272-L310) 中存在重入：
- 允许重入的外部调用：
  - [(positionOut0,positionOut1) = IPositionAdapter(adapter).withdraw(shares,supply)](../src/core/AdaptiveLPVault.sol#L296)
- 调用前读取的余额：
  - [idle0Before = IERC20(token0).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L290)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [amount0Out < minAmount0Out || amount1Out < minAmount1Out](../src/core/AdaptiveLPVault.sol#L300)
    - 可能过期的变量：`amount0Out`。

- [ ] ID-9

[AdaptiveLPVault._executeControlledSwap(SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L764-L796) 中存在重入：
- 允许重入的外部调用：
  - [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](../src/core/AdaptiveLPVault.sol#L777-L779)
- 调用前读取的余额：
  - [executorInput = IERC20(input).balanceOf(executorAddress)](../src/core/AdaptiveLPVault.sol#L773)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [IERC20(input).balanceOf(executorAddress) != executorInput || IERC20(output).balanceOf(executorAddress) != executorOutput](../src/core/AdaptiveLPVault.sol#L788-L789)
    - 可能过期的变量：`executorInput`。

- [ ] ID-10

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](../src/core/AdaptiveLPVault.sol#L407-L409)
    - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 调用前读取的余额：
  - [(plan,assessment,current) = _previewFromSnapshot(oracle)](../src/core/AdaptiveLPVault.sol#L376-L377)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`finalNav`。

- [ ] ID-11

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [_exitActivePosition(current.adapter)](../src/core/AdaptiveLPVault.sol#L389)
    - [IPositionAdapter(adapter).withdrawAll()](../src/core/AdaptiveLPVault.sol#L732)
- 调用前读取的余额：
  - [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](../src/core/AdaptiveLPVault.sol#L388)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`minimumNavAfter`。

- [ ] ID-12

[AdaptiveLPVault._depositToAdapter(address,PositionPlan,uint256,uint256)](../src/core/AdaptiveLPVault.sol#L743-L762) 中存在重入：
- 允许重入的外部调用：
  - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 调用前读取的余额：
  - [before1 = IERC20(token1).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L747)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [used0 > amount0Max || used1 > amount1Max || after0 > before0 || after1 > before1 || before0 - after0 != used0 || before1 - after1 != used1](../src/core/AdaptiveLPVault.sol#L757-L758)
    - 可能过期的变量：`before1`。

- [ ] ID-13

[AdaptiveLPVault._depositToAdapter(address,PositionPlan,uint256,uint256)](../src/core/AdaptiveLPVault.sol#L743-L762) 中存在重入：
- 允许重入的外部调用：
  - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 调用前读取的余额：
  - [before0 = IERC20(token0).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L746)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [used0 > amount0Max || used1 > amount1Max || after0 > before0 || after1 > before1 || before0 - after0 != used0 || before1 - after1 != used1](../src/core/AdaptiveLPVault.sol#L757-L758)
    - 可能过期的变量：`before0`。

- [ ] ID-14

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](../src/core/AdaptiveLPVault.sol#L404)
    - [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](../src/core/AdaptiveLPVault.sol#L777-L779)
- 调用前读取的余额：
  - [(plan,assessment,current) = _previewFromSnapshot(oracle)](../src/core/AdaptiveLPVault.sol#L376-L377)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`finalNav`。

- [ ] ID-15

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](../src/core/AdaptiveLPVault.sol#L404)
    - [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](../src/core/AdaptiveLPVault.sol#L777-L779)
- 调用前读取的余额：
  - [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](../src/core/AdaptiveLPVault.sol#L388)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`minimumNavAfter`。

- [ ] ID-16

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](../src/core/AdaptiveLPVault.sol#L407-L409)
    - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 调用前读取的余额：
  - [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](../src/core/AdaptiveLPVault.sol#L388)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`minimumNavAfter`。

- [ ] ID-17

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](../src/core/AdaptiveLPVault.sol#L407-L409)
    - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 调用前读取的余额：
  - [balance0 = IERC20(token0).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L390)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`finalNav`。

- [ ] ID-18

[ControlledSwapExecutor.executeSwap(SwapPlan)](../src/swap/ControlledSwapExecutor.sol#L108-L161) 中存在重入：
- 允许重入的外部调用：
  - [_ROUTER.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({tokenIn:tokenIn,tokenOut:tokenOut,fee:_FEE_TIER,recipient:_VAULT,deadline:uint256(plan.deadline),amountIn:plan.amountIn,amountOutMinimum:plan.minAmountOut,sqrtPriceLimitX96:0}))](../src/swap/ControlledSwapExecutor.sol#L128-L139)
- 调用前读取的余额：
  - [executorInputBefore = inputToken.balanceOf(address(this))](../src/swap/ControlledSwapExecutor.sol#L119)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [executorInputAfter != expectedExecutorInputAfter](../src/swap/ControlledSwapExecutor.sol#L144)
    - 可能过期的变量：`expectedExecutorInputAfter`。

- [ ] ID-19

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [_exitActivePosition(current.adapter)](../src/core/AdaptiveLPVault.sol#L389)
    - [IPositionAdapter(adapter).withdrawAll()](../src/core/AdaptiveLPVault.sol#L732)
- 调用前读取的余额：
  - [(plan,assessment,current) = _previewFromSnapshot(oracle)](../src/core/AdaptiveLPVault.sol#L376-L377)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`finalNav`。

- [ ] ID-20

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](../src/core/AdaptiveLPVault.sol#L404)
    - [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](../src/core/AdaptiveLPVault.sol#L777-L779)
- 调用前读取的余额：
  - [balance1 = IERC20(token1).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L391)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`finalNav`。

- [ ] ID-21

[ControlledSwapExecutor.executeSwap(SwapPlan)](../src/swap/ControlledSwapExecutor.sol#L108-L161) 中存在重入：
- 允许重入的外部调用：
  - [_ROUTER.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({tokenIn:tokenIn,tokenOut:tokenOut,fee:_FEE_TIER,recipient:_VAULT,deadline:uint256(plan.deadline),amountIn:plan.amountIn,amountOutMinimum:plan.minAmountOut,sqrtPriceLimitX96:0}))](../src/swap/ControlledSwapExecutor.sol#L128-L139)
- 调用前读取的余额：
  - [vaultOutputBefore = outputToken.balanceOf(_VAULT)](../src/swap/ControlledSwapExecutor.sol#L124)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [amountOut < plan.minAmountOut](../src/swap/ControlledSwapExecutor.sol#L158)
    - 可能过期的变量：`amountOut`。
  - [vaultOutputAfter < vaultOutputBefore](../src/swap/ControlledSwapExecutor.sol#L154)
    - 可能过期的变量：`vaultOutputBefore`。

- [ ] ID-22

[UniswapV2Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV2Adapter.sol#L164-L184) 中存在重入：
- 允许重入的外部调用：
  - [liquidity = _PAIR.mint(address(this))](../src/adapters/UniswapV2Adapter.sol#L178)
- 调用前读取的余额：
  - [lpBefore = _PAIR.balanceOf(address(this))](../src/adapters/UniswapV2Adapter.sol#L175)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [lpAfter < lpBefore || lpAfter - lpBefore != liquidity](../src/adapters/UniswapV2Adapter.sol#L181)
    - 可能过期的变量：`lpBefore`。

- [ ] ID-23

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](../src/core/AdaptiveLPVault.sol#L407-L409)
    - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 调用前读取的余额：
  - [balance1 = IERC20(token1).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L391)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`finalNav`。

- [ ] ID-24

[ControlledSwapExecutor.executeSwap(SwapPlan)](../src/swap/ControlledSwapExecutor.sol#L108-L161) 中存在重入：
- 允许重入的外部调用：
  - [_ROUTER.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({tokenIn:tokenIn,tokenOut:tokenOut,fee:_FEE_TIER,recipient:_VAULT,deadline:uint256(plan.deadline),amountIn:plan.amountIn,amountOutMinimum:plan.minAmountOut,sqrtPriceLimitX96:0}))](../src/swap/ControlledSwapExecutor.sol#L128-L139)
- 调用前读取的余额：
  - [executorOutputBefore = outputToken.balanceOf(address(this))](../src/swap/ControlledSwapExecutor.sol#L125)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [executorOutputAfter != executorOutputBefore](../src/swap/ControlledSwapExecutor.sol#L149)
    - 可能过期的变量：`executorOutputBefore`。

- [ ] ID-25

[AdaptiveLPVault._executeControlledSwap(SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L764-L796) 中存在重入：
- 允许重入的外部调用：
  - [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](../src/core/AdaptiveLPVault.sol#L777-L779)
- 调用前读取的余额：
  - [executorOutput = IERC20(output).balanceOf(executorAddress)](../src/core/AdaptiveLPVault.sol#L774)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [IERC20(input).balanceOf(executorAddress) != executorInput || IERC20(output).balanceOf(executorAddress) != executorOutput](../src/core/AdaptiveLPVault.sol#L788-L789)
    - 可能过期的变量：`executorOutput`。

- [ ] ID-26

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 允许重入的外部调用：
  - [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](../src/core/AdaptiveLPVault.sol#L388)
    - [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](../src/core/AdaptiveLPVault.sol#L638)
- 调用前读取的余额：
  - [(plan,assessment,current) = _previewFromSnapshot(oracle)](../src/core/AdaptiveLPVault.sol#L376-L377)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [finalNav < minimumNavAfter](../src/core/AdaptiveLPVault.sol#L418)
    - 可能过期的变量：`finalNav`。

- [ ] ID-27

[AdaptiveLPVault.redeem(uint256,uint256,uint256,address,address)](../src/core/AdaptiveLPVault.sol#L272-L310) 中存在重入：
- 允许重入的外部调用：
  - [(positionOut0,positionOut1) = IPositionAdapter(adapter).withdraw(shares,supply)](../src/core/AdaptiveLPVault.sol#L296)
- 调用前读取的余额：
  - [idle1Before = IERC20(token1).balanceOf(address(this))](../src/core/AdaptiveLPVault.sol#L291)
- 调用后，条件判断中可能使用了过期的余额数据：
  - [amount0Out < minAmount0Out || amount1Out < minAmount1Out](../src/core/AdaptiveLPVault.sol#L300)
    - 可能过期的变量：`amount1Out`。

<a id="divide-before-multiply"></a>
## 先除后乘（divide-before-multiply）

影响等级：中  
置信度：中

- [ ] ID-28

[VaultStrategyMath._targetRange(int24,int24,uint24)](../src/libraries/VaultStrategyMath.sol#L214-L235) 对除法的结果执行了乘法运算：
- [quotient = tick / s](../src/libraries/VaultStrategyMath.sol#L222)
- [lowerCenter = quotient * s](../src/libraries/VaultStrategyMath.sol#L225)

- [ ] ID-29

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128](../src/libraries/PriceMath.sol#L57)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-30

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128](../src/libraries/PriceMath.sol#L66)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-31

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128](../src/libraries/PriceMath.sol#L54)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-32

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128](../src/libraries/PriceMath.sol#L64)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-33

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128](../src/libraries/PriceMath.sol#L59)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-34

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128](../src/libraries/PriceMath.sol#L67)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-35

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128](../src/libraries/PriceMath.sol#L60)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-36

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128](../src/libraries/PriceMath.sol#L69)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-37

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128](../src/libraries/PriceMath.sol#L65)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-38

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128](../src/libraries/PriceMath.sol#L68)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-39

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128](../src/libraries/PriceMath.sol#L56)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-40

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128](../src/libraries/PriceMath.sol#L72)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-41

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128](../src/libraries/PriceMath.sol#L61)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-42

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128](../src/libraries/PriceMath.sol#L71)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-43

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128](../src/libraries/PriceMath.sol#L55)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-44

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128](../src/libraries/PriceMath.sol#L63)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-45

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128](../src/libraries/PriceMath.sol#L70)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-46

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128](../src/libraries/PriceMath.sol#L62)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

- [ ] ID-47

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 对除法的结果执行了乘法运算：
- [ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128](../src/libraries/PriceMath.sol#L58)
- [ratio = type()(uint256).max / ratio](../src/libraries/PriceMath.sol#L74)

<a id="incorrect-equality"></a>
## 不当的严格相等判断（incorrect-equality）

影响等级：中  
置信度：高

- [ ] ID-48

[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L233-L315) 使用了危险的严格相等判断：
- [desired0 == 0 && desired1 == 0](../src/adapters/UniswapV3Adapter.sol#L241)

- [ ] ID-49

[AdaptiveLPVault._validateHealthyDeployment(AssetSnapshot,int24)](../src/core/AdaptiveLPVault.sol#L868-L881) 使用了危险的严格相等判断：
- [finalNav == 0](../src/core/AdaptiveLPVault.sol#L875)

- [ ] ID-50

[AdaptiveLPVault.deposit(uint256,uint256,uint256,address)](../src/core/AdaptiveLPVault.sol#L223-L269) 使用了危险的严格相等判断：
- [position.principal0 == 0 || position.principal1 == 0](../src/core/AdaptiveLPVault.sol#L239)

- [ ] ID-51

[AdaptiveLPVault.deposit(uint256,uint256,uint256,address)](../src/core/AdaptiveLPVault.sol#L223-L269) 使用了危险的严格相等判断：
- [sharesMinted == 0](../src/core/AdaptiveLPVault.sol#L253)

- [ ] ID-52

[UniswapV2Adapter.withdrawAll()](../src/adapters/UniswapV2Adapter.sol#L205-L211) 使用了危险的严格相等判断：
- [lpBalance == 0](../src/adapters/UniswapV2Adapter.sol#L207)

- [ ] ID-53

[UniswapV3Adapter.withdraw(uint256,uint256)](../src/adapters/UniswapV3Adapter.sol#L318-L338) 使用了危险的严格相等判断：
- [liquidityToRemove == 0](../src/adapters/UniswapV3Adapter.sol#L333)

- [ ] ID-54

[AdaptiveLPVault._assessmentInputs(PositionPlan,uint256,uint256,int24)](../src/core/AdaptiveLPVault.sol#L685-L702) 使用了危险的严格相等判断：
- [plan.targetVenue == VenueType.IDLE](../src/core/AdaptiveLPVault.sol#L690)

- [ ] ID-55

[UniswapV3Adapter._snapshot()](../src/adapters/UniswapV3Adapter.sol#L353-L386) 使用了危险的严格相等判断：
- [tokenId == 0](../src/adapters/UniswapV3Adapter.sol#L358)

- [ ] ID-56

[AdaptiveLPVault._validateActivePosition(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L908-L922) 使用了危险的严格相等判断：
- [position.liquidity == 0 && position.amount0 == 0 && position.amount1 == 0](../src/core/AdaptiveLPVault.sol#L913)

- [ ] ID-57

[AdaptiveLPVault.deposit(uint256,uint256,uint256,address)](../src/core/AdaptiveLPVault.sol#L223-L269) 使用了危险的严格相等判断：
- [amount0Used == 0 || amount1Used == 0](../src/core/AdaptiveLPVault.sol#L249)

- [ ] ID-58

[AdaptiveLPVault._exitActivePosition(address)](../src/core/AdaptiveLPVault.sol#L730-L740) 使用了危险的严格相等判断：
- [activeVenue == VenueType.IDLE](../src/core/AdaptiveLPVault.sol#L731)

- [ ] ID-59

[AdaptiveLPVault.deposit(uint256,uint256,uint256,address)](../src/core/AdaptiveLPVault.sol#L223-L269) 使用了危险的严格相等判断：
- [_isV3Venue(activeVenue) && ((position.principal0 == 0) != (position.principal1 == 0))](../src/core/AdaptiveLPVault.sol#L236)

- [ ] ID-60

[UniswapV2Adapter.snapshot()](../src/adapters/UniswapV2Adapter.sol#L128-L145) 使用了危险的严格相等判断：
- [lpBalance == 0](../src/adapters/UniswapV2Adapter.sol#L135)

- [ ] ID-61

[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L885-L905) 使用了危险的严格相等判断：
- [venues[i] == expectedVenue](../src/core/AdaptiveLPVault.sol#L896)

- [ ] ID-62

[AdaptiveLPVault._proportionalAmounts(uint256,uint256,uint256,uint256)](../src/core/AdaptiveLPVault.sol#L980-L991) 使用了危险的严格相等判断：
- [high0 < high1 || (high0 == high1 && low0 <= low1)](../src/core/AdaptiveLPVault.sol#L987)

- [ ] ID-63

[AdaptiveLPVault._validateHealthyDeployment(AssetSnapshot,int24)](../src/core/AdaptiveLPVault.sol#L868-L881) 使用了危险的严格相等判断：
- [finalNav == 0 || finalDeployBps < minDeployBps](../src/core/AdaptiveLPVault.sol#L876)

- [ ] ID-64

[UniswapV3Adapter._validateManagedPosition(uint256,int24,int24)](../src/adapters/UniswapV3Adapter.sol#L463-L469) 使用了危险的严格相等判断：
- [tokenId == 0 || _POSITION_MANAGER.ownerOf(tokenId) != address(this)](../src/adapters/UniswapV3Adapter.sol#L464)

- [ ] ID-65

[AdaptiveLPVault._idleBps(AssetSnapshot,int24,uint256)](../src/core/AdaptiveLPVault.sol#L976-L978) 使用了危险的严格相等判断：
- [totalNav == 0](../src/core/AdaptiveLPVault.sol#L977)

- [ ] ID-66

[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L885-L905) 使用了危险的严格相等判断：
- [expectedVenue == VenueType.UNISWAP_V2](../src/core/AdaptiveLPVault.sol#L890)

- [ ] ID-67

[AdaptiveLPVault._validateActivePosition(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L908-L922) 使用了危险的严格相等判断：
- [position.positionId == 0](../src/core/AdaptiveLPVault.sol#L917)

- [ ] ID-68

[AdaptiveLPVault._validateActivePositionAfterPartialExit()](../src/core/AdaptiveLPVault.sol#L935-L938) 使用了危险的严格相等判断：
- [position.liquidity == 0](../src/core/AdaptiveLPVault.sol#L937)

- [ ] ID-69

[AdaptiveLPVault._isV3Venue(VenueType)](../src/core/AdaptiveLPVault.sol#L1146-L1148) 使用了危险的严格相等判断：
- [venue == VenueType.UNISWAP_V3_LOW_FEE || venue == VenueType.UNISWAP_V3_HIGH_FEE](../src/core/AdaptiveLPVault.sol#L1147)

- [ ] ID-70

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 使用了危险的严格相等判断：
- [plan.targetVenue == VenueType.IDLE](../src/core/AdaptiveLPVault.sol#L386)

- [ ] ID-71

[AdaptiveLPVault._activePositionSnapshot()](../src/core/AdaptiveLPVault.sol#L626-L630) 使用了危险的严格相等判断：
- [activeVenue == VenueType.IDLE](../src/core/AdaptiveLPVault.sol#L627)

- [ ] ID-72

[UniswapV3Adapter._validateManagedPosition(uint256,int24,int24)](../src/adapters/UniswapV3Adapter.sol#L463-L469) 使用了危险的严格相等判断：
- [current.tickLower != expectedLower || current.tickUpper != expectedUpper || current.liquidity == 0](../src/adapters/UniswapV3Adapter.sol#L466)

- [ ] ID-73

[UniswapV2Adapter.withdraw(uint256,uint256)](../src/adapters/UniswapV2Adapter.sol#L187-L202) 使用了危险的严格相等判断：
- [liquidityToBurn == 0](../src/adapters/UniswapV2Adapter.sol#L199)

<a id="reentrancy-no-eth"></a>
## 不涉及原生 ETH 转账的重入（reentrancy-no-eth）

影响等级：中  
置信度：中

- [ ] ID-74

[UniswapV3Adapter.withdrawAll()](../src/adapters/UniswapV3Adapter.sol#L341-L350) 中存在重入：
- 外部调用：
  - [(amount0,amount1) = _decreaseAndCollect(tokenId,current.liquidity)](../src/adapters/UniswapV3Adapter.sol#L346)
    - [_POSITION_MANAGER.decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams({tokenId:tokenId,liquidity:liquidityToRemove,amount0Min:0,amount1Min:0,deadline:block.timestamp}))](../src/adapters/UniswapV3Adapter.sol#L423-L427)
    - [_POSITION_MANAGER.collect(INonfungiblePositionManager.CollectParams({tokenId:tokenId,recipient:_VAULT,amount0Max:type()(uint128).max,amount1Max:type()(uint128).max}))](../src/adapters/UniswapV3Adapter.sol#L433-L437)
  - [_POSITION_MANAGER.burn(tokenId)](../src/adapters/UniswapV3Adapter.sol#L348)
- 在上述调用之后写入的状态变量：
  - [_positionId = 0](../src/adapters/UniswapV3Adapter.sol#L349)
- [UniswapV3Adapter._positionId](../src/adapters/UniswapV3Adapter.sol#L37) 可在跨函数重入中被以下函数使用：
  - [UniswapV3Adapter._snapshot()](../src/adapters/UniswapV3Adapter.sol#L353-L386)
  - [UniswapV3Adapter.positionId()](../src/adapters/UniswapV3Adapter.sol#L194-L196)

- [ ] ID-75

[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L233-L315) 中存在重入：
- 外部调用：
  - [_POSITION_MANAGER.burn(tokenId)](../src/adapters/UniswapV3Adapter.sol#L252)
- 在上述调用之后写入的状态变量：
  - [_positionId = 0](../src/adapters/UniswapV3Adapter.sol#L253)
- [UniswapV3Adapter._positionId](../src/adapters/UniswapV3Adapter.sol#L37) 可在跨函数重入中被以下函数使用：
  - [UniswapV3Adapter._snapshot()](../src/adapters/UniswapV3Adapter.sol#L353-L386)
  - [UniswapV3Adapter.positionId()](../src/adapters/UniswapV3Adapter.sol#L194-L196)

- [ ] ID-76

[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](../src/core/AdaptiveLPVault.sol#L361-L431) 中存在重入：
- 外部调用：
  - [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](../src/core/AdaptiveLPVault.sol#L388)
    - [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](../src/core/AdaptiveLPVault.sol#L638)
  - [_exitActivePosition(current.adapter)](../src/core/AdaptiveLPVault.sol#L389)
    - [IPositionAdapter(adapter).withdrawAll()](../src/core/AdaptiveLPVault.sol#L732)
  - [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](../src/core/AdaptiveLPVault.sol#L404)
    - [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](../src/core/AdaptiveLPVault.sol#L777-L779)
  - [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](../src/core/AdaptiveLPVault.sol#L407-L409)
    - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 在上述调用之后写入的状态变量及其跨函数重入使用位置：
  - [_commitPlan(plan)](../src/core/AdaptiveLPVault.sol#L429)
    - [_lastExecutedPlan = plan](../src/core/AdaptiveLPVault.sol#L832)
    - [AdaptiveLPVault._lastExecutedPlan](../src/core/AdaptiveLPVault.sol#L91) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.lastExecutedPlan()](../src/core/AdaptiveLPVault.sol#L482-L484)
  - [activeVenue = plan.targetVenue](../src/core/AdaptiveLPVault.sol#L410)
    - [AdaptiveLPVault.activeVenue](../src/core/AdaptiveLPVault.sol#L87) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._activePositionSnapshot()](../src/core/AdaptiveLPVault.sol#L626-L630)
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.activeVenue](../src/core/AdaptiveLPVault.sol#L87)
  - [_commitPlan(plan)](../src/core/AdaptiveLPVault.sol#L429)
    - [lastPositionChangeAt = _timestamp32()](../src/core/AdaptiveLPVault.sol#L833)
    - [AdaptiveLPVault.lastPositionChangeAt](../src/core/AdaptiveLPVault.sol#L88) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault.lastPositionChangeAt](../src/core/AdaptiveLPVault.sol#L88)
  - [_commitPlan(plan)](../src/core/AdaptiveLPVault.sol#L429)
    - [planVersion = plan.version](../src/core/AdaptiveLPVault.sol#L831)
    - [AdaptiveLPVault.planVersion](../src/core/AdaptiveLPVault.sol#L89) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.planVersion](../src/core/AdaptiveLPVault.sol#L89)

- [ ] ID-77

[AdaptiveLPVault.emergencyExitToIdle()](../src/core/AdaptiveLPVault.sol#L434-L457) 中存在重入：
- 外部调用：
  - [position = _synchronizeFees(adapter)](../src/core/AdaptiveLPVault.sol#L441)
    - [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](../src/core/AdaptiveLPVault.sol#L638)
  - [_exitActivePosition(adapter)](../src/core/AdaptiveLPVault.sol#L443)
    - [IPositionAdapter(adapter).withdrawAll()](../src/core/AdaptiveLPVault.sol#L732)
- 在上述调用之后写入的状态变量：
  - [activeVenue = VenueType.IDLE](../src/core/AdaptiveLPVault.sol#L444)
- [AdaptiveLPVault.activeVenue](../src/core/AdaptiveLPVault.sol#L87) 可在跨函数重入中被以下函数使用：
  - [AdaptiveLPVault._activePositionSnapshot()](../src/core/AdaptiveLPVault.sol#L626-L630)
  - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
  - [AdaptiveLPVault.activeVenue](../src/core/AdaptiveLPVault.sol#L87)

- [ ] ID-78

[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L233-L315) 中存在重入：
- 外部调用：
  - [_POSITION_MANAGER.burn(tokenId)](../src/adapters/UniswapV3Adapter.sol#L252)
  - [(tokenId,liquidityCreated,used0,used1) = _POSITION_MANAGER.mint(INonfungiblePositionManager.MintParams({token0:_TOKEN0,token1:_TOKEN1,fee:_FEE_TIER,tickLower:plan.tickLower,tickUpper:plan.tickUpper,amount0Desired:desired0,amount1Desired:desired1,amount0Min:0,amount1Min:0,recipient:address(this),deadline:block.timestamp}))](../src/adapters/UniswapV3Adapter.sol#L272-L286)
- 在上述调用之后写入的状态变量：
  - [_positionId = tokenId](../src/adapters/UniswapV3Adapter.sol#L288)
- [UniswapV3Adapter._positionId](../src/adapters/UniswapV3Adapter.sol#L37) 可在跨函数重入中被以下函数使用：
  - [UniswapV3Adapter._snapshot()](../src/adapters/UniswapV3Adapter.sol#L353-L386)
  - [UniswapV3Adapter.positionId()](../src/adapters/UniswapV3Adapter.sol#L194-L196)

- [ ] ID-79

[AdaptiveLPVault.bootstrap(uint256,uint256,address)](../src/core/AdaptiveLPVault.sol#L167-L220) 中存在重入：
- 外部调用：
  - [_depositToAdapter(adapter,plan,amount0,amount1)](../src/core/AdaptiveLPVault.sol#L197)
    - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 在上述调用之后写入的状态变量及其跨函数重入使用位置：
  - [_lastExecutedPlan = plan](../src/core/AdaptiveLPVault.sol#L209)
    - [AdaptiveLPVault._lastExecutedPlan](../src/core/AdaptiveLPVault.sol#L91) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.lastExecutedPlan()](../src/core/AdaptiveLPVault.sol#L482-L484)
  - [activeVenue = plan.targetVenue](../src/core/AdaptiveLPVault.sol#L199)
    - [AdaptiveLPVault.activeVenue](../src/core/AdaptiveLPVault.sol#L87) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._activePositionSnapshot()](../src/core/AdaptiveLPVault.sol#L626-L630)
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.activeVenue](../src/core/AdaptiveLPVault.sol#L87)
  - [initialized = true](../src/core/AdaptiveLPVault.sol#L211)
    - [AdaptiveLPVault.initialized](../src/core/AdaptiveLPVault.sol#L86) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._requireInitialized()](../src/core/AdaptiveLPVault.sol#L589-L591)
      - [AdaptiveLPVault.initialized](../src/core/AdaptiveLPVault.sol#L86)
  - [planVersion = plan.version](../src/core/AdaptiveLPVault.sol#L208)
    - [AdaptiveLPVault.planVersion](../src/core/AdaptiveLPVault.sol#L89) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.planVersion](../src/core/AdaptiveLPVault.sol#L89)

- [ ] ID-80

[AdaptiveLPVault.rebalance(bytes32,uint32)](../src/core/AdaptiveLPVault.sol#L313-L358) 中存在重入：
- 外部调用：
  - [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](../src/core/AdaptiveLPVault.sol#L328)
    - [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](../src/core/AdaptiveLPVault.sol#L638)
  - [_exitActivePosition(current.adapter)](../src/core/AdaptiveLPVault.sol#L329)
    - [IPositionAdapter(adapter).withdrawAll()](../src/core/AdaptiveLPVault.sol#L732)
  - [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](../src/core/AdaptiveLPVault.sol#L333-L335)
    - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 在上述调用之后写入的状态变量及其跨函数重入使用位置：
  - [_commitPlan(plan)](../src/core/AdaptiveLPVault.sol#L356)
    - [_lastExecutedPlan = plan](../src/core/AdaptiveLPVault.sol#L832)
    - [AdaptiveLPVault._lastExecutedPlan](../src/core/AdaptiveLPVault.sol#L91) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.lastExecutedPlan()](../src/core/AdaptiveLPVault.sol#L482-L484)
  - [activeVenue = plan.targetVenue](../src/core/AdaptiveLPVault.sol#L337)
    - [AdaptiveLPVault.activeVenue](../src/core/AdaptiveLPVault.sol#L87) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._activePositionSnapshot()](../src/core/AdaptiveLPVault.sol#L626-L630)
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.activeVenue](../src/core/AdaptiveLPVault.sol#L87)
  - [_commitPlan(plan)](../src/core/AdaptiveLPVault.sol#L356)
    - [lastPositionChangeAt = _timestamp32()](../src/core/AdaptiveLPVault.sol#L833)
    - [AdaptiveLPVault.lastPositionChangeAt](../src/core/AdaptiveLPVault.sol#L88) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault.lastPositionChangeAt](../src/core/AdaptiveLPVault.sol#L88)
  - [_commitPlan(plan)](../src/core/AdaptiveLPVault.sol#L356)
    - [planVersion = plan.version](../src/core/AdaptiveLPVault.sol#L831)
    - [AdaptiveLPVault.planVersion](../src/core/AdaptiveLPVault.sol#L89) 可在跨函数重入中被以下函数使用：
      - [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L661-L683)
      - [AdaptiveLPVault.planVersion](../src/core/AdaptiveLPVault.sol#L89)

<a id="uninitialized-local"></a>
## 未初始化的局部变量（uninitialized-local）

影响等级：中  
置信度：中

- [ ] ID-81

[UniswapV3Adapter.constructor(PositionAdapterConfig).poolToken1](../src/adapters/UniswapV3Adapter.sol#L83) 是一个从未初始化的局部变量。

- [ ] ID-82

[CanonicalV3Oracle.snapshot().tickCumulatives](../src/oracle/CanonicalV3Oracle.sol#L166) 是一个从未初始化的局部变量。

- [ ] ID-83

[AdaptiveLPVault._readAndValidateOracleBinding(address,address).poolToken0](../src/core/AdaptiveLPVault.sol#L1076) 是一个从未初始化的局部变量。

- [ ] ID-84

[UniswapV2Adapter.constructor(PositionAdapterConfig).pairFactory](../src/adapters/UniswapV2Adapter.sol#L50) 是一个从未初始化的局部变量。

- [ ] ID-85

[UniswapV2Adapter.constructor(PositionAdapterConfig).registeredPair](../src/adapters/UniswapV2Adapter.sol#L77) 是一个从未初始化的局部变量。

- [ ] ID-86

[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address).poolTickSpacing](../src/control/AdapterRegistry.sol#L265) 是一个从未初始化的局部变量。

- [ ] ID-87

[UniswapV3Adapter.constructor(PositionAdapterConfig).managerFactory](../src/adapters/UniswapV3Adapter.sol#L85) 是一个从未初始化的局部变量。

- [ ] ID-88

[UniswapV2Adapter.constructor(PositionAdapterConfig).pairToken0](../src/adapters/UniswapV2Adapter.sol#L48) 是一个从未初始化的局部变量。

- [ ] ID-89

[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address).poolFeeTier](../src/control/AdapterRegistry.sol#L264) 是一个从未初始化的局部变量。

- [ ] ID-90

[UniswapV2Adapter.constructor(PositionAdapterConfig).pairToken1](../src/adapters/UniswapV2Adapter.sol#L49) 是一个从未初始化的局部变量。

- [ ] ID-91

[UniswapV3Adapter.constructor(PositionAdapterConfig).poolFee](../src/adapters/UniswapV3Adapter.sol#L86) 是一个从未初始化的局部变量。

- [ ] ID-92

[AdapterRegistry._validateAdapterBinding(VenueType,address).poolToken1](../src/control/AdapterRegistry.sol#L179) 是一个从未初始化的局部变量。

- [ ] ID-93

[AdapterRegistry._validateAdapterBinding(VenueType,address).poolToken0](../src/control/AdapterRegistry.sol#L178) 是一个从未初始化的局部变量。

- [ ] ID-94

[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterVenue](../src/control/AdapterRegistry.sol#L137) 是一个从未初始化的局部变量。

- [ ] ID-95

[UniswapV3Adapter.constructor(PositionAdapterConfig).poolTickSpacing](../src/adapters/UniswapV3Adapter.sol#L87) 是一个从未初始化的局部变量。

- [ ] ID-96

[VaultStrategyMath.getPlan(VaultStrategyMath.PlanInputs).tickLower](../src/libraries/VaultStrategyMath.sol#L91) 是一个从未初始化的局部变量。

- [ ] ID-97

[CanonicalV3Oracle.constructor(OracleConfig).registeredPool](../src/oracle/CanonicalV3Oracle.sol#L82) 是一个从未初始化的局部变量。

- [ ] ID-98

[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address).poolFactory](../src/control/AdapterRegistry.sol#L266) 是一个从未初始化的局部变量。

- [ ] ID-99

[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterToken0](../src/control/AdapterRegistry.sol#L139) 是一个从未初始化的局部变量。

- [ ] ID-100

[ControlledSwapExecutor.constructor(SwapExecutorConfig).poolToken1](../src/swap/ControlledSwapExecutor.sol#L48) 是一个从未初始化的局部变量。

- [ ] ID-101

[ControlledSwapExecutor.constructor(SwapExecutorConfig).registeredPool](../src/swap/ControlledSwapExecutor.sol#L82) 是一个从未初始化的局部变量。

- [ ] ID-102

[UniswapV3Adapter.constructor(PositionAdapterConfig).registeredPool](../src/adapters/UniswapV3Adapter.sol#L133) 是一个从未初始化的局部变量。

- [ ] ID-103

[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterVault](../src/control/AdapterRegistry.sol#L136) 是一个从未初始化的局部变量。

- [ ] ID-104

[CanonicalV3Oracle.constructor(OracleConfig).factory_](../src/oracle/CanonicalV3Oracle.sol#L43) 是一个从未初始化的局部变量。

- [ ] ID-105

[AdapterRegistry._validateV2Pool(address,address,address,uint24,int24,address).registeredPool](../src/control/AdapterRegistry.sol#L247) 是一个从未初始化的局部变量。

- [ ] ID-106

[ControlledSwapExecutor.constructor(SwapExecutorConfig).routerFactory](../src/swap/ControlledSwapExecutor.sol#L90) 是一个从未初始化的局部变量。

- [ ] ID-107

[CanonicalV3Oracle.constructor(OracleConfig).tickSpacing_](../src/oracle/CanonicalV3Oracle.sol#L45) 是一个从未初始化的局部变量。

- [ ] ID-108

[AdapterRegistry._validateV2Pool(address,address,address,uint24,int24,address).poolFactory](../src/control/AdapterRegistry.sol#L239) 是一个从未初始化的局部变量。

- [ ] ID-109

[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterTickSpacing](../src/control/AdapterRegistry.sol#L142) 是一个从未初始化的局部变量。

- [ ] ID-110

[ControlledSwapExecutor.constructor(SwapExecutorConfig).poolToken0](../src/swap/ControlledSwapExecutor.sol#L47) 是一个从未初始化的局部变量。

- [ ] ID-111

[ControlledSwapExecutor.constructor(SwapExecutorConfig).poolFee](../src/swap/ControlledSwapExecutor.sol#L50) 是一个从未初始化的局部变量。

- [ ] ID-112

[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterToken1](../src/control/AdapterRegistry.sol#L140) 是一个从未初始化的局部变量。

- [ ] ID-113

[UniswapV3Adapter.constructor(PositionAdapterConfig).poolFactory](../src/adapters/UniswapV3Adapter.sol#L84) 是一个从未初始化的局部变量。

- [ ] ID-114

[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address).registeredPool](../src/control/AdapterRegistry.sol#L290) 是一个从未初始化的局部变量。

- [ ] ID-115

[ControlledSwapExecutor.constructor(SwapExecutorConfig).poolFactory](../src/swap/ControlledSwapExecutor.sol#L49) 是一个从未初始化的局部变量。

- [ ] ID-116

[CanonicalV3Oracle.snapshot().spotTick](../src/oracle/CanonicalV3Oracle.sol#L146) 是一个从未初始化的局部变量。

- [ ] ID-117

[CanonicalV3Oracle.constructor(OracleConfig).token1_](../src/oracle/CanonicalV3Oracle.sol#L42) 是一个从未初始化的局部变量。

- [ ] ID-118

[CanonicalV3Oracle.constructor(OracleConfig).fee_](../src/oracle/CanonicalV3Oracle.sol#L44) 是一个从未初始化的局部变量。

- [ ] ID-119

[CanonicalV3Oracle.constructor(OracleConfig).token0_](../src/oracle/CanonicalV3Oracle.sol#L41) 是一个从未初始化的局部变量。

- [ ] ID-120

[CanonicalV3Oracle.snapshot().secondsPerLiquidityCumulativeX128s](../src/oracle/CanonicalV3Oracle.sol#L167) 是一个从未初始化的局部变量。

- [ ] ID-121

[AdaptiveLPVault._readAndValidateOracleBinding(address,address).poolToken1](../src/core/AdaptiveLPVault.sol#L1077) 是一个从未初始化的局部变量。

- [ ] ID-122

[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterFeeTier](../src/control/AdapterRegistry.sol#L141) 是一个从未初始化的局部变量。

- [ ] ID-123

[UniswapV3Adapter.constructor(PositionAdapterConfig).poolToken0](../src/adapters/UniswapV3Adapter.sol#L82) 是一个从未初始化的局部变量。

- [ ] ID-124

[VaultStrategyMath.getPlan(VaultStrategyMath.PlanInputs).tickUpper](../src/libraries/VaultStrategyMath.sol#L92) 是一个从未初始化的局部变量。

- [ ] ID-125

[AdaptiveLPVault._readAndValidateOracleBinding(address,address).poolFactory](../src/core/AdaptiveLPVault.sol#L1075) 是一个从未初始化的局部变量。

- [ ] ID-126

[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterPool](../src/control/AdapterRegistry.sol#L138) 是一个从未初始化的局部变量。

- [ ] ID-127

[AdaptiveLPVault._readAndValidateOracleBinding(address,address).poolFee](../src/core/AdaptiveLPVault.sol#L1078) 是一个从未初始化的局部变量。

<a id="unused-return"></a>
## 未使用的返回值（unused-return）

影响等级：中  
置信度：中

- [ ] ID-128

[UniswapV3Adapter._feeGrowthInside(int24,int24,int24)](../src/adapters/UniswapV3Adapter.sol#L488-L522) 在以下调用中忽略了返回值：
- [(None,None,lowerOutside0X128,lowerOutside1X128,None,None,None,None) = _POOL.ticks(tickLower)](../src/adapters/UniswapV3Adapter.sol#L495)

- [ ] ID-129

[UniswapV3Adapter._snapshot()](../src/adapters/UniswapV3Adapter.sol#L353-L386) 在以下调用中忽略了返回值：
- [(sqrtPriceX96,currentTick,None,None,None,None,None) = _POOL.slot0()](../src/adapters/UniswapV3Adapter.sol#L366)

- [ ] ID-130

[UniswapV3Adapter._readPosition(uint256)](../src/adapters/UniswapV3Adapter.sol#L441-L460) 在以下调用中忽略了返回值：
- [(None,None,current.token0,current.token1,current.fee,current.tickLower,current.tickUpper,current.liquidity,current.feeGrowthInside0LastX128,current.feeGrowthInside1LastX128,current.tokensOwed0,current.tokensOwed1) = _POSITION_MANAGER.positions(tokenId)](../src/adapters/UniswapV3Adapter.sol#L442-L454)

- [ ] ID-131

[UniswapV2Adapter.snapshot()](../src/adapters/UniswapV2Adapter.sol#L128-L145) 在以下调用中忽略了返回值：
- [(reserve0,reserve1,None) = _PAIR.getReserves()](../src/adapters/UniswapV2Adapter.sol#L137)

- [ ] ID-132

[UniswapV3Adapter._previewDeposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L389-L404) 在以下调用中忽略了返回值：
- [(sqrtPriceX96,None,None,None,None,None,None) = _POOL.slot0()](../src/adapters/UniswapV3Adapter.sol#L397)

- [ ] ID-133

[ControlledSwapExecutor.executeSwap(SwapPlan)](../src/swap/ControlledSwapExecutor.sol#L108-L161) 在以下调用中忽略了返回值：
- [_ROUTER.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({tokenIn:tokenIn,tokenOut:tokenOut,fee:_FEE_TIER,recipient:_VAULT,deadline:uint256(plan.deadline),amountIn:plan.amountIn,amountOutMinimum:plan.minAmountOut,sqrtPriceLimitX96:0}))](../src/swap/ControlledSwapExecutor.sol#L128-L139)

- [ ] ID-134

[AdaptiveLPVault._checkManagerOrKeeper()](../src/core/AdaptiveLPVault.sol#L499-L501) 在以下调用中忽略了返回值：
- [vaultControl.checkManagerOrKeeper(_msgSender())](../src/core/AdaptiveLPVault.sol#L500)

- [ ] ID-135

[AdaptiveLPVault._depositToAdapter(address,PositionPlan,uint256,uint256)](../src/core/AdaptiveLPVault.sol#L743-L762) 在以下调用中忽略了返回值：
- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)

- [ ] ID-136

[UniswapV3Adapter._feeGrowthInside(int24,int24,int24)](../src/adapters/UniswapV3Adapter.sol#L488-L522) 在以下调用中忽略了返回值：
- [(None,None,upperOutside0X128,upperOutside1X128,None,None,None,None) = _POOL.ticks(tickUpper)](../src/adapters/UniswapV3Adapter.sol#L496)

- [ ] ID-137

[CanonicalV3Oracle.snapshot()](../src/oracle/CanonicalV3Oracle.sol#L139-L211) 在以下调用中忽略了返回值：
- [(sqrtPriceX96,tick) = _POOL.slot0()](../src/oracle/CanonicalV3Oracle.sol#L147-L154)

- [ ] ID-138

[UniswapV2Adapter._burnLiquidity(uint256)](../src/adapters/UniswapV2Adapter.sol#L250-L259) 在以下调用中忽略了返回值：
- [_PAIR.burn(_VAULT)](../src/adapters/UniswapV2Adapter.sol#L255)

- [ ] ID-139

[AdaptiveLPVault._pauseAll(address)](../src/core/AdaptiveLPVault.sol#L519-L521) 在以下调用中忽略了返回值：
- [vaultControl.pauseAll(caller)](../src/core/AdaptiveLPVault.sol#L520)

- [ ] ID-140

[UniswapV3Adapter._decreaseLiquidity(uint256,uint128)](../src/adapters/UniswapV3Adapter.sol#L422-L428) 在以下调用中忽略了返回值：
- [_POSITION_MANAGER.decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams({tokenId:tokenId,liquidity:liquidityToRemove,amount0Min:0,amount1Min:0,deadline:block.timestamp}))](../src/adapters/UniswapV3Adapter.sol#L423-L427)

- [ ] ID-141

[UniswapV2Adapter._previewDeposit(uint256,uint256)](../src/adapters/UniswapV2Adapter.sol#L225-L244) 在以下调用中忽略了返回值：
- [(reserve0,reserve1,None) = _PAIR.getReserves()](../src/adapters/UniswapV2Adapter.sol#L232)

- [ ] ID-142

[AdaptiveLPVault._checkManagerOrGuardian()](../src/core/AdaptiveLPVault.sol#L495-L497) 在以下调用中忽略了返回值：
- [vaultControl.checkManagerOrGuardian(_msgSender())](../src/core/AdaptiveLPVault.sol#L496)

- [ ] ID-143

[AdaptiveLPVault._exitActivePosition(address)](../src/core/AdaptiveLPVault.sol#L730-L740) 在以下调用中忽略了返回值：
- [IPositionAdapter(adapter).withdrawAll()](../src/core/AdaptiveLPVault.sol#L732)

- [ ] ID-144

[UniswapV3Adapter._collectAll(uint256)](../src/adapters/UniswapV3Adapter.sol#L432-L438) 在以下调用中忽略了返回值：
- [_POSITION_MANAGER.collect(INonfungiblePositionManager.CollectParams({tokenId:tokenId,recipient:_VAULT,amount0Max:type()(uint128).max,amount1Max:type()(uint128).max}))](../src/adapters/UniswapV3Adapter.sol#L433-L437)

<a id="events-maths"></a>
## 数值状态变更缺少事件（events-maths）

影响等级：低  
置信度：中

- [ ] ID-145

[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L233-L315) 应针对以下状态变更发出事件：
- [_positionId = 0](../src/adapters/UniswapV3Adapter.sol#L253)
- [_positionId = tokenId](../src/adapters/UniswapV3Adapter.sol#L288)

<a id="calls-loop"></a>
## 循环中的外部调用（calls-loop）

影响等级：低  
置信度：中

- [ ] ID-146

[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L885-L905) 在循环内进行了外部调用：[position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](../src/core/AdaptiveLPVault.sol#L899)。
- 包含该循环的调用栈：
  - `AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)`

- [ ] ID-147

[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L885-L905) 在循环内进行了外部调用：[position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](../src/core/AdaptiveLPVault.sol#L899)。
- 包含该循环的调用栈：
  - `AdaptiveLPVault.emergencyExitToIdle()`

- [ ] ID-148

[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L885-L905) 在循环内进行了外部调用：[position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](../src/core/AdaptiveLPVault.sol#L899)。
- 包含该循环的调用栈：
  - `AdaptiveLPVault.rebalance(bytes32,uint32)`

- [ ] ID-149

[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L885-L905) 在循环内进行了外部调用：[position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](../src/core/AdaptiveLPVault.sol#L899)。
- 包含该循环的调用栈：
  - `AdaptiveLPVault.deposit(uint256,uint256,uint256,address)`

- [ ] ID-150

[AdaptiveLPVault._getAdapterOrRevert(VenueType)](../src/core/AdaptiveLPVault.sol#L511-L513) 在循环内进行了外部调用：[vaultControl.getAdapterOrRevert(venue)](../src/core/AdaptiveLPVault.sol#L512)。
- 包含该循环的调用栈：
  - `AdaptiveLPVault.bootstrap(uint256,uint256,address)`
  - `AdaptiveLPVault._validateManagedV3PositionsEmpty()`

- [ ] ID-151

[AdaptiveLPVault._validateManagedV3PositionsEmpty()](../src/core/AdaptiveLPVault.sol#L924-L933) 在循环内进行了外部调用：[position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](../src/core/AdaptiveLPVault.sol#L928)。
- 包含该循环的调用栈：
  - `AdaptiveLPVault.bootstrap(uint256,uint256,address)`

- [ ] ID-152

[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](../src/core/AdaptiveLPVault.sol#L885-L905) 在循环内进行了外部调用：[position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](../src/core/AdaptiveLPVault.sol#L899)。
- 包含该循环的调用栈：
  - `AdaptiveLPVault.bootstrap(uint256,uint256,address)`

<a id="reentrancy-benign"></a>
## 良性重入（reentrancy-benign）

影响等级：低  
置信度：中

- [ ] ID-153

[AdaptiveLPVault.emergencyExitToIdle()](../src/core/AdaptiveLPVault.sol#L434-L457) 中存在重入：
- 外部调用：
  - [position = _synchronizeFees(adapter)](../src/core/AdaptiveLPVault.sol#L441)
    - [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](../src/core/AdaptiveLPVault.sol#L638)
  - [_exitActivePosition(adapter)](../src/core/AdaptiveLPVault.sol#L443)
    - [IPositionAdapter(adapter).withdrawAll()](../src/core/AdaptiveLPVault.sol#L732)
- 在上述调用之后写入的状态变量：
  - [++ planVersion](../src/core/AdaptiveLPVault.sol#L451)

- [ ] ID-154

[AdaptiveLPVault.bootstrap(uint256,uint256,address)](../src/core/AdaptiveLPVault.sol#L167-L220) 中存在重入：
- 外部调用：
  - [_depositToAdapter(adapter,plan,amount0,amount1)](../src/core/AdaptiveLPVault.sol#L197)
    - [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](../src/core/AdaptiveLPVault.sol#L751)
- 在上述调用之后写入的状态变量：
  - [lastPositionChangeAt = _timestamp32()](../src/core/AdaptiveLPVault.sol#L210)

<a id="timestamp"></a>
## 时间戳相关比较（timestamp）

影响等级：低  
置信度：中

- [ ] ID-155

[ControlledSwapExecutor.executeSwap(SwapPlan)](../src/swap/ControlledSwapExecutor.sol#L108-L161) 使用时间戳进行比较。
- 危险的比较：
  - [block.timestamp > plan.deadline](../src/swap/ControlledSwapExecutor.sol#L112)

- [ ] ID-156

[UniswapV3Adapter._readPosition(uint256)](../src/adapters/UniswapV3Adapter.sol#L441-L460) 使用时间戳进行比较。
- 危险的比较：
  - [current.token0 != _TOKEN0 || current.token1 != _TOKEN1 || current.fee != _FEE_TIER](../src/adapters/UniswapV3Adapter.sol#L456)

- [ ] ID-157

[UniswapV3Adapter._validateRange(int24,int24)](../src/adapters/UniswapV3Adapter.sol#L478-L485) 使用时间戳进行比较。
- 危险的比较：
  - [tickLower < MIN_TICK || tickUpper > MAX_TICK || tickLower >= tickUpper || tickLower % _TICK_SPACING != 0 || tickUpper % _TICK_SPACING != 0](../src/adapters/UniswapV3Adapter.sol#L480-L481)

- [ ] ID-158

[UniswapV3Adapter._decreaseAndCollect(uint256,uint128)](../src/adapters/UniswapV3Adapter.sol#L407-L419) 使用时间戳进行比较。
- 危险的比较：
  - [liquidityToRemove != 0](../src/adapters/UniswapV3Adapter.sol#L414)

- [ ] ID-159

[UniswapV3Adapter.syncFees()](../src/adapters/UniswapV3Adapter.sol#L204-L220) 使用时间戳进行比较。
- 危险的比较：
  - [afterSnapshot.claimableFee0 != 0 || afterSnapshot.claimableFee1 != 0](../src/adapters/UniswapV3Adapter.sol#L217)

- [ ] ID-160

[UniswapV3Adapter._snapshot()](../src/adapters/UniswapV3Adapter.sol#L353-L386) 使用时间戳进行比较。
- 危险的比较：
  - [tokenId == 0](../src/adapters/UniswapV3Adapter.sol#L358)

- [ ] ID-161

[UniswapV3Adapter._feeGrowthInside(int24,int24,int24)](../src/adapters/UniswapV3Adapter.sol#L488-L522) 使用时间戳进行比较。
- 危险的比较：
  - [currentTick >= tickLower](../src/adapters/UniswapV3Adapter.sol#L503)
  - [currentTick < tickUpper](../src/adapters/UniswapV3Adapter.sol#L511)

- [ ] ID-162

[AdaptiveLPVault._timestamp32()](../src/core/AdaptiveLPVault.sol#L1141-L1144) 使用时间戳进行比较。
- 危险的比较：
  - [block.timestamp > type()(uint32).max](../src/core/AdaptiveLPVault.sol#L1142)

- [ ] ID-163

[UniswapV3Adapter.withdraw(uint256,uint256)](../src/adapters/UniswapV3Adapter.sol#L318-L338) 使用时间戳进行比较。
- 危险的比较：
  - [liquidityToRemove == 0](../src/adapters/UniswapV3Adapter.sol#L333)

- [ ] ID-164

[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L233-L315) 使用时间戳进行比较。
- 危险的比较：
  - [desired0 == 0 && desired1 == 0](../src/adapters/UniswapV3Adapter.sol#L241)
  - [tokenId != 0](../src/adapters/UniswapV3Adapter.sol#L244)
  - [current.liquidity != 0](../src/adapters/UniswapV3Adapter.sol#L246)
  - [current.tickLower != plan.tickLower || current.tickUpper != plan.tickUpper](../src/adapters/UniswapV3Adapter.sol#L247)
  - [current.tokensOwed0 != 0 || current.tokensOwed1 != 0](../src/adapters/UniswapV3Adapter.sol#L251)
  - [desired0 != 0](../src/adapters/UniswapV3Adapter.sol#L261)
  - [desired1 != 0](../src/adapters/UniswapV3Adapter.sol#L265)
  - [tokenId == 0](../src/adapters/UniswapV3Adapter.sol#L270)
  - [desired0 != 0](../src/adapters/UniswapV3Adapter.sol#L305)
  - [desired1 != 0](../src/adapters/UniswapV3Adapter.sol#L306)
  - [used0 > desired0](../src/adapters/UniswapV3Adapter.sol#L308)
  - [used1 > desired1](../src/adapters/UniswapV3Adapter.sol#L309)
  - [desired0 > used0](../src/adapters/UniswapV3Adapter.sol#L310)
  - [desired1 > used1](../src/adapters/UniswapV3Adapter.sol#L311)

- [ ] ID-165

[UniswapV3Adapter._amountsForLiquidityAtPrices(uint160,uint160,uint160,uint128,bool)](../src/adapters/UniswapV3Adapter.sol#L564-L579) 使用时间戳进行比较。
- 危险的比较：
  - [sqrtPriceX96 <= sqrtLowerX96](../src/adapters/UniswapV3Adapter.sol#L571)
  - [sqrtPriceX96 < sqrtUpperX96](../src/adapters/UniswapV3Adapter.sol#L573)

- [ ] ID-166

[AdaptiveLPVault._requireDeadline(uint32)](../src/core/AdaptiveLPVault.sol#L1132-L1134) 使用时间戳进行比较。
- 危险的比较：
  - [deadline == 0 || block.timestamp > deadline](../src/core/AdaptiveLPVault.sol#L1133)

- [ ] ID-167

[AdaptiveLPVault._requireCooldown()](../src/core/AdaptiveLPVault.sol#L1136-L1139) 使用时间戳进行比较。
- 危险的比较：
  - [block.timestamp < availableAt](../src/core/AdaptiveLPVault.sol#L1138)

- [ ] ID-168

[UniswapV3Adapter._validateManagedPosition(uint256,int24,int24)](../src/adapters/UniswapV3Adapter.sol#L463-L469) 使用时间戳进行比较。
- 危险的比较：
  - [tokenId == 0 || _POSITION_MANAGER.ownerOf(tokenId) != address(this)](../src/adapters/UniswapV3Adapter.sol#L464)
  - [current.tickLower != expectedLower || current.tickUpper != expectedUpper || current.liquidity == 0](../src/adapters/UniswapV3Adapter.sol#L466)

<a id="cyclomatic-complexity"></a>
## 圈复杂度过高（cyclomatic-complexity）

影响等级：提示信息  
置信度：高

- [ ] ID-169

[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](../src/adapters/UniswapV3Adapter.sol#L233-L315) 的圈复杂度较高（14）。

- [ ] ID-170

[AdapterRegistry._validateAdapterBinding(VenueType,address)](../src/control/AdapterRegistry.sol#L126-L216) 的圈复杂度较高（26）。

- [ ] ID-171

[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address)](../src/control/AdapterRegistry.sol#L256-L297) 的圈复杂度较高（13）。

- [ ] ID-172

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 的圈复杂度较高（25）。

- [ ] ID-173

[ControlledSwapExecutor.constructor(SwapExecutorConfig)](../src/swap/ControlledSwapExecutor.sol#L40-L105) 的圈复杂度较高（22）。

- [ ] ID-174

[UniswapV2Adapter.constructor(PositionAdapterConfig)](../src/adapters/UniswapV2Adapter.sol#L38-L90) 的圈复杂度较高（14）。

- [ ] ID-175

[AdaptiveLPVault._readAndValidateOracleBinding(address,address)](../src/core/AdaptiveLPVault.sol#L1023-L1121) 的圈复杂度较高（30）。

- [ ] ID-176

[UniswapV3Adapter.constructor(PositionAdapterConfig)](../src/adapters/UniswapV3Adapter.sol#L70-L151) 的圈复杂度较高（21）。

- [ ] ID-177

[CanonicalV3Oracle.constructor(OracleConfig)](../src/oracle/CanonicalV3Oracle.sol#L29-L101) 的圈复杂度较高（18）。

<a id="dead-code"></a>
## 未使用的代码（dead-code）

影响等级：提示信息  
置信度：中

- [ ] ID-178

[VaultRoles._checkManagerOrKeeper()](../src/control/VaultRoles.sol#L45-L49) 从未被使用，应予移除。

<a id="naming-convention"></a>
## 命名约定（naming-convention）

影响等级：提示信息  
置信度：高

> `mixedCase` 指首字母小写的驼峰命名法。

- [ ] ID-179

变量 [UniswapV3Adapter._TOKEN1](../src/adapters/UniswapV3Adapter.sol#L29) 未采用 `mixedCase` 命名。

- [ ] ID-180

函数 [IVaultRoles.KEEPER_ROLE()](../src/interfaces/IVaultRoles.sol#L20) 未采用 `mixedCase` 命名。

- [ ] ID-181

变量 [UniswapV2Adapter._PAIR](../src/adapters/UniswapV2Adapter.sol#L24) 未采用 `mixedCase` 命名。

- [ ] ID-182

变量 [ControlledSwapExecutor._ROUTER_ADDRESS](../src/swap/ControlledSwapExecutor.sol#L19) 未采用 `mixedCase` 命名。

- [ ] ID-183

变量 [UniswapV3Adapter._TOKEN0](../src/adapters/UniswapV3Adapter.sol#L28) 未采用 `mixedCase` 命名。

- [ ] ID-184

变量 [CanonicalV3Oracle._TOKEN1](../src/oracle/CanonicalV3Oracle.sol#L19) 未采用 `mixedCase` 命名。

- [ ] ID-185

函数 [IVaultRoles.GUARDIAN_ROLE()](../src/interfaces/IVaultRoles.sol#L24) 未采用 `mixedCase` 命名。

- [ ] ID-186

变量 [ControlledSwapExecutor._VAULT](../src/swap/ControlledSwapExecutor.sol#L18) 未采用 `mixedCase` 命名。

- [ ] ID-187

变量 [CanonicalV3Oracle._TOKEN0_DECIMALS](../src/oracle/CanonicalV3Oracle.sol#L20) 未采用 `mixedCase` 命名。

- [ ] ID-188

变量 [CanonicalV3Oracle._POOL](../src/oracle/CanonicalV3Oracle.sol#L25) 未采用 `mixedCase` 命名。

- [ ] ID-189

变量 [CanonicalV3Oracle._TOKEN0](../src/oracle/CanonicalV3Oracle.sol#L18) 未采用 `mixedCase` 命名。

- [ ] ID-190

变量 [UniswapV2Adapter._TOKEN0](../src/adapters/UniswapV2Adapter.sol#L22) 未采用 `mixedCase` 命名。

- [ ] ID-191

变量 [CanonicalV3Oracle._SHORT_TWAP_WINDOW_SECONDS](../src/oracle/CanonicalV3Oracle.sol#L23) 未采用 `mixedCase` 命名。

- [ ] ID-192

变量 [UniswapV3Adapter._TICK_SPACING](../src/adapters/UniswapV3Adapter.sol#L32) 未采用 `mixedCase` 命名。

- [ ] ID-193

变量 [ControlledSwapExecutor._SWAP_POOL](../src/swap/ControlledSwapExecutor.sol#L22) 未采用 `mixedCase` 命名。

- [ ] ID-194

变量 [UniswapV2Adapter._TOKEN1](../src/adapters/UniswapV2Adapter.sol#L23) 未采用 `mixedCase` 命名。

- [ ] ID-195

变量 [UniswapV3Adapter._VENUE](../src/adapters/UniswapV3Adapter.sol#L26) 未采用 `mixedCase` 命名。

- [ ] ID-196

变量 [UniswapV2Adapter._VAULT](../src/adapters/UniswapV2Adapter.sol#L20) 未采用 `mixedCase` 命名。

- [ ] ID-197

变量 [CanonicalV3Oracle._CANONICAL_POOL](../src/oracle/CanonicalV3Oracle.sol#L17) 未采用 `mixedCase` 命名。

- [ ] ID-198

变量 [CanonicalV3Oracle._TOKEN1_DECIMALS](../src/oracle/CanonicalV3Oracle.sol#L21) 未采用 `mixedCase` 命名。

- [ ] ID-199

变量 [UniswapV3Adapter._VAULT](../src/adapters/UniswapV3Adapter.sol#L25) 未采用 `mixedCase` 命名。

- [ ] ID-200

变量 [UniswapV2Adapter._POOL](../src/adapters/UniswapV2Adapter.sol#L21) 未采用 `mixedCase` 命名。

- [ ] ID-201

变量 [UniswapV3Adapter._FEE_TIER](../src/adapters/UniswapV3Adapter.sol#L31) 未采用 `mixedCase` 命名。

- [ ] ID-202

变量 [UniswapV3Adapter._POOL_ADDRESS](../src/adapters/UniswapV3Adapter.sol#L27) 未采用 `mixedCase` 命名。

- [ ] ID-203

变量 [UniswapV3Adapter._POSITION_MANAGER](../src/adapters/UniswapV3Adapter.sol#L35) 未采用 `mixedCase` 命名。

- [ ] ID-204

变量 [ControlledSwapExecutor._TOKEN0](../src/swap/ControlledSwapExecutor.sol#L20) 未采用 `mixedCase` 命名。

- [ ] ID-205

变量 [ControlledSwapExecutor._TOKEN1](../src/swap/ControlledSwapExecutor.sol#L21) 未采用 `mixedCase` 命名。

- [ ] ID-206

变量 [UniswapV3Adapter._POSITION_MANAGER_ADDRESS](../src/adapters/UniswapV3Adapter.sol#L30) 未采用 `mixedCase` 命名。

- [ ] ID-207

变量 [ControlledSwapExecutor._FEE_TIER](../src/swap/ControlledSwapExecutor.sol#L23) 未采用 `mixedCase` 命名。

- [ ] ID-208

函数 [IVaultRoles.DEFAULT_ADMIN_ROLE()](../src/interfaces/IVaultRoles.sol#L12) 未采用 `mixedCase` 命名。

- [ ] ID-209

变量 [ControlledSwapExecutor._ROUTER](../src/swap/ControlledSwapExecutor.sol#L25) 未采用 `mixedCase` 命名。

- [ ] ID-210

变量 [CanonicalV3Oracle._TWAP_WINDOW_SECONDS](../src/oracle/CanonicalV3Oracle.sol#L22) 未采用 `mixedCase` 命名。

- [ ] ID-211

变量 [UniswapV3Adapter._POOL](../src/adapters/UniswapV3Adapter.sol#L34) 未采用 `mixedCase` 命名。

- [ ] ID-212

函数 [IVaultRoles.MANAGER_ROLE()](../src/interfaces/IVaultRoles.sol#L16) 未采用 `mixedCase` 命名。

<a id="too-many-digits"></a>
## 数字字面量位数过多（too-many-digits）

影响等级：提示信息  
置信度：中

- [ ] ID-213

[PriceMath.sqrtRatioAtTick(int24)](../src/libraries/PriceMath.sol#L46-L81) 使用了位数过多的数字字面量：
- [ratio = 0x100000000000000000000000000000000](../src/libraries/PriceMath.sol#L52)

- [ ] ID-214

[UniswapV3Adapter.slitherConstructorConstantVariables()](../src/adapters/UniswapV3Adapter.sol#L17-L619) 使用了位数过多的数字字面量：
- [Q128 = 0x100000000000000000000000000000000](../src/adapters/UniswapV3Adapter.sol#L21)

- [ ] ID-215

[UniswapV3Adapter.slitherConstructorConstantVariables()](../src/adapters/UniswapV3Adapter.sol#L17-L619) 使用了位数过多的数字字面量：
- [Q96 = 0x1000000000000000000000000](../src/adapters/UniswapV3Adapter.sol#L20)
