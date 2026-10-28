**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [arbitrary-send-erc20](#arbitrary-send-erc20) (4 results) (High)
 - [weak-prng](#weak-prng) (1 results) (High)
 - [reentrancy-balance](#reentrancy-balance) (23 results) (High)
 - [divide-before-multiply](#divide-before-multiply) (20 results) (Medium)
 - [incorrect-equality](#incorrect-equality) (26 results) (Medium)
 - [reentrancy-no-eth](#reentrancy-no-eth) (7 results) (Medium)
 - [uninitialized-local](#uninitialized-local) (47 results) (Medium)
 - [unused-return](#unused-return) (17 results) (Medium)
 - [events-maths](#events-maths) (1 results) (Low)
 - [calls-loop](#calls-loop) (7 results) (Low)
 - [reentrancy-benign](#reentrancy-benign) (2 results) (Low)
 - [timestamp](#timestamp) (14 results) (Low)
 - [cyclomatic-complexity](#cyclomatic-complexity) (9 results) (Informational)
 - [dead-code](#dead-code) (1 results) (Informational)
 - [naming-convention](#naming-convention) (34 results) (Informational)
 - [too-many-digits](#too-many-digits) (3 results) (Informational)
## arbitrary-send-erc20
Impact: High
Confidence: High
 - [ ] ID-0
[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L233-L315) uses arbitrary from in transferFrom: [IERC20(_TOKEN0).safeTransferFrom(_VAULT,address(this),desired0)](src/adapters/UniswapV3Adapter.sol#L262)

src/adapters/UniswapV3Adapter.sol#L233-L315


 - [ ] ID-1
[UniswapV2Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV2Adapter.sol#L164-L184) uses arbitrary from in transferFrom: [IERC20(_TOKEN0).safeTransferFrom(_VAULT,_POOL,used0)](src/adapters/UniswapV2Adapter.sol#L176)

src/adapters/UniswapV2Adapter.sol#L164-L184


 - [ ] ID-2
[UniswapV2Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV2Adapter.sol#L164-L184) uses arbitrary from in transferFrom: [IERC20(_TOKEN1).safeTransferFrom(_VAULT,_POOL,used1)](src/adapters/UniswapV2Adapter.sol#L177)

src/adapters/UniswapV2Adapter.sol#L164-L184


 - [ ] ID-3
[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L233-L315) uses arbitrary from in transferFrom: [IERC20(_TOKEN1).safeTransferFrom(_VAULT,address(this),desired1)](src/adapters/UniswapV3Adapter.sol#L266)

src/adapters/UniswapV3Adapter.sol#L233-L315


## weak-prng
Impact: High
Confidence: Medium
 - [ ] ID-4
[UniswapV3Adapter._validateRange(int24,int24)](src/adapters/UniswapV3Adapter.sol#L478-L485) uses a weak PRNG: "[tickLower < MIN_TICK || tickUpper > MAX_TICK || tickLower >= tickUpper || tickLower % _TICK_SPACING != 0 || tickUpper % _TICK_SPACING != 0](src/adapters/UniswapV3Adapter.sol#L480-L481)" 

src/adapters/UniswapV3Adapter.sol#L478-L485


## reentrancy-balance
Impact: High
Confidence: Medium
 - [ ] ID-5
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](src/core/AdaptiveLPVault.sol#L404)
		- [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](src/core/AdaptiveLPVault.sol#L777-L779)
	Balance read before the call:
	- [balance0 = IERC20(token0).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L390)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `finalNav`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-6
Reentrancy in [AdaptiveLPVault._executeControlledSwap(SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L764-L796):
	External call allowing reentrancy:
	- [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](src/core/AdaptiveLPVault.sol#L777-L779)
	Balance read before the call:
	- [inputBefore = IERC20(input).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L770)
	Possible stale balance used after the call in a condition:
	- [inputAfter > inputBefore || inputBefore - inputAfter != amountIn](src/core/AdaptiveLPVault.sol#L781)
		- stale variable `inputBefore`

src/core/AdaptiveLPVault.sol#L764-L796


 - [ ] ID-7
Reentrancy in [AdaptiveLPVault.emergencyExitToIdle()](src/core/AdaptiveLPVault.sol#L434-L457):
	External call allowing reentrancy:
	- [_exitActivePosition(adapter)](src/core/AdaptiveLPVault.sol#L443)
		- [IPositionAdapter(adapter).withdrawAll()](src/core/AdaptiveLPVault.sol#L732)
	Balance read before the call:
	- [position = _synchronizeFees(adapter)](src/core/AdaptiveLPVault.sol#L441)
	Possible stale balance used after the call in a condition:
	- [planVersion == type()(uint64).max](src/core/AdaptiveLPVault.sol#L449)
		- stale variable `planVersion`

src/core/AdaptiveLPVault.sol#L434-L457


 - [ ] ID-8
Reentrancy in [AdaptiveLPVault.redeem(uint256,uint256,uint256,address,address)](src/core/AdaptiveLPVault.sol#L272-L310):
	External call allowing reentrancy:
	- [(positionOut0,positionOut1) = IPositionAdapter(adapter).withdraw(shares,supply)](src/core/AdaptiveLPVault.sol#L296)
	Balance read before the call:
	- [idle0Before = IERC20(token0).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L290)
	Possible stale balance used after the call in a condition:
	- [amount0Out < minAmount0Out || amount1Out < minAmount1Out](src/core/AdaptiveLPVault.sol#L300)
		- stale variable `amount0Out`

src/core/AdaptiveLPVault.sol#L272-L310


 - [ ] ID-9
Reentrancy in [AdaptiveLPVault._executeControlledSwap(SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L764-L796):
	External call allowing reentrancy:
	- [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](src/core/AdaptiveLPVault.sol#L777-L779)
	Balance read before the call:
	- [executorInput = IERC20(input).balanceOf(executorAddress)](src/core/AdaptiveLPVault.sol#L773)
	Possible stale balance used after the call in a condition:
	- [IERC20(input).balanceOf(executorAddress) != executorInput || IERC20(output).balanceOf(executorAddress) != executorOutput](src/core/AdaptiveLPVault.sol#L788-L789)
		- stale variable `executorInput`

src/core/AdaptiveLPVault.sol#L764-L796


 - [ ] ID-10
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](src/core/AdaptiveLPVault.sol#L407-L409)
		- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	Balance read before the call:
	- [(plan,assessment,current) = _previewFromSnapshot(oracle)](src/core/AdaptiveLPVault.sol#L376-L377)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `finalNav`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-11
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [_exitActivePosition(current.adapter)](src/core/AdaptiveLPVault.sol#L389)
		- [IPositionAdapter(adapter).withdrawAll()](src/core/AdaptiveLPVault.sol#L732)
	Balance read before the call:
	- [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](src/core/AdaptiveLPVault.sol#L388)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `minimumNavAfter`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-12
Reentrancy in [AdaptiveLPVault._depositToAdapter(address,PositionPlan,uint256,uint256)](src/core/AdaptiveLPVault.sol#L743-L762):
	External call allowing reentrancy:
	- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	Balance read before the call:
	- [before1 = IERC20(token1).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L747)
	Possible stale balance used after the call in a condition:
	- [used0 > amount0Max || used1 > amount1Max || after0 > before0 || after1 > before1 || before0 - after0 != used0 || before1 - after1 != used1](src/core/AdaptiveLPVault.sol#L757-L758)
		- stale variable `before1`

src/core/AdaptiveLPVault.sol#L743-L762


 - [ ] ID-13
Reentrancy in [AdaptiveLPVault._depositToAdapter(address,PositionPlan,uint256,uint256)](src/core/AdaptiveLPVault.sol#L743-L762):
	External call allowing reentrancy:
	- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	Balance read before the call:
	- [before0 = IERC20(token0).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L746)
	Possible stale balance used after the call in a condition:
	- [used0 > amount0Max || used1 > amount1Max || after0 > before0 || after1 > before1 || before0 - after0 != used0 || before1 - after1 != used1](src/core/AdaptiveLPVault.sol#L757-L758)
		- stale variable `before0`

src/core/AdaptiveLPVault.sol#L743-L762


 - [ ] ID-14
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](src/core/AdaptiveLPVault.sol#L404)
		- [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](src/core/AdaptiveLPVault.sol#L777-L779)
	Balance read before the call:
	- [(plan,assessment,current) = _previewFromSnapshot(oracle)](src/core/AdaptiveLPVault.sol#L376-L377)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `finalNav`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-15
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](src/core/AdaptiveLPVault.sol#L404)
		- [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](src/core/AdaptiveLPVault.sol#L777-L779)
	Balance read before the call:
	- [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](src/core/AdaptiveLPVault.sol#L388)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `minimumNavAfter`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-16
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](src/core/AdaptiveLPVault.sol#L407-L409)
		- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	Balance read before the call:
	- [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](src/core/AdaptiveLPVault.sol#L388)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `minimumNavAfter`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-17
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](src/core/AdaptiveLPVault.sol#L407-L409)
		- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	Balance read before the call:
	- [balance0 = IERC20(token0).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L390)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `finalNav`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-18
Reentrancy in [ControlledSwapExecutor.executeSwap(SwapPlan)](src/swap/ControlledSwapExecutor.sol#L108-L161):
	External call allowing reentrancy:
	- [_ROUTER.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({tokenIn:tokenIn,tokenOut:tokenOut,fee:_FEE_TIER,recipient:_VAULT,deadline:uint256(plan.deadline),amountIn:plan.amountIn,amountOutMinimum:plan.minAmountOut,sqrtPriceLimitX96:0}))](src/swap/ControlledSwapExecutor.sol#L128-L139)
	Balance read before the call:
	- [executorInputBefore = inputToken.balanceOf(address(this))](src/swap/ControlledSwapExecutor.sol#L119)
	Possible stale balance used after the call in a condition:
	- [executorInputAfter != expectedExecutorInputAfter](src/swap/ControlledSwapExecutor.sol#L144)
		- stale variable `expectedExecutorInputAfter`

src/swap/ControlledSwapExecutor.sol#L108-L161


 - [ ] ID-19
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [_exitActivePosition(current.adapter)](src/core/AdaptiveLPVault.sol#L389)
		- [IPositionAdapter(adapter).withdrawAll()](src/core/AdaptiveLPVault.sol#L732)
	Balance read before the call:
	- [(plan,assessment,current) = _previewFromSnapshot(oracle)](src/core/AdaptiveLPVault.sol#L376-L377)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `finalNav`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-20
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](src/core/AdaptiveLPVault.sol#L404)
		- [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](src/core/AdaptiveLPVault.sol#L777-L779)
	Balance read before the call:
	- [balance1 = IERC20(token1).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L391)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `finalNav`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-21
Reentrancy in [ControlledSwapExecutor.executeSwap(SwapPlan)](src/swap/ControlledSwapExecutor.sol#L108-L161):
	External call allowing reentrancy:
	- [_ROUTER.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({tokenIn:tokenIn,tokenOut:tokenOut,fee:_FEE_TIER,recipient:_VAULT,deadline:uint256(plan.deadline),amountIn:plan.amountIn,amountOutMinimum:plan.minAmountOut,sqrtPriceLimitX96:0}))](src/swap/ControlledSwapExecutor.sol#L128-L139)
	Balance read before the call:
	- [vaultOutputBefore = outputToken.balanceOf(_VAULT)](src/swap/ControlledSwapExecutor.sol#L124)
	Possible stale balance used after the call in a condition:
	- [amountOut < plan.minAmountOut](src/swap/ControlledSwapExecutor.sol#L158)
		- stale variable `amountOut`
	- [vaultOutputAfter < vaultOutputBefore](src/swap/ControlledSwapExecutor.sol#L154)
		- stale variable `vaultOutputBefore`

src/swap/ControlledSwapExecutor.sol#L108-L161


 - [ ] ID-22
Reentrancy in [UniswapV2Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV2Adapter.sol#L164-L184):
	External call allowing reentrancy:
	- [liquidity = _PAIR.mint(address(this))](src/adapters/UniswapV2Adapter.sol#L178)
	Balance read before the call:
	- [lpBefore = _PAIR.balanceOf(address(this))](src/adapters/UniswapV2Adapter.sol#L175)
	Possible stale balance used after the call in a condition:
	- [lpAfter < lpBefore || lpAfter - lpBefore != liquidity](src/adapters/UniswapV2Adapter.sol#L181)
		- stale variable `lpBefore`

src/adapters/UniswapV2Adapter.sol#L164-L184


 - [ ] ID-23
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](src/core/AdaptiveLPVault.sol#L407-L409)
		- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	Balance read before the call:
	- [balance1 = IERC20(token1).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L391)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `finalNav`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-24
Reentrancy in [ControlledSwapExecutor.executeSwap(SwapPlan)](src/swap/ControlledSwapExecutor.sol#L108-L161):
	External call allowing reentrancy:
	- [_ROUTER.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({tokenIn:tokenIn,tokenOut:tokenOut,fee:_FEE_TIER,recipient:_VAULT,deadline:uint256(plan.deadline),amountIn:plan.amountIn,amountOutMinimum:plan.minAmountOut,sqrtPriceLimitX96:0}))](src/swap/ControlledSwapExecutor.sol#L128-L139)
	Balance read before the call:
	- [executorOutputBefore = outputToken.balanceOf(address(this))](src/swap/ControlledSwapExecutor.sol#L125)
	Possible stale balance used after the call in a condition:
	- [executorOutputAfter != executorOutputBefore](src/swap/ControlledSwapExecutor.sol#L149)
		- stale variable `executorOutputBefore`

src/swap/ControlledSwapExecutor.sol#L108-L161


 - [ ] ID-25
Reentrancy in [AdaptiveLPVault._executeControlledSwap(SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L764-L796):
	External call allowing reentrancy:
	- [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](src/core/AdaptiveLPVault.sol#L777-L779)
	Balance read before the call:
	- [executorOutput = IERC20(output).balanceOf(executorAddress)](src/core/AdaptiveLPVault.sol#L774)
	Possible stale balance used after the call in a condition:
	- [IERC20(input).balanceOf(executorAddress) != executorInput || IERC20(output).balanceOf(executorAddress) != executorOutput](src/core/AdaptiveLPVault.sol#L788-L789)
		- stale variable `executorOutput`

src/core/AdaptiveLPVault.sol#L764-L796


 - [ ] ID-26
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External call allowing reentrancy:
	- [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](src/core/AdaptiveLPVault.sol#L388)
		- [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](src/core/AdaptiveLPVault.sol#L638)
	Balance read before the call:
	- [(plan,assessment,current) = _previewFromSnapshot(oracle)](src/core/AdaptiveLPVault.sol#L376-L377)
	Possible stale balance used after the call in a condition:
	- [finalNav < minimumNavAfter](src/core/AdaptiveLPVault.sol#L418)
		- stale variable `finalNav`

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-27
Reentrancy in [AdaptiveLPVault.redeem(uint256,uint256,uint256,address,address)](src/core/AdaptiveLPVault.sol#L272-L310):
	External call allowing reentrancy:
	- [(positionOut0,positionOut1) = IPositionAdapter(adapter).withdraw(shares,supply)](src/core/AdaptiveLPVault.sol#L296)
	Balance read before the call:
	- [idle1Before = IERC20(token1).balanceOf(address(this))](src/core/AdaptiveLPVault.sol#L291)
	Possible stale balance used after the call in a condition:
	- [amount0Out < minAmount0Out || amount1Out < minAmount1Out](src/core/AdaptiveLPVault.sol#L300)
		- stale variable `amount1Out`

src/core/AdaptiveLPVault.sol#L272-L310


## divide-before-multiply
Impact: Medium
Confidence: Medium
 - [ ] ID-28
[VaultStrategyMath._targetRange(int24,int24,uint24)](src/libraries/VaultStrategyMath.sol#L214-L235) performs a multiplication on the result of a division:
	- [quotient = tick / s](src/libraries/VaultStrategyMath.sol#L222)
	- [lowerCenter = quotient * s](src/libraries/VaultStrategyMath.sol#L225)

src/libraries/VaultStrategyMath.sol#L214-L235


 - [ ] ID-29
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128](src/libraries/PriceMath.sol#L57)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-30
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128](src/libraries/PriceMath.sol#L66)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-31
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128](src/libraries/PriceMath.sol#L54)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-32
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128](src/libraries/PriceMath.sol#L64)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-33
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128](src/libraries/PriceMath.sol#L59)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-34
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128](src/libraries/PriceMath.sol#L67)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-35
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128](src/libraries/PriceMath.sol#L60)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-36
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128](src/libraries/PriceMath.sol#L69)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-37
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128](src/libraries/PriceMath.sol#L65)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-38
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128](src/libraries/PriceMath.sol#L68)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-39
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128](src/libraries/PriceMath.sol#L56)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-40
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128](src/libraries/PriceMath.sol#L72)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-41
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128](src/libraries/PriceMath.sol#L61)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-42
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128](src/libraries/PriceMath.sol#L71)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-43
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128](src/libraries/PriceMath.sol#L55)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-44
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128](src/libraries/PriceMath.sol#L63)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-45
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128](src/libraries/PriceMath.sol#L70)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-46
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128](src/libraries/PriceMath.sol#L62)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-47
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) performs a multiplication on the result of a division:
	- [ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128](src/libraries/PriceMath.sol#L58)
	- [ratio = type()(uint256).max / ratio](src/libraries/PriceMath.sol#L74)

src/libraries/PriceMath.sol#L46-L81


## incorrect-equality
Impact: Medium
Confidence: High
 - [ ] ID-48
[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L233-L315) uses a dangerous strict equality:
	- [desired0 == 0 && desired1 == 0](src/adapters/UniswapV3Adapter.sol#L241)

src/adapters/UniswapV3Adapter.sol#L233-L315


 - [ ] ID-49
[AdaptiveLPVault._validateHealthyDeployment(AssetSnapshot,int24)](src/core/AdaptiveLPVault.sol#L868-L881) uses a dangerous strict equality:
	- [finalNav == 0](src/core/AdaptiveLPVault.sol#L875)

src/core/AdaptiveLPVault.sol#L868-L881


 - [ ] ID-50
[AdaptiveLPVault.deposit(uint256,uint256,uint256,address)](src/core/AdaptiveLPVault.sol#L223-L269) uses a dangerous strict equality:
	- [position.principal0 == 0 || position.principal1 == 0](src/core/AdaptiveLPVault.sol#L239)

src/core/AdaptiveLPVault.sol#L223-L269


 - [ ] ID-51
[AdaptiveLPVault.deposit(uint256,uint256,uint256,address)](src/core/AdaptiveLPVault.sol#L223-L269) uses a dangerous strict equality:
	- [sharesMinted == 0](src/core/AdaptiveLPVault.sol#L253)

src/core/AdaptiveLPVault.sol#L223-L269


 - [ ] ID-52
[UniswapV2Adapter.withdrawAll()](src/adapters/UniswapV2Adapter.sol#L205-L211) uses a dangerous strict equality:
	- [lpBalance == 0](src/adapters/UniswapV2Adapter.sol#L207)

src/adapters/UniswapV2Adapter.sol#L205-L211


 - [ ] ID-53
[UniswapV3Adapter.withdraw(uint256,uint256)](src/adapters/UniswapV3Adapter.sol#L318-L338) uses a dangerous strict equality:
	- [liquidityToRemove == 0](src/adapters/UniswapV3Adapter.sol#L333)

src/adapters/UniswapV3Adapter.sol#L318-L338


 - [ ] ID-54
[AdaptiveLPVault._assessmentInputs(PositionPlan,uint256,uint256,int24)](src/core/AdaptiveLPVault.sol#L685-L702) uses a dangerous strict equality:
	- [plan.targetVenue == VenueType.IDLE](src/core/AdaptiveLPVault.sol#L690)

src/core/AdaptiveLPVault.sol#L685-L702


 - [ ] ID-55
[UniswapV3Adapter._snapshot()](src/adapters/UniswapV3Adapter.sol#L353-L386) uses a dangerous strict equality:
	- [tokenId == 0](src/adapters/UniswapV3Adapter.sol#L358)

src/adapters/UniswapV3Adapter.sol#L353-L386


 - [ ] ID-56
[AdaptiveLPVault._validateActivePosition(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L908-L922) uses a dangerous strict equality:
	- [position.liquidity == 0 && position.amount0 == 0 && position.amount1 == 0](src/core/AdaptiveLPVault.sol#L913)

src/core/AdaptiveLPVault.sol#L908-L922


 - [ ] ID-57
[AdaptiveLPVault.deposit(uint256,uint256,uint256,address)](src/core/AdaptiveLPVault.sol#L223-L269) uses a dangerous strict equality:
	- [amount0Used == 0 || amount1Used == 0](src/core/AdaptiveLPVault.sol#L249)

src/core/AdaptiveLPVault.sol#L223-L269


 - [ ] ID-58
[AdaptiveLPVault._exitActivePosition(address)](src/core/AdaptiveLPVault.sol#L730-L740) uses a dangerous strict equality:
	- [activeVenue == VenueType.IDLE](src/core/AdaptiveLPVault.sol#L731)

src/core/AdaptiveLPVault.sol#L730-L740


 - [ ] ID-59
[AdaptiveLPVault.deposit(uint256,uint256,uint256,address)](src/core/AdaptiveLPVault.sol#L223-L269) uses a dangerous strict equality:
	- [_isV3Venue(activeVenue) && ((position.principal0 == 0) != (position.principal1 == 0))](src/core/AdaptiveLPVault.sol#L236)

src/core/AdaptiveLPVault.sol#L223-L269


 - [ ] ID-60
[UniswapV2Adapter.snapshot()](src/adapters/UniswapV2Adapter.sol#L128-L145) uses a dangerous strict equality:
	- [lpBalance == 0](src/adapters/UniswapV2Adapter.sol#L135)

src/adapters/UniswapV2Adapter.sol#L128-L145


 - [ ] ID-61
[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L885-L905) uses a dangerous strict equality:
	- [venues[i] == expectedVenue](src/core/AdaptiveLPVault.sol#L896)

src/core/AdaptiveLPVault.sol#L885-L905


 - [ ] ID-62
[AdaptiveLPVault._proportionalAmounts(uint256,uint256,uint256,uint256)](src/core/AdaptiveLPVault.sol#L980-L991) uses a dangerous strict equality:
	- [high0 < high1 || (high0 == high1 && low0 <= low1)](src/core/AdaptiveLPVault.sol#L987)

src/core/AdaptiveLPVault.sol#L980-L991


 - [ ] ID-63
[AdaptiveLPVault._validateHealthyDeployment(AssetSnapshot,int24)](src/core/AdaptiveLPVault.sol#L868-L881) uses a dangerous strict equality:
	- [finalNav == 0 || finalDeployBps < minDeployBps](src/core/AdaptiveLPVault.sol#L876)

src/core/AdaptiveLPVault.sol#L868-L881


 - [ ] ID-64
[UniswapV3Adapter._validateManagedPosition(uint256,int24,int24)](src/adapters/UniswapV3Adapter.sol#L463-L469) uses a dangerous strict equality:
	- [tokenId == 0 || _POSITION_MANAGER.ownerOf(tokenId) != address(this)](src/adapters/UniswapV3Adapter.sol#L464)

src/adapters/UniswapV3Adapter.sol#L463-L469


 - [ ] ID-65
[AdaptiveLPVault._idleBps(AssetSnapshot,int24,uint256)](src/core/AdaptiveLPVault.sol#L976-L978) uses a dangerous strict equality:
	- [totalNav == 0](src/core/AdaptiveLPVault.sol#L977)

src/core/AdaptiveLPVault.sol#L976-L978


 - [ ] ID-66
[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L885-L905) uses a dangerous strict equality:
	- [expectedVenue == VenueType.UNISWAP_V2](src/core/AdaptiveLPVault.sol#L890)

src/core/AdaptiveLPVault.sol#L885-L905


 - [ ] ID-67
[AdaptiveLPVault._validateActivePosition(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L908-L922) uses a dangerous strict equality:
	- [position.positionId == 0](src/core/AdaptiveLPVault.sol#L917)

src/core/AdaptiveLPVault.sol#L908-L922


 - [ ] ID-68
[AdaptiveLPVault._validateActivePositionAfterPartialExit()](src/core/AdaptiveLPVault.sol#L935-L938) uses a dangerous strict equality:
	- [position.liquidity == 0](src/core/AdaptiveLPVault.sol#L937)

src/core/AdaptiveLPVault.sol#L935-L938


 - [ ] ID-69
[AdaptiveLPVault._isV3Venue(VenueType)](src/core/AdaptiveLPVault.sol#L1146-L1148) uses a dangerous strict equality:
	- [venue == VenueType.UNISWAP_V3_LOW_FEE || venue == VenueType.UNISWAP_V3_HIGH_FEE](src/core/AdaptiveLPVault.sol#L1147)

src/core/AdaptiveLPVault.sol#L1146-L1148


 - [ ] ID-70
[AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431) uses a dangerous strict equality:
	- [plan.targetVenue == VenueType.IDLE](src/core/AdaptiveLPVault.sol#L386)

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-71
[AdaptiveLPVault._activePositionSnapshot()](src/core/AdaptiveLPVault.sol#L626-L630) uses a dangerous strict equality:
	- [activeVenue == VenueType.IDLE](src/core/AdaptiveLPVault.sol#L627)

src/core/AdaptiveLPVault.sol#L626-L630


 - [ ] ID-72
[UniswapV3Adapter._validateManagedPosition(uint256,int24,int24)](src/adapters/UniswapV3Adapter.sol#L463-L469) uses a dangerous strict equality:
	- [current.tickLower != expectedLower || current.tickUpper != expectedUpper || current.liquidity == 0](src/adapters/UniswapV3Adapter.sol#L466)

src/adapters/UniswapV3Adapter.sol#L463-L469


 - [ ] ID-73
[UniswapV2Adapter.withdraw(uint256,uint256)](src/adapters/UniswapV2Adapter.sol#L187-L202) uses a dangerous strict equality:
	- [liquidityToBurn == 0](src/adapters/UniswapV2Adapter.sol#L199)

src/adapters/UniswapV2Adapter.sol#L187-L202


## reentrancy-no-eth
Impact: Medium
Confidence: Medium
 - [ ] ID-74
Reentrancy in [UniswapV3Adapter.withdrawAll()](src/adapters/UniswapV3Adapter.sol#L341-L350):
	External calls:
	- [(amount0,amount1) = _decreaseAndCollect(tokenId,current.liquidity)](src/adapters/UniswapV3Adapter.sol#L346)
		- [_POSITION_MANAGER.decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams({tokenId:tokenId,liquidity:liquidityToRemove,amount0Min:0,amount1Min:0,deadline:block.timestamp}))](src/adapters/UniswapV3Adapter.sol#L423-L427)
		- [_POSITION_MANAGER.collect(INonfungiblePositionManager.CollectParams({tokenId:tokenId,recipient:_VAULT,amount0Max:type()(uint128).max,amount1Max:type()(uint128).max}))](src/adapters/UniswapV3Adapter.sol#L433-L437)
	- [_POSITION_MANAGER.burn(tokenId)](src/adapters/UniswapV3Adapter.sol#L348)
	State variables written after the call(s):
	- [_positionId = 0](src/adapters/UniswapV3Adapter.sol#L349)
	[UniswapV3Adapter._positionId](src/adapters/UniswapV3Adapter.sol#L37) can be used in cross function reentrancies:
	- [UniswapV3Adapter._snapshot()](src/adapters/UniswapV3Adapter.sol#L353-L386)
	- [UniswapV3Adapter.positionId()](src/adapters/UniswapV3Adapter.sol#L194-L196)

src/adapters/UniswapV3Adapter.sol#L341-L350


 - [ ] ID-75
Reentrancy in [UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L233-L315):
	External calls:
	- [_POSITION_MANAGER.burn(tokenId)](src/adapters/UniswapV3Adapter.sol#L252)
	State variables written after the call(s):
	- [_positionId = 0](src/adapters/UniswapV3Adapter.sol#L253)
	[UniswapV3Adapter._positionId](src/adapters/UniswapV3Adapter.sol#L37) can be used in cross function reentrancies:
	- [UniswapV3Adapter._snapshot()](src/adapters/UniswapV3Adapter.sol#L353-L386)
	- [UniswapV3Adapter.positionId()](src/adapters/UniswapV3Adapter.sol#L194-L196)

src/adapters/UniswapV3Adapter.sol#L233-L315


 - [ ] ID-76
Reentrancy in [AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)](src/core/AdaptiveLPVault.sol#L361-L431):
	External calls:
	- [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](src/core/AdaptiveLPVault.sol#L388)
		- [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](src/core/AdaptiveLPVault.sol#L638)
	- [_exitActivePosition(current.adapter)](src/core/AdaptiveLPVault.sol#L389)
		- [IPositionAdapter(adapter).withdrawAll()](src/core/AdaptiveLPVault.sol#L732)
	- [actualAmountOut = _executeControlledSwap(expectedDirection,amountIn,minAmountOut,deadline)](src/core/AdaptiveLPVault.sol#L404)
		- [actualAmountOut = swapExecutor.executeSwap(SwapPlan({direction:direction,amountIn:amountIn,minAmountOut:minAmountOut,deadline:deadline}))](src/core/AdaptiveLPVault.sol#L777-L779)
	- [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](src/core/AdaptiveLPVault.sol#L407-L409)
		- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	State variables written after the call(s):
	- [_commitPlan(plan)](src/core/AdaptiveLPVault.sol#L429)
		- [_lastExecutedPlan = plan](src/core/AdaptiveLPVault.sol#L832)
	[AdaptiveLPVault._lastExecutedPlan](src/core/AdaptiveLPVault.sol#L91) can be used in cross function reentrancies:
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.lastExecutedPlan()](src/core/AdaptiveLPVault.sol#L482-L484)
	- [activeVenue = plan.targetVenue](src/core/AdaptiveLPVault.sol#L410)
	[AdaptiveLPVault.activeVenue](src/core/AdaptiveLPVault.sol#L87) can be used in cross function reentrancies:
	- [AdaptiveLPVault._activePositionSnapshot()](src/core/AdaptiveLPVault.sol#L626-L630)
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.activeVenue](src/core/AdaptiveLPVault.sol#L87)
	- [_commitPlan(plan)](src/core/AdaptiveLPVault.sol#L429)
		- [lastPositionChangeAt = _timestamp32()](src/core/AdaptiveLPVault.sol#L833)
	[AdaptiveLPVault.lastPositionChangeAt](src/core/AdaptiveLPVault.sol#L88) can be used in cross function reentrancies:
	- [AdaptiveLPVault.lastPositionChangeAt](src/core/AdaptiveLPVault.sol#L88)
	- [_commitPlan(plan)](src/core/AdaptiveLPVault.sol#L429)
		- [planVersion = plan.version](src/core/AdaptiveLPVault.sol#L831)
	[AdaptiveLPVault.planVersion](src/core/AdaptiveLPVault.sol#L89) can be used in cross function reentrancies:
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.planVersion](src/core/AdaptiveLPVault.sol#L89)

src/core/AdaptiveLPVault.sol#L361-L431


 - [ ] ID-77
Reentrancy in [AdaptiveLPVault.emergencyExitToIdle()](src/core/AdaptiveLPVault.sol#L434-L457):
	External calls:
	- [position = _synchronizeFees(adapter)](src/core/AdaptiveLPVault.sol#L441)
		- [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](src/core/AdaptiveLPVault.sol#L638)
	- [_exitActivePosition(adapter)](src/core/AdaptiveLPVault.sol#L443)
		- [IPositionAdapter(adapter).withdrawAll()](src/core/AdaptiveLPVault.sol#L732)
	State variables written after the call(s):
	- [activeVenue = VenueType.IDLE](src/core/AdaptiveLPVault.sol#L444)
	[AdaptiveLPVault.activeVenue](src/core/AdaptiveLPVault.sol#L87) can be used in cross function reentrancies:
	- [AdaptiveLPVault._activePositionSnapshot()](src/core/AdaptiveLPVault.sol#L626-L630)
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.activeVenue](src/core/AdaptiveLPVault.sol#L87)

src/core/AdaptiveLPVault.sol#L434-L457


 - [ ] ID-78
Reentrancy in [UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L233-L315):
	External calls:
	- [_POSITION_MANAGER.burn(tokenId)](src/adapters/UniswapV3Adapter.sol#L252)
	- [(tokenId,liquidityCreated,used0,used1) = _POSITION_MANAGER.mint(INonfungiblePositionManager.MintParams({token0:_TOKEN0,token1:_TOKEN1,fee:_FEE_TIER,tickLower:plan.tickLower,tickUpper:plan.tickUpper,amount0Desired:desired0,amount1Desired:desired1,amount0Min:0,amount1Min:0,recipient:address(this),deadline:block.timestamp}))](src/adapters/UniswapV3Adapter.sol#L272-L286)
	State variables written after the call(s):
	- [_positionId = tokenId](src/adapters/UniswapV3Adapter.sol#L288)
	[UniswapV3Adapter._positionId](src/adapters/UniswapV3Adapter.sol#L37) can be used in cross function reentrancies:
	- [UniswapV3Adapter._snapshot()](src/adapters/UniswapV3Adapter.sol#L353-L386)
	- [UniswapV3Adapter.positionId()](src/adapters/UniswapV3Adapter.sol#L194-L196)

src/adapters/UniswapV3Adapter.sol#L233-L315


 - [ ] ID-79
Reentrancy in [AdaptiveLPVault.bootstrap(uint256,uint256,address)](src/core/AdaptiveLPVault.sol#L167-L220):
	External calls:
	- [_depositToAdapter(adapter,plan,amount0,amount1)](src/core/AdaptiveLPVault.sol#L197)
		- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	State variables written after the call(s):
	- [_lastExecutedPlan = plan](src/core/AdaptiveLPVault.sol#L209)
	[AdaptiveLPVault._lastExecutedPlan](src/core/AdaptiveLPVault.sol#L91) can be used in cross function reentrancies:
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.lastExecutedPlan()](src/core/AdaptiveLPVault.sol#L482-L484)
	- [activeVenue = plan.targetVenue](src/core/AdaptiveLPVault.sol#L199)
	[AdaptiveLPVault.activeVenue](src/core/AdaptiveLPVault.sol#L87) can be used in cross function reentrancies:
	- [AdaptiveLPVault._activePositionSnapshot()](src/core/AdaptiveLPVault.sol#L626-L630)
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.activeVenue](src/core/AdaptiveLPVault.sol#L87)
	- [initialized = true](src/core/AdaptiveLPVault.sol#L211)
	[AdaptiveLPVault.initialized](src/core/AdaptiveLPVault.sol#L86) can be used in cross function reentrancies:
	- [AdaptiveLPVault._requireInitialized()](src/core/AdaptiveLPVault.sol#L589-L591)
	- [AdaptiveLPVault.initialized](src/core/AdaptiveLPVault.sol#L86)
	- [planVersion = plan.version](src/core/AdaptiveLPVault.sol#L208)
	[AdaptiveLPVault.planVersion](src/core/AdaptiveLPVault.sol#L89) can be used in cross function reentrancies:
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.planVersion](src/core/AdaptiveLPVault.sol#L89)

src/core/AdaptiveLPVault.sol#L167-L220


 - [ ] ID-80
Reentrancy in [AdaptiveLPVault.rebalance(bytes32,uint32)](src/core/AdaptiveLPVault.sol#L313-L358):
	External calls:
	- [beforeMigration = _preMigrationSnapshot(oracle.twapTick,current)](src/core/AdaptiveLPVault.sol#L328)
		- [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](src/core/AdaptiveLPVault.sol#L638)
	- [_exitActivePosition(current.adapter)](src/core/AdaptiveLPVault.sol#L329)
		- [IPositionAdapter(adapter).withdrawAll()](src/core/AdaptiveLPVault.sol#L732)
	- [_depositToAdapter(adapter,plan,IERC20(token0).balanceOf(address(this)),IERC20(token1).balanceOf(address(this)))](src/core/AdaptiveLPVault.sol#L333-L335)
		- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	State variables written after the call(s):
	- [_commitPlan(plan)](src/core/AdaptiveLPVault.sol#L356)
		- [_lastExecutedPlan = plan](src/core/AdaptiveLPVault.sol#L832)
	[AdaptiveLPVault._lastExecutedPlan](src/core/AdaptiveLPVault.sol#L91) can be used in cross function reentrancies:
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.lastExecutedPlan()](src/core/AdaptiveLPVault.sol#L482-L484)
	- [activeVenue = plan.targetVenue](src/core/AdaptiveLPVault.sol#L337)
	[AdaptiveLPVault.activeVenue](src/core/AdaptiveLPVault.sol#L87) can be used in cross function reentrancies:
	- [AdaptiveLPVault._activePositionSnapshot()](src/core/AdaptiveLPVault.sol#L626-L630)
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.activeVenue](src/core/AdaptiveLPVault.sol#L87)
	- [_commitPlan(plan)](src/core/AdaptiveLPVault.sol#L356)
		- [lastPositionChangeAt = _timestamp32()](src/core/AdaptiveLPVault.sol#L833)
	[AdaptiveLPVault.lastPositionChangeAt](src/core/AdaptiveLPVault.sol#L88) can be used in cross function reentrancies:
	- [AdaptiveLPVault.lastPositionChangeAt](src/core/AdaptiveLPVault.sol#L88)
	- [_commitPlan(plan)](src/core/AdaptiveLPVault.sol#L356)
		- [planVersion = plan.version](src/core/AdaptiveLPVault.sol#L831)
	[AdaptiveLPVault.planVersion](src/core/AdaptiveLPVault.sol#L89) can be used in cross function reentrancies:
	- [AdaptiveLPVault._planInputs(OracleSnapshot,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L661-L683)
	- [AdaptiveLPVault.planVersion](src/core/AdaptiveLPVault.sol#L89)

src/core/AdaptiveLPVault.sol#L313-L358


## uninitialized-local
Impact: Medium
Confidence: Medium
 - [ ] ID-81
[UniswapV3Adapter.constructor(PositionAdapterConfig).poolToken1](src/adapters/UniswapV3Adapter.sol#L83) is a local variable never initialized

src/adapters/UniswapV3Adapter.sol#L83


 - [ ] ID-82
[CanonicalV3Oracle.snapshot().tickCumulatives](src/oracle/CanonicalV3Oracle.sol#L166) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L166


 - [ ] ID-83
[AdaptiveLPVault._readAndValidateOracleBinding(address,address).poolToken0](src/core/AdaptiveLPVault.sol#L1076) is a local variable never initialized

src/core/AdaptiveLPVault.sol#L1076


 - [ ] ID-84
[UniswapV2Adapter.constructor(PositionAdapterConfig).pairFactory](src/adapters/UniswapV2Adapter.sol#L50) is a local variable never initialized

src/adapters/UniswapV2Adapter.sol#L50


 - [ ] ID-85
[UniswapV2Adapter.constructor(PositionAdapterConfig).registeredPair](src/adapters/UniswapV2Adapter.sol#L77) is a local variable never initialized

src/adapters/UniswapV2Adapter.sol#L77


 - [ ] ID-86
[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address).poolTickSpacing](src/control/AdapterRegistry.sol#L265) is a local variable never initialized

src/control/AdapterRegistry.sol#L265


 - [ ] ID-87
[UniswapV3Adapter.constructor(PositionAdapterConfig).managerFactory](src/adapters/UniswapV3Adapter.sol#L85) is a local variable never initialized

src/adapters/UniswapV3Adapter.sol#L85


 - [ ] ID-88
[UniswapV2Adapter.constructor(PositionAdapterConfig).pairToken0](src/adapters/UniswapV2Adapter.sol#L48) is a local variable never initialized

src/adapters/UniswapV2Adapter.sol#L48


 - [ ] ID-89
[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address).poolFeeTier](src/control/AdapterRegistry.sol#L264) is a local variable never initialized

src/control/AdapterRegistry.sol#L264


 - [ ] ID-90
[UniswapV2Adapter.constructor(PositionAdapterConfig).pairToken1](src/adapters/UniswapV2Adapter.sol#L49) is a local variable never initialized

src/adapters/UniswapV2Adapter.sol#L49


 - [ ] ID-91
[UniswapV3Adapter.constructor(PositionAdapterConfig).poolFee](src/adapters/UniswapV3Adapter.sol#L86) is a local variable never initialized

src/adapters/UniswapV3Adapter.sol#L86


 - [ ] ID-92
[AdapterRegistry._validateAdapterBinding(VenueType,address).poolToken1](src/control/AdapterRegistry.sol#L179) is a local variable never initialized

src/control/AdapterRegistry.sol#L179


 - [ ] ID-93
[AdapterRegistry._validateAdapterBinding(VenueType,address).poolToken0](src/control/AdapterRegistry.sol#L178) is a local variable never initialized

src/control/AdapterRegistry.sol#L178


 - [ ] ID-94
[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterVenue](src/control/AdapterRegistry.sol#L137) is a local variable never initialized

src/control/AdapterRegistry.sol#L137


 - [ ] ID-95
[UniswapV3Adapter.constructor(PositionAdapterConfig).poolTickSpacing](src/adapters/UniswapV3Adapter.sol#L87) is a local variable never initialized

src/adapters/UniswapV3Adapter.sol#L87


 - [ ] ID-96
[VaultStrategyMath.getPlan(VaultStrategyMath.PlanInputs).tickLower](src/libraries/VaultStrategyMath.sol#L91) is a local variable never initialized

src/libraries/VaultStrategyMath.sol#L91


 - [ ] ID-97
[CanonicalV3Oracle.constructor(OracleConfig).registeredPool](src/oracle/CanonicalV3Oracle.sol#L82) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L82


 - [ ] ID-98
[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address).poolFactory](src/control/AdapterRegistry.sol#L266) is a local variable never initialized

src/control/AdapterRegistry.sol#L266


 - [ ] ID-99
[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterToken0](src/control/AdapterRegistry.sol#L139) is a local variable never initialized

src/control/AdapterRegistry.sol#L139


 - [ ] ID-100
[ControlledSwapExecutor.constructor(SwapExecutorConfig).poolToken1](src/swap/ControlledSwapExecutor.sol#L48) is a local variable never initialized

src/swap/ControlledSwapExecutor.sol#L48


 - [ ] ID-101
[ControlledSwapExecutor.constructor(SwapExecutorConfig).registeredPool](src/swap/ControlledSwapExecutor.sol#L82) is a local variable never initialized

src/swap/ControlledSwapExecutor.sol#L82


 - [ ] ID-102
[UniswapV3Adapter.constructor(PositionAdapterConfig).registeredPool](src/adapters/UniswapV3Adapter.sol#L133) is a local variable never initialized

src/adapters/UniswapV3Adapter.sol#L133


 - [ ] ID-103
[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterVault](src/control/AdapterRegistry.sol#L136) is a local variable never initialized

src/control/AdapterRegistry.sol#L136


 - [ ] ID-104
[CanonicalV3Oracle.constructor(OracleConfig).factory_](src/oracle/CanonicalV3Oracle.sol#L43) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L43


 - [ ] ID-105
[AdapterRegistry._validateV2Pool(address,address,address,uint24,int24,address).registeredPool](src/control/AdapterRegistry.sol#L247) is a local variable never initialized

src/control/AdapterRegistry.sol#L247


 - [ ] ID-106
[ControlledSwapExecutor.constructor(SwapExecutorConfig).routerFactory](src/swap/ControlledSwapExecutor.sol#L90) is a local variable never initialized

src/swap/ControlledSwapExecutor.sol#L90


 - [ ] ID-107
[CanonicalV3Oracle.constructor(OracleConfig).tickSpacing_](src/oracle/CanonicalV3Oracle.sol#L45) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L45


 - [ ] ID-108
[AdapterRegistry._validateV2Pool(address,address,address,uint24,int24,address).poolFactory](src/control/AdapterRegistry.sol#L239) is a local variable never initialized

src/control/AdapterRegistry.sol#L239


 - [ ] ID-109
[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterTickSpacing](src/control/AdapterRegistry.sol#L142) is a local variable never initialized

src/control/AdapterRegistry.sol#L142


 - [ ] ID-110
[ControlledSwapExecutor.constructor(SwapExecutorConfig).poolToken0](src/swap/ControlledSwapExecutor.sol#L47) is a local variable never initialized

src/swap/ControlledSwapExecutor.sol#L47


 - [ ] ID-111
[ControlledSwapExecutor.constructor(SwapExecutorConfig).poolFee](src/swap/ControlledSwapExecutor.sol#L50) is a local variable never initialized

src/swap/ControlledSwapExecutor.sol#L50


 - [ ] ID-112
[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterToken1](src/control/AdapterRegistry.sol#L140) is a local variable never initialized

src/control/AdapterRegistry.sol#L140


 - [ ] ID-113
[UniswapV3Adapter.constructor(PositionAdapterConfig).poolFactory](src/adapters/UniswapV3Adapter.sol#L84) is a local variable never initialized

src/adapters/UniswapV3Adapter.sol#L84


 - [ ] ID-114
[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address).registeredPool](src/control/AdapterRegistry.sol#L290) is a local variable never initialized

src/control/AdapterRegistry.sol#L290


 - [ ] ID-115
[ControlledSwapExecutor.constructor(SwapExecutorConfig).poolFactory](src/swap/ControlledSwapExecutor.sol#L49) is a local variable never initialized

src/swap/ControlledSwapExecutor.sol#L49


 - [ ] ID-116
[CanonicalV3Oracle.snapshot().spotTick](src/oracle/CanonicalV3Oracle.sol#L146) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L146


 - [ ] ID-117
[CanonicalV3Oracle.constructor(OracleConfig).token1_](src/oracle/CanonicalV3Oracle.sol#L42) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L42


 - [ ] ID-118
[CanonicalV3Oracle.constructor(OracleConfig).fee_](src/oracle/CanonicalV3Oracle.sol#L44) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L44


 - [ ] ID-119
[CanonicalV3Oracle.constructor(OracleConfig).token0_](src/oracle/CanonicalV3Oracle.sol#L41) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L41


 - [ ] ID-120
[CanonicalV3Oracle.snapshot().secondsPerLiquidityCumulativeX128s](src/oracle/CanonicalV3Oracle.sol#L167) is a local variable never initialized

src/oracle/CanonicalV3Oracle.sol#L167


 - [ ] ID-121
[AdaptiveLPVault._readAndValidateOracleBinding(address,address).poolToken1](src/core/AdaptiveLPVault.sol#L1077) is a local variable never initialized

src/core/AdaptiveLPVault.sol#L1077


 - [ ] ID-122
[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterFeeTier](src/control/AdapterRegistry.sol#L141) is a local variable never initialized

src/control/AdapterRegistry.sol#L141


 - [ ] ID-123
[UniswapV3Adapter.constructor(PositionAdapterConfig).poolToken0](src/adapters/UniswapV3Adapter.sol#L82) is a local variable never initialized

src/adapters/UniswapV3Adapter.sol#L82


 - [ ] ID-124
[VaultStrategyMath.getPlan(VaultStrategyMath.PlanInputs).tickUpper](src/libraries/VaultStrategyMath.sol#L92) is a local variable never initialized

src/libraries/VaultStrategyMath.sol#L92


 - [ ] ID-125
[AdaptiveLPVault._readAndValidateOracleBinding(address,address).poolFactory](src/core/AdaptiveLPVault.sol#L1075) is a local variable never initialized

src/core/AdaptiveLPVault.sol#L1075


 - [ ] ID-126
[AdapterRegistry._validateAdapterBinding(VenueType,address).adapterPool](src/control/AdapterRegistry.sol#L138) is a local variable never initialized

src/control/AdapterRegistry.sol#L138


 - [ ] ID-127
[AdaptiveLPVault._readAndValidateOracleBinding(address,address).poolFee](src/core/AdaptiveLPVault.sol#L1078) is a local variable never initialized

src/core/AdaptiveLPVault.sol#L1078


## unused-return
Impact: Medium
Confidence: Medium
 - [ ] ID-128
[UniswapV3Adapter._feeGrowthInside(int24,int24,int24)](src/adapters/UniswapV3Adapter.sol#L488-L522) ignores return value by [(None,None,lowerOutside0X128,lowerOutside1X128,None,None,None,None) = _POOL.ticks(tickLower)](src/adapters/UniswapV3Adapter.sol#L495)

src/adapters/UniswapV3Adapter.sol#L488-L522


 - [ ] ID-129
[UniswapV3Adapter._snapshot()](src/adapters/UniswapV3Adapter.sol#L353-L386) ignores return value by [(sqrtPriceX96,currentTick,None,None,None,None,None) = _POOL.slot0()](src/adapters/UniswapV3Adapter.sol#L366)

src/adapters/UniswapV3Adapter.sol#L353-L386


 - [ ] ID-130
[UniswapV3Adapter._readPosition(uint256)](src/adapters/UniswapV3Adapter.sol#L441-L460) ignores return value by [(None,None,current.token0,current.token1,current.fee,current.tickLower,current.tickUpper,current.liquidity,current.feeGrowthInside0LastX128,current.feeGrowthInside1LastX128,current.tokensOwed0,current.tokensOwed1) = _POSITION_MANAGER.positions(tokenId)](src/adapters/UniswapV3Adapter.sol#L442-L454)

src/adapters/UniswapV3Adapter.sol#L441-L460


 - [ ] ID-131
[UniswapV2Adapter.snapshot()](src/adapters/UniswapV2Adapter.sol#L128-L145) ignores return value by [(reserve0,reserve1,None) = _PAIR.getReserves()](src/adapters/UniswapV2Adapter.sol#L137)

src/adapters/UniswapV2Adapter.sol#L128-L145


 - [ ] ID-132
[UniswapV3Adapter._previewDeposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L389-L404) ignores return value by [(sqrtPriceX96,None,None,None,None,None,None) = _POOL.slot0()](src/adapters/UniswapV3Adapter.sol#L397)

src/adapters/UniswapV3Adapter.sol#L389-L404


 - [ ] ID-133
[ControlledSwapExecutor.executeSwap(SwapPlan)](src/swap/ControlledSwapExecutor.sol#L108-L161) ignores return value by [_ROUTER.exactInputSingle(IUniswapV3SwapRouter.ExactInputSingleParams({tokenIn:tokenIn,tokenOut:tokenOut,fee:_FEE_TIER,recipient:_VAULT,deadline:uint256(plan.deadline),amountIn:plan.amountIn,amountOutMinimum:plan.minAmountOut,sqrtPriceLimitX96:0}))](src/swap/ControlledSwapExecutor.sol#L128-L139)

src/swap/ControlledSwapExecutor.sol#L108-L161


 - [ ] ID-134
[AdaptiveLPVault._checkManagerOrKeeper()](src/core/AdaptiveLPVault.sol#L499-L501) ignores return value by [vaultControl.checkManagerOrKeeper(_msgSender())](src/core/AdaptiveLPVault.sol#L500)

src/core/AdaptiveLPVault.sol#L499-L501


 - [ ] ID-135
[AdaptiveLPVault._depositToAdapter(address,PositionPlan,uint256,uint256)](src/core/AdaptiveLPVault.sol#L743-L762) ignores return value by [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)

src/core/AdaptiveLPVault.sol#L743-L762


 - [ ] ID-136
[UniswapV3Adapter._feeGrowthInside(int24,int24,int24)](src/adapters/UniswapV3Adapter.sol#L488-L522) ignores return value by [(None,None,upperOutside0X128,upperOutside1X128,None,None,None,None) = _POOL.ticks(tickUpper)](src/adapters/UniswapV3Adapter.sol#L496)

src/adapters/UniswapV3Adapter.sol#L488-L522


 - [ ] ID-137
[CanonicalV3Oracle.snapshot()](src/oracle/CanonicalV3Oracle.sol#L139-L211) ignores return value by [(sqrtPriceX96,tick) = _POOL.slot0()](src/oracle/CanonicalV3Oracle.sol#L147-L154)

src/oracle/CanonicalV3Oracle.sol#L139-L211


 - [ ] ID-138
[UniswapV2Adapter._burnLiquidity(uint256)](src/adapters/UniswapV2Adapter.sol#L250-L259) ignores return value by [_PAIR.burn(_VAULT)](src/adapters/UniswapV2Adapter.sol#L255)

src/adapters/UniswapV2Adapter.sol#L250-L259


 - [ ] ID-139
[AdaptiveLPVault._pauseAll(address)](src/core/AdaptiveLPVault.sol#L519-L521) ignores return value by [vaultControl.pauseAll(caller)](src/core/AdaptiveLPVault.sol#L520)

src/core/AdaptiveLPVault.sol#L519-L521


 - [ ] ID-140
[UniswapV3Adapter._decreaseLiquidity(uint256,uint128)](src/adapters/UniswapV3Adapter.sol#L422-L428) ignores return value by [_POSITION_MANAGER.decreaseLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams({tokenId:tokenId,liquidity:liquidityToRemove,amount0Min:0,amount1Min:0,deadline:block.timestamp}))](src/adapters/UniswapV3Adapter.sol#L423-L427)

src/adapters/UniswapV3Adapter.sol#L422-L428


 - [ ] ID-141
[UniswapV2Adapter._previewDeposit(uint256,uint256)](src/adapters/UniswapV2Adapter.sol#L225-L244) ignores return value by [(reserve0,reserve1,None) = _PAIR.getReserves()](src/adapters/UniswapV2Adapter.sol#L232)

src/adapters/UniswapV2Adapter.sol#L225-L244


 - [ ] ID-142
[AdaptiveLPVault._checkManagerOrGuardian()](src/core/AdaptiveLPVault.sol#L495-L497) ignores return value by [vaultControl.checkManagerOrGuardian(_msgSender())](src/core/AdaptiveLPVault.sol#L496)

src/core/AdaptiveLPVault.sol#L495-L497


 - [ ] ID-143
[AdaptiveLPVault._exitActivePosition(address)](src/core/AdaptiveLPVault.sol#L730-L740) ignores return value by [IPositionAdapter(adapter).withdrawAll()](src/core/AdaptiveLPVault.sol#L732)

src/core/AdaptiveLPVault.sol#L730-L740


 - [ ] ID-144
[UniswapV3Adapter._collectAll(uint256)](src/adapters/UniswapV3Adapter.sol#L432-L438) ignores return value by [_POSITION_MANAGER.collect(INonfungiblePositionManager.CollectParams({tokenId:tokenId,recipient:_VAULT,amount0Max:type()(uint128).max,amount1Max:type()(uint128).max}))](src/adapters/UniswapV3Adapter.sol#L433-L437)

src/adapters/UniswapV3Adapter.sol#L432-L438


## events-maths
Impact: Low
Confidence: Medium
 - [ ] ID-145
[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L233-L315) should emit an event for: 
	- [_positionId = 0](src/adapters/UniswapV3Adapter.sol#L253) 
	- [_positionId = tokenId](src/adapters/UniswapV3Adapter.sol#L288) 

src/adapters/UniswapV3Adapter.sol#L233-L315


## calls-loop
Impact: Low
Confidence: Medium
 - [ ] ID-146
[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L885-L905) has external calls inside a loop: [position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](src/core/AdaptiveLPVault.sol#L899)
	Calls stack containing the loop:
		AdaptiveLPVault.rebalanceWithSwap(bytes32,SwapDirection,uint256,uint256,uint32)

src/core/AdaptiveLPVault.sol#L885-L905


 - [ ] ID-147
[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L885-L905) has external calls inside a loop: [position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](src/core/AdaptiveLPVault.sol#L899)
	Calls stack containing the loop:
		AdaptiveLPVault.emergencyExitToIdle()

src/core/AdaptiveLPVault.sol#L885-L905


 - [ ] ID-148
[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L885-L905) has external calls inside a loop: [position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](src/core/AdaptiveLPVault.sol#L899)
	Calls stack containing the loop:
		AdaptiveLPVault.rebalance(bytes32,uint32)

src/core/AdaptiveLPVault.sol#L885-L905


 - [ ] ID-149
[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L885-L905) has external calls inside a loop: [position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](src/core/AdaptiveLPVault.sol#L899)
	Calls stack containing the loop:
		AdaptiveLPVault.deposit(uint256,uint256,uint256,address)

src/core/AdaptiveLPVault.sol#L885-L905


 - [ ] ID-150
[AdaptiveLPVault._getAdapterOrRevert(VenueType)](src/core/AdaptiveLPVault.sol#L511-L513) has external calls inside a loop: [vaultControl.getAdapterOrRevert(venue)](src/core/AdaptiveLPVault.sol#L512)
	Calls stack containing the loop:
		AdaptiveLPVault.bootstrap(uint256,uint256,address)
		AdaptiveLPVault._validateManagedV3PositionsEmpty()

src/core/AdaptiveLPVault.sol#L511-L513


 - [ ] ID-151
[AdaptiveLPVault._validateManagedV3PositionsEmpty()](src/core/AdaptiveLPVault.sol#L924-L933) has external calls inside a loop: [position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](src/core/AdaptiveLPVault.sol#L928)
	Calls stack containing the loop:
		AdaptiveLPVault.bootstrap(uint256,uint256,address)

src/core/AdaptiveLPVault.sol#L924-L933


 - [ ] ID-152
[AdaptiveLPVault._validateSingleActivePositions(VenueType,PositionPlan,PositionSnapshot)](src/core/AdaptiveLPVault.sol#L885-L905) has external calls inside a loop: [position = IPositionAdapter(_getAdapterOrRevert(venues[i])).snapshot()](src/core/AdaptiveLPVault.sol#L899)
	Calls stack containing the loop:
		AdaptiveLPVault.bootstrap(uint256,uint256,address)

src/core/AdaptiveLPVault.sol#L885-L905


## reentrancy-benign
Impact: Low
Confidence: Medium
 - [ ] ID-153
Reentrancy in [AdaptiveLPVault.emergencyExitToIdle()](src/core/AdaptiveLPVault.sol#L434-L457):
	External calls:
	- [position = _synchronizeFees(adapter)](src/core/AdaptiveLPVault.sol#L441)
		- [(fee0,fee1) = IPositionAdapter(adapter).syncFees()](src/core/AdaptiveLPVault.sol#L638)
	- [_exitActivePosition(adapter)](src/core/AdaptiveLPVault.sol#L443)
		- [IPositionAdapter(adapter).withdrawAll()](src/core/AdaptiveLPVault.sol#L732)
	State variables written after the call(s):
	- [++ planVersion](src/core/AdaptiveLPVault.sol#L451)

src/core/AdaptiveLPVault.sol#L434-L457


 - [ ] ID-154
Reentrancy in [AdaptiveLPVault.bootstrap(uint256,uint256,address)](src/core/AdaptiveLPVault.sol#L167-L220):
	External calls:
	- [_depositToAdapter(adapter,plan,amount0,amount1)](src/core/AdaptiveLPVault.sol#L197)
		- [(used0,used1,None) = IPositionAdapter(adapter).deposit(amount0Max,amount1Max,plan)](src/core/AdaptiveLPVault.sol#L751)
	State variables written after the call(s):
	- [lastPositionChangeAt = _timestamp32()](src/core/AdaptiveLPVault.sol#L210)

src/core/AdaptiveLPVault.sol#L167-L220


## timestamp
Impact: Low
Confidence: Medium
 - [ ] ID-155
[ControlledSwapExecutor.executeSwap(SwapPlan)](src/swap/ControlledSwapExecutor.sol#L108-L161) uses timestamp for comparisons
	Dangerous comparisons:
	- [block.timestamp > plan.deadline](src/swap/ControlledSwapExecutor.sol#L112)

src/swap/ControlledSwapExecutor.sol#L108-L161


 - [ ] ID-156
[UniswapV3Adapter._readPosition(uint256)](src/adapters/UniswapV3Adapter.sol#L441-L460) uses timestamp for comparisons
	Dangerous comparisons:
	- [current.token0 != _TOKEN0 || current.token1 != _TOKEN1 || current.fee != _FEE_TIER](src/adapters/UniswapV3Adapter.sol#L456)

src/adapters/UniswapV3Adapter.sol#L441-L460


 - [ ] ID-157
[UniswapV3Adapter._validateRange(int24,int24)](src/adapters/UniswapV3Adapter.sol#L478-L485) uses timestamp for comparisons
	Dangerous comparisons:
	- [tickLower < MIN_TICK || tickUpper > MAX_TICK || tickLower >= tickUpper || tickLower % _TICK_SPACING != 0 || tickUpper % _TICK_SPACING != 0](src/adapters/UniswapV3Adapter.sol#L480-L481)

src/adapters/UniswapV3Adapter.sol#L478-L485


 - [ ] ID-158
[UniswapV3Adapter._decreaseAndCollect(uint256,uint128)](src/adapters/UniswapV3Adapter.sol#L407-L419) uses timestamp for comparisons
	Dangerous comparisons:
	- [liquidityToRemove != 0](src/adapters/UniswapV3Adapter.sol#L414)

src/adapters/UniswapV3Adapter.sol#L407-L419


 - [ ] ID-159
[UniswapV3Adapter.syncFees()](src/adapters/UniswapV3Adapter.sol#L204-L220) uses timestamp for comparisons
	Dangerous comparisons:
	- [afterSnapshot.claimableFee0 != 0 || afterSnapshot.claimableFee1 != 0](src/adapters/UniswapV3Adapter.sol#L217)

src/adapters/UniswapV3Adapter.sol#L204-L220


 - [ ] ID-160
[UniswapV3Adapter._snapshot()](src/adapters/UniswapV3Adapter.sol#L353-L386) uses timestamp for comparisons
	Dangerous comparisons:
	- [tokenId == 0](src/adapters/UniswapV3Adapter.sol#L358)

src/adapters/UniswapV3Adapter.sol#L353-L386


 - [ ] ID-161
[UniswapV3Adapter._feeGrowthInside(int24,int24,int24)](src/adapters/UniswapV3Adapter.sol#L488-L522) uses timestamp for comparisons
	Dangerous comparisons:
	- [currentTick >= tickLower](src/adapters/UniswapV3Adapter.sol#L503)
	- [currentTick < tickUpper](src/adapters/UniswapV3Adapter.sol#L511)

src/adapters/UniswapV3Adapter.sol#L488-L522


 - [ ] ID-162
[AdaptiveLPVault._timestamp32()](src/core/AdaptiveLPVault.sol#L1141-L1144) uses timestamp for comparisons
	Dangerous comparisons:
	- [block.timestamp > type()(uint32).max](src/core/AdaptiveLPVault.sol#L1142)

src/core/AdaptiveLPVault.sol#L1141-L1144


 - [ ] ID-163
[UniswapV3Adapter.withdraw(uint256,uint256)](src/adapters/UniswapV3Adapter.sol#L318-L338) uses timestamp for comparisons
	Dangerous comparisons:
	- [liquidityToRemove == 0](src/adapters/UniswapV3Adapter.sol#L333)

src/adapters/UniswapV3Adapter.sol#L318-L338


 - [ ] ID-164
[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L233-L315) uses timestamp for comparisons
	Dangerous comparisons:
	- [desired0 == 0 && desired1 == 0](src/adapters/UniswapV3Adapter.sol#L241)
	- [tokenId != 0](src/adapters/UniswapV3Adapter.sol#L244)
	- [current.liquidity != 0](src/adapters/UniswapV3Adapter.sol#L246)
	- [current.tickLower != plan.tickLower || current.tickUpper != plan.tickUpper](src/adapters/UniswapV3Adapter.sol#L247)
	- [current.tokensOwed0 != 0 || current.tokensOwed1 != 0](src/adapters/UniswapV3Adapter.sol#L251)
	- [desired0 != 0](src/adapters/UniswapV3Adapter.sol#L261)
	- [desired1 != 0](src/adapters/UniswapV3Adapter.sol#L265)
	- [tokenId == 0](src/adapters/UniswapV3Adapter.sol#L270)
	- [desired0 != 0](src/adapters/UniswapV3Adapter.sol#L305)
	- [desired1 != 0](src/adapters/UniswapV3Adapter.sol#L306)
	- [used0 > desired0](src/adapters/UniswapV3Adapter.sol#L308)
	- [used1 > desired1](src/adapters/UniswapV3Adapter.sol#L309)
	- [desired0 > used0](src/adapters/UniswapV3Adapter.sol#L310)
	- [desired1 > used1](src/adapters/UniswapV3Adapter.sol#L311)

src/adapters/UniswapV3Adapter.sol#L233-L315


 - [ ] ID-165
[UniswapV3Adapter._amountsForLiquidityAtPrices(uint160,uint160,uint160,uint128,bool)](src/adapters/UniswapV3Adapter.sol#L564-L579) uses timestamp for comparisons
	Dangerous comparisons:
	- [sqrtPriceX96 <= sqrtLowerX96](src/adapters/UniswapV3Adapter.sol#L571)
	- [sqrtPriceX96 < sqrtUpperX96](src/adapters/UniswapV3Adapter.sol#L573)

src/adapters/UniswapV3Adapter.sol#L564-L579


 - [ ] ID-166
[AdaptiveLPVault._requireDeadline(uint32)](src/core/AdaptiveLPVault.sol#L1132-L1134) uses timestamp for comparisons
	Dangerous comparisons:
	- [deadline == 0 || block.timestamp > deadline](src/core/AdaptiveLPVault.sol#L1133)

src/core/AdaptiveLPVault.sol#L1132-L1134


 - [ ] ID-167
[AdaptiveLPVault._requireCooldown()](src/core/AdaptiveLPVault.sol#L1136-L1139) uses timestamp for comparisons
	Dangerous comparisons:
	- [block.timestamp < availableAt](src/core/AdaptiveLPVault.sol#L1138)

src/core/AdaptiveLPVault.sol#L1136-L1139


 - [ ] ID-168
[UniswapV3Adapter._validateManagedPosition(uint256,int24,int24)](src/adapters/UniswapV3Adapter.sol#L463-L469) uses timestamp for comparisons
	Dangerous comparisons:
	- [tokenId == 0 || _POSITION_MANAGER.ownerOf(tokenId) != address(this)](src/adapters/UniswapV3Adapter.sol#L464)
	- [current.tickLower != expectedLower || current.tickUpper != expectedUpper || current.liquidity == 0](src/adapters/UniswapV3Adapter.sol#L466)

src/adapters/UniswapV3Adapter.sol#L463-L469


## cyclomatic-complexity
Impact: Informational
Confidence: High
 - [ ] ID-169
[UniswapV3Adapter.deposit(uint256,uint256,PositionPlan)](src/adapters/UniswapV3Adapter.sol#L233-L315) has a high cyclomatic complexity (14).

src/adapters/UniswapV3Adapter.sol#L233-L315


 - [ ] ID-170
[AdapterRegistry._validateAdapterBinding(VenueType,address)](src/control/AdapterRegistry.sol#L126-L216) has a high cyclomatic complexity (26).

src/control/AdapterRegistry.sol#L126-L216


 - [ ] ID-171
[AdapterRegistry._validateV3Pool(address,address,address,uint24,int24,address)](src/control/AdapterRegistry.sol#L256-L297) has a high cyclomatic complexity (13).

src/control/AdapterRegistry.sol#L256-L297


 - [ ] ID-172
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) has a high cyclomatic complexity (25).

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-173
[ControlledSwapExecutor.constructor(SwapExecutorConfig)](src/swap/ControlledSwapExecutor.sol#L40-L105) has a high cyclomatic complexity (22).

src/swap/ControlledSwapExecutor.sol#L40-L105


 - [ ] ID-174
[UniswapV2Adapter.constructor(PositionAdapterConfig)](src/adapters/UniswapV2Adapter.sol#L38-L90) has a high cyclomatic complexity (14).

src/adapters/UniswapV2Adapter.sol#L38-L90


 - [ ] ID-175
[AdaptiveLPVault._readAndValidateOracleBinding(address,address)](src/core/AdaptiveLPVault.sol#L1023-L1121) has a high cyclomatic complexity (30).

src/core/AdaptiveLPVault.sol#L1023-L1121


 - [ ] ID-176
[UniswapV3Adapter.constructor(PositionAdapterConfig)](src/adapters/UniswapV3Adapter.sol#L70-L151) has a high cyclomatic complexity (21).

src/adapters/UniswapV3Adapter.sol#L70-L151


 - [ ] ID-177
[CanonicalV3Oracle.constructor(OracleConfig)](src/oracle/CanonicalV3Oracle.sol#L29-L101) has a high cyclomatic complexity (18).

src/oracle/CanonicalV3Oracle.sol#L29-L101


## dead-code
Impact: Informational
Confidence: Medium
 - [ ] ID-178
[VaultRoles._checkManagerOrKeeper()](src/control/VaultRoles.sol#L45-L49) is never used and should be removed

src/control/VaultRoles.sol#L45-L49


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-179
Variable [UniswapV3Adapter._TOKEN1](src/adapters/UniswapV3Adapter.sol#L29) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L29


 - [ ] ID-180
Function [IVaultRoles.KEEPER_ROLE()](src/interfaces/IVaultRoles.sol#L20) is not in mixedCase

src/interfaces/IVaultRoles.sol#L20


 - [ ] ID-181
Variable [UniswapV2Adapter._PAIR](src/adapters/UniswapV2Adapter.sol#L24) is not in mixedCase

src/adapters/UniswapV2Adapter.sol#L24


 - [ ] ID-182
Variable [ControlledSwapExecutor._ROUTER_ADDRESS](src/swap/ControlledSwapExecutor.sol#L19) is not in mixedCase

src/swap/ControlledSwapExecutor.sol#L19


 - [ ] ID-183
Variable [UniswapV3Adapter._TOKEN0](src/adapters/UniswapV3Adapter.sol#L28) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L28


 - [ ] ID-184
Variable [CanonicalV3Oracle._TOKEN1](src/oracle/CanonicalV3Oracle.sol#L19) is not in mixedCase

src/oracle/CanonicalV3Oracle.sol#L19


 - [ ] ID-185
Function [IVaultRoles.GUARDIAN_ROLE()](src/interfaces/IVaultRoles.sol#L24) is not in mixedCase

src/interfaces/IVaultRoles.sol#L24


 - [ ] ID-186
Variable [ControlledSwapExecutor._VAULT](src/swap/ControlledSwapExecutor.sol#L18) is not in mixedCase

src/swap/ControlledSwapExecutor.sol#L18


 - [ ] ID-187
Variable [CanonicalV3Oracle._TOKEN0_DECIMALS](src/oracle/CanonicalV3Oracle.sol#L20) is not in mixedCase

src/oracle/CanonicalV3Oracle.sol#L20


 - [ ] ID-188
Variable [CanonicalV3Oracle._POOL](src/oracle/CanonicalV3Oracle.sol#L25) is not in mixedCase

src/oracle/CanonicalV3Oracle.sol#L25


 - [ ] ID-189
Variable [CanonicalV3Oracle._TOKEN0](src/oracle/CanonicalV3Oracle.sol#L18) is not in mixedCase

src/oracle/CanonicalV3Oracle.sol#L18


 - [ ] ID-190
Variable [UniswapV2Adapter._TOKEN0](src/adapters/UniswapV2Adapter.sol#L22) is not in mixedCase

src/adapters/UniswapV2Adapter.sol#L22


 - [ ] ID-191
Variable [CanonicalV3Oracle._SHORT_TWAP_WINDOW_SECONDS](src/oracle/CanonicalV3Oracle.sol#L23) is not in mixedCase

src/oracle/CanonicalV3Oracle.sol#L23


 - [ ] ID-192
Variable [UniswapV3Adapter._TICK_SPACING](src/adapters/UniswapV3Adapter.sol#L32) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L32


 - [ ] ID-193
Variable [ControlledSwapExecutor._SWAP_POOL](src/swap/ControlledSwapExecutor.sol#L22) is not in mixedCase

src/swap/ControlledSwapExecutor.sol#L22


 - [ ] ID-194
Variable [UniswapV2Adapter._TOKEN1](src/adapters/UniswapV2Adapter.sol#L23) is not in mixedCase

src/adapters/UniswapV2Adapter.sol#L23


 - [ ] ID-195
Variable [UniswapV3Adapter._VENUE](src/adapters/UniswapV3Adapter.sol#L26) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L26


 - [ ] ID-196
Variable [UniswapV2Adapter._VAULT](src/adapters/UniswapV2Adapter.sol#L20) is not in mixedCase

src/adapters/UniswapV2Adapter.sol#L20


 - [ ] ID-197
Variable [CanonicalV3Oracle._CANONICAL_POOL](src/oracle/CanonicalV3Oracle.sol#L17) is not in mixedCase

src/oracle/CanonicalV3Oracle.sol#L17


 - [ ] ID-198
Variable [CanonicalV3Oracle._TOKEN1_DECIMALS](src/oracle/CanonicalV3Oracle.sol#L21) is not in mixedCase

src/oracle/CanonicalV3Oracle.sol#L21


 - [ ] ID-199
Variable [UniswapV3Adapter._VAULT](src/adapters/UniswapV3Adapter.sol#L25) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L25


 - [ ] ID-200
Variable [UniswapV2Adapter._POOL](src/adapters/UniswapV2Adapter.sol#L21) is not in mixedCase

src/adapters/UniswapV2Adapter.sol#L21


 - [ ] ID-201
Variable [UniswapV3Adapter._FEE_TIER](src/adapters/UniswapV3Adapter.sol#L31) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L31


 - [ ] ID-202
Variable [UniswapV3Adapter._POOL_ADDRESS](src/adapters/UniswapV3Adapter.sol#L27) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L27


 - [ ] ID-203
Variable [UniswapV3Adapter._POSITION_MANAGER](src/adapters/UniswapV3Adapter.sol#L35) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L35


 - [ ] ID-204
Variable [ControlledSwapExecutor._TOKEN0](src/swap/ControlledSwapExecutor.sol#L20) is not in mixedCase

src/swap/ControlledSwapExecutor.sol#L20


 - [ ] ID-205
Variable [ControlledSwapExecutor._TOKEN1](src/swap/ControlledSwapExecutor.sol#L21) is not in mixedCase

src/swap/ControlledSwapExecutor.sol#L21


 - [ ] ID-206
Variable [UniswapV3Adapter._POSITION_MANAGER_ADDRESS](src/adapters/UniswapV3Adapter.sol#L30) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L30


 - [ ] ID-207
Variable [ControlledSwapExecutor._FEE_TIER](src/swap/ControlledSwapExecutor.sol#L23) is not in mixedCase

src/swap/ControlledSwapExecutor.sol#L23


 - [ ] ID-208
Function [IVaultRoles.DEFAULT_ADMIN_ROLE()](src/interfaces/IVaultRoles.sol#L12) is not in mixedCase

src/interfaces/IVaultRoles.sol#L12


 - [ ] ID-209
Variable [ControlledSwapExecutor._ROUTER](src/swap/ControlledSwapExecutor.sol#L25) is not in mixedCase

src/swap/ControlledSwapExecutor.sol#L25


 - [ ] ID-210
Variable [CanonicalV3Oracle._TWAP_WINDOW_SECONDS](src/oracle/CanonicalV3Oracle.sol#L22) is not in mixedCase

src/oracle/CanonicalV3Oracle.sol#L22


 - [ ] ID-211
Variable [UniswapV3Adapter._POOL](src/adapters/UniswapV3Adapter.sol#L34) is not in mixedCase

src/adapters/UniswapV3Adapter.sol#L34


 - [ ] ID-212
Function [IVaultRoles.MANAGER_ROLE()](src/interfaces/IVaultRoles.sol#L16) is not in mixedCase

src/interfaces/IVaultRoles.sol#L16


## too-many-digits
Impact: Informational
Confidence: Medium
 - [ ] ID-213
[PriceMath.sqrtRatioAtTick(int24)](src/libraries/PriceMath.sol#L46-L81) uses literals with too many digits:
	- [ratio = 0x100000000000000000000000000000000](src/libraries/PriceMath.sol#L52)

src/libraries/PriceMath.sol#L46-L81


 - [ ] ID-214
[UniswapV3Adapter.slitherConstructorConstantVariables()](src/adapters/UniswapV3Adapter.sol#L17-L619) uses literals with too many digits:
	- [Q128 = 0x100000000000000000000000000000000](src/adapters/UniswapV3Adapter.sol#L21)

src/adapters/UniswapV3Adapter.sol#L17-L619


 - [ ] ID-215
[UniswapV3Adapter.slitherConstructorConstantVariables()](src/adapters/UniswapV3Adapter.sol#L17-L619) uses literals with too many digits:
	- [Q96 = 0x1000000000000000000000000](src/adapters/UniswapV3Adapter.sol#L20)

src/adapters/UniswapV3Adapter.sol#L17-L619


