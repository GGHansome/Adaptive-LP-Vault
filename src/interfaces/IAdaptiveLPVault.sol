// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AssetSnapshot, DeploymentAssessment, MarketRegime, PositionPlan, VenueType} from "../core/VaultTypes.sol";
import {SwapDirection} from "../swap/SwapTypes.sol";

/// @notice Defines the external business interface of the adaptive dual-asset liquidity vault.
/// @dev Role, pause, and adapter administration live at the immutable `vaultControl` address.
interface IAdaptiveLPVault {
    /// @notice Indicates that a value-sensitive operation could not obtain a healthy oracle snapshot.
    error OracleUnhealthy();

    /// @notice Indicates that pool tokens are zero, equal, or not ordered by address.
    error InvalidTokenOrder();

    /// @notice Indicates that a token's `decimals()` metadata could not be read.
    /// @param token Address of the token whose metadata read failed.
    error InvalidTokenMetadata(address token);

    /// @notice Indicates that a token reports more than 18 decimals.
    /// @param token Address of the token with an invalid decimal count.
    /// @param actual Decimal count returned by the token.
    error InvalidTokenDecimals(address token, uint8 actual);

    /// @notice Indicates that bootstrap net asset value is below `minimumInitialNav`.
    error MinimumNavNotMet();

    /// @notice Indicates that a required actual token amount rounded to zero.
    error ZeroAmount();

    /// @notice Indicates that an active V3 position has single-sided principal and cannot accept a deposit.
    error ActivePositionSingleSided();

    /// @notice Indicates that minted shares are below the caller's minimum.
    /// @param actual Actual number of shares calculated for the deposit.
    /// @param minimum Minimum number of shares required by the caller.
    error SharesSlippage(uint256 actual, uint256 minimum);

    /// @notice Indicates that one or both redemption outputs are below the caller's minimums.
    /// @param amount0 Actual token0 redemption output.
    /// @param amount1 Actual token1 redemption output.
    error AssetSlippage(uint256 amount0, uint256 amount1);

    /// @notice Indicates that adapter withdrawal returns differ from vault balance increases.
    error AdapterBalanceMismatch();

    /// @notice Indicates that the current plan hash differs from the caller's expected hash.
    error InvalidPlanHash();

    /// @notice Indicates that the supplied swap direction is `NONE` or differs from deployment assessment.
    error InvalidSwapDirection();

    /// @notice Indicates that a V3 range is misaligned, inverted, overflowing, or out of bounds.
    error InvalidTickRange();

    /// @notice Indicates that the caller-supplied deadline has passed.
    error DeadlineExpired();

    /// @notice Indicates that the generated plan would not change the current position state.
    error NoStateChangeRequired();

    /// @notice Indicates that the minimum interval between planned position changes has not elapsed.
    /// @param availableAt Earliest timestamp at which another planned rebalance may execute.
    error CooldownActive(uint256 availableAt);

    /// @notice Indicates that deployment requires an inventory-balancing swap.
    error SwapRequired();

    /// @notice Indicates that the current entry point, plan, or assessment does not permit a swap.
    error SwapNotAllowed();

    /// @notice Indicates that migration net asset value loss exceeds the configured limit.
    error MigrationLossExceeded();

    /// @notice Indicates that the post-operation idle-asset ratio exceeds the configured limit.
    error IdleLimitExceeded();

    /// @notice Indicates that simulated or actual deployment is below the required ratio.
    error DeploymentRatioTooLow();

    /// @notice Indicates that a target position would coexist with another effective position.
    error ActivePositionExists();

    /// @notice Indicates that an exited position still contains liquidity or assets.
    error PositionNotCleared();

    /// @notice Emitted after bootstrap commits initial assets, shares, position, and lifecycle state.
    /// @param manager Manager account that executed bootstrap.
    /// @param amount0 Actual token0 amount incorporated into the vault.
    /// @param amount1 Actual token1 amount incorporated into the vault.
    /// @param grossInitialShares Total shares minted for the initial net asset value.
    /// @param lockedShares Shares minted to the vault itself and permanently locked.
    /// @param initialVenue Asset location after bootstrap.
    event VaultBootstrapped(
        address indexed manager,
        uint256 amount0,
        uint256 amount1,
        uint256 grossInitialShares,
        uint256 lockedShares,
        VenueType initialVenue
    );

    /// @notice Emitted after a deposit transfers assets and mints shares.
    /// @param caller Account that supplied the deposited assets.
    /// @param receiver Account that received the newly minted shares.
    /// @param amount0 Actual token0 amount transferred into the vault.
    /// @param amount1 Actual token1 amount transferred into the vault.
    /// @param shares Number of shares minted to `receiver`.
    event Deposit(address indexed caller, address indexed receiver, uint256 amount0, uint256 amount1, uint256 shares);

    /// @notice Emitted after shares are burned and both underlying assets are paid out.
    /// @param caller Account that initiated the redemption.
    /// @param receiver Account that received token0 and token1.
    /// @param owner Account whose shares were burned.
    /// @param shares Number of shares burned from `owner`.
    /// @param amount0 Actual token0 amount paid to `receiver`.
    /// @param amount1 Actual token1 amount paid to `receiver`.
    event Redeem(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 shares,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted after a strategy plan is successfully executed and committed as history.
    /// @param planHash Stable hash of the committed plan.
    /// @param version Committed plan version.
    /// @param targetVenue Venue established by the committed plan.
    /// @param regime Market regime committed for subsequent hysteresis decisions.
    event PositionPlanCommitted(
        bytes32 indexed planHash, uint64 indexed version, VenueType targetVenue, MarketRegime regime
    );

    /// @notice Emitted after all rebalance steps and post-conditions succeed.
    /// @param caller Account that initiated the rebalance.
    /// @param planHash Hash of the plan executed by the rebalance.
    /// @param previousVenue Asset location before execution.
    /// @param targetVenue Asset location after execution.
    /// @param withSwap Whether the rebalance executed a controlled swap.
    /// @param total0 Total token0 assets after execution.
    /// @param total1 Total token1 assets after execution.
    /// @param nav1 Net asset value after execution, denominated in raw token1 units.
    /// @param idleBps Idle-asset ratio after execution, in basis points.
    event RebalanceExecuted(
        address indexed caller,
        bytes32 indexed planHash,
        VenueType previousVenue,
        VenueType targetVenue,
        bool withSwap,
        uint256 total0,
        uint256 total1,
        uint256 nav1,
        uint256 idleBps
    );

    /// @notice Emitted after bootstrap or rebalance establishes a new active V3 range.
    /// @param planHash Hash of the plan that established the range.
    /// @param oldTickLower Previous lower tick, or zero when no active V3 position existed.
    /// @param oldTickUpper Previous upper tick, or zero when no active V3 position existed.
    /// @param newTickLower Actual lower tick of the new position.
    /// @param newTickUpper Actual upper tick of the new position.
    event V3RangeChanged(
        bytes32 indexed planHash, int24 oldTickLower, int24 oldTickUpper, int24 newTickLower, int24 newTickUpper
    );

    /// @notice Emitted when the vault receives at least one nonzero fee amount from an active V3 position.
    /// @param adapter Address of the active adapter that synchronized fees.
    /// @param fee0 Actual token0 balance increase received by the vault.
    /// @param fee1 Actual token1 balance increase received by the vault.
    /// @param total0 Total token0 assets immediately after synchronization.
    /// @param total1 Total token1 assets immediately after synchronization.
    event FeesSynchronized(address indexed adapter, uint256 fee0, uint256 fee1, uint256 total0, uint256 total1);

    /// @notice Emitted after an active position is completely exited and the vault moves to IDLE.
    /// @param caller Guardian or manager that initiated the emergency exit.
    /// @param previousVenue Active venue before the exit.
    /// @param amount0 Token0 controlled directly by the vault after the exit.
    /// @param amount1 Token1 controlled directly by the vault after the exit.
    event EmergencyExit(address indexed caller, VenueType previousVenue, uint256 amount0, uint256 amount1);

    /// @notice Returns whether bootstrap has completed.
    function initialized() external view returns (bool);

    /// @notice Returns the dedicated control contract that owns roles, pause state, and adapter configuration.
    function vaultControl() external view returns (address);

    /// @notice Initializes the vault once with seed assets and a first strategy position.
    /// @dev The function validates all component bindings before transferring assets or committing state.
    /// @param amount0 Maximum token0 amount supplied by the manager.
    /// @param amount1 Maximum token1 amount supplied by the manager.
    /// @param receiver Account that receives the unlocked portion of initial shares.
    function bootstrap(uint256 amount0, uint256 amount1, address receiver) external;

    /// @notice Deposits the active position's required asset ratio and mints vault shares.
    /// @dev Shares are priced against net asset value and supply observed before the deposit.
    /// @param amount0Max Maximum token0 amount the caller permits the vault to transfer.
    /// @param amount1Max Maximum token1 amount the caller permits the vault to transfer.
    /// @param minSharesOut Minimum acceptable number of minted shares.
    /// @param receiver Account that receives the minted shares.
    /// @return amount0Used Actual token0 amount transferred from the caller.
    /// @return amount1Used Actual token1 amount transferred from the caller.
    /// @return sharesMinted Actual number of shares minted to `receiver`.
    function deposit(uint256 amount0Max, uint256 amount1Max, uint256 minSharesOut, address receiver)
        external
        returns (uint256 amount0Used, uint256 amount1Used, uint256 sharesMinted);

    /// @notice Burns shares from an owner and pays the pro rata token0 and token1 assets to a receiver.
    /// @dev A caller other than `owner` must have sufficient share allowance from `owner`.
    /// @param shares Number of shares to redeem.
    /// @param minAmount0Out Minimum acceptable token0 output.
    /// @param minAmount1Out Minimum acceptable token1 output.
    /// @param receiver Account that receives both underlying assets.
    /// @param owner Account whose shares are burned.
    /// @return amount0Out Actual token0 amount paid to `receiver`.
    /// @return amount1Out Actual token1 amount paid to `receiver`.
    function redeem(uint256 shares, uint256 minAmount0Out, uint256 minAmount1Out, address receiver, address owner)
        external
        returns (uint256 amount0Out, uint256 amount1Out);

    /// @notice Executes the current strategy plan when no inventory-balancing swap is required.
    /// @param expectedPlanHash Hash the caller expects from current on-chain inputs.
    /// @param deadline Last timestamp at which execution is permitted.
    function rebalance(bytes32 expectedPlanHash, uint32 deadline) external;

    /// @notice Executes the current strategy plan with one controlled inventory-balancing swap.
    /// @param expectedPlanHash Hash the caller expects from current on-chain inputs.
    /// @param expectedDirection Swap direction the caller expects from deployment assessment.
    /// @param amountIn Exact input amount proposed for the controlled swap.
    /// @param keeperMinAmountOut Keeper-provided minimum acceptable swap output.
    /// @param deadline Last timestamp at which execution is permitted.
    function rebalanceWithSwap(
        bytes32 expectedPlanHash,
        SwapDirection expectedDirection,
        uint256 amountIn,
        uint256 keeperMinAmountOut,
        uint32 deadline
    ) external;

    /// @notice Exits all active-position assets to the vault and sets the active venue to IDLE.
    /// @dev Emergency exit bypasses the rebalance cooldown and does not update plan history.
    ///      Unrecognized LP donations in the non-active V2 adapter remain untouched.
    function emergencyExitToIdle() external;

    /// @notice Returns the strategy plan and deployment assessment produced from current state.
    /// @return plan Current normalized position plan.
    /// @return assessment Swap requirements and direction derived from excess assets.
    function previewRebalance() external view returns (PositionPlan memory plan, DeploymentAssessment memory assessment);

    /// @notice Returns total token0 and token1 assets controlled by the vault and active adapter.
    /// @dev Non-active V2 LP donations enter accounting only when V2 becomes active; no shares are minted for them.
    /// @return total0 Total token0 assets without double-counting principal or fees.
    /// @return total1 Total token1 assets without double-counting principal or fees.
    function totalAssets() external view returns (uint256 total0, uint256 total1);

    /// @notice Returns a complete snapshot of idle assets, position assets, and share supply.
    /// @return assets Current vault asset snapshot.
    function assetSnapshot() external view returns (AssetSnapshot memory assets);

    /// @notice Returns the most recently executed healthy strategy plan.
    /// @return plan Last committed plan, whose regime is used as hysteresis history.
    function lastExecutedPlan() external view returns (PositionPlan memory plan);
}
