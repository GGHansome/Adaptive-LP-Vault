// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PositionSnapshot} from "../adapters/AdapterTypes.sol";
import {PositionPlan, VenueType} from "../core/VaultTypes.sol";

/// @notice Defines the common position-management surface for every supported venue adapter.
interface IPositionAdapter {
    /// @notice Indicates that deployment configuration does not describe the expected adapter kind.
    error InvalidAdapterConfiguration();

    /// @notice Indicates that a position plan targets a venue other than the adapter's bound venue.
    /// @param expected Venue represented by the adapter.
    /// @param actual Venue requested by the position plan.
    error InvalidPlanVenue(VenueType expected, VenueType actual);

    /// @notice Indicates that a withdrawal has an invalid pre-burn share supply or requests more shares than that supply.
    error InvalidShareSupply();

    /// @notice Indicates that the adapter or pool token pair differs from the expected pair.
    error InvalidAssetPair();

    /// @notice Indicates that a pool, pair, factory, or position-manager binding is invalid or inconsistent.
    error InvalidPoolBinding();

    /// @notice Indicates that pool tokens are zero, equal, or not ordered by address.
    error InvalidTokenOrder();

    /// @notice Indicates that the bound V3 pool exposes an invalid tick spacing.
    error InvalidTickSpacing();

    /// @notice Indicates that a requested V3 range is misaligned, inverted, or out of bounds.
    error InvalidTickRange();

    /// @notice Indicates that a new position was requested while another effective position exists.
    error ActivePositionExists();

    /// @notice Indicates that a supposedly exited position still contains liquidity or assets.
    error PositionNotCleared();

    /// @notice Indicates that fee collection left claimable position fees behind.
    error FeeCollectionIncomplete();

    /// @notice Indicates that a position manager returned an invalid position identifier, owner, or state.
    error InvalidManagedPosition();

    /// @notice Indicates that calculated V3 liquidity exceeds the position manager's uint128 limit.
    error LiquidityOverflow();

    /// @notice Indicates that a position manager reported consuming more than the approved desired amount.
    /// @param token Token whose reported consumption exceeded the desired amount.
    /// @param desired Maximum amount made available to the position manager.
    /// @param used Amount reported as consumed by the position manager.
    error UsedAmountExceedsDesired(address token, uint256 desired, uint256 used);

    /// @notice Indicates that an adapter's loose asset or LP-token balance differs from the expected value.
    /// @param token Token whose adapter balance did not return to the expected value.
    /// @param expected Expected adapter balance after the operation.
    /// @param actual Adapter balance observed after the operation.
    error AdapterBalanceMismatch(address token, uint256 expected, uint256 actual);

    /// @notice Indicates that an asset-mutating method was called by an account other than the vault.
    error NotVaultCaller();

    /// @notice Returns the immutable vault authorized to mutate adapter assets.
    /// @return vaultAddress Address of the bound vault.
    function vault() external view returns (address vaultAddress);

    /// @notice Returns the immutable venue represented by the adapter.
    /// @return venueType Venue represented by the adapter.
    function venue() external view returns (VenueType venueType);

    /// @notice Returns the immutable pool or pair bound to the adapter.
    /// @return poolAddress Address of the bound pool or pair.
    function pool() external view returns (address poolAddress);

    /// @notice Returns the lower-address token bound to the adapter.
    /// @return token Address of token0.
    function token0() external view returns (address token);

    /// @notice Returns the higher-address token bound to the adapter.
    /// @return token Address of token1.
    function token1() external view returns (address token);

    /// @notice Returns the bound V3 fee tier, or zero for V2.
    /// @return fee Fee tier expressed in hundredths of a basis point.
    function feeTier() external view returns (uint24 fee);

    /// @notice Returns the bound V3 tick spacing, or zero for V2.
    /// @return spacing Tick spacing of the bound pool.
    function tickSpacing() external view returns (int24 spacing);

    /// @notice Returns the complete current position snapshot.
    /// @dev Principal and claimable fees must not be counted twice in `amount0` or `amount1`.
    /// @return position Current adapter position state and assets.
    function snapshot() external view returns (PositionSnapshot memory position);

    /// @notice Collects claimable position fees and transfers them to the vault.
    /// @return fee0 Actual token0 balance increase received by the vault.
    /// @return fee1 Actual token1 balance increase received by the vault.
    function syncFees() external returns (uint256 fee0, uint256 fee1);

    /// @notice Previews the amounts that would be deployed by `deposit`.
    /// @dev This function must use the same AMM calculation path as the state-changing deposit.
    /// @param amount0Max Maximum token0 amount available for deployment.
    /// @param amount1Max Maximum token1 amount available for deployment.
    /// @param plan Normalized position plan controlling the target position.
    /// @return used0 Token0 amount expected to be deployed.
    /// @return used1 Token1 amount expected to be deployed.
    function previewDeposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        external
        view
        returns (uint256 used0, uint256 used1);

    /// @notice Deploys assets into the adapter's bound venue.
    /// @dev Only the bound vault may call this function. Implementations validate protocol-specific execution results;
    ///      the V2 adapter checks that its actual LP-token balance increase equals the pair's reported minted liquidity.
    /// @param amount0Max Maximum token0 amount available for deployment.
    /// @param amount1Max Maximum token1 amount available for deployment.
    /// @param plan Normalized position plan controlling the target position.
    /// @return used0 Actual token0 amount deployed.
    /// @return used1 Actual token1 amount deployed.
    /// @return liquidity Native liquidity units created or added.
    function deposit(uint256 amount0Max, uint256 amount1Max, PositionPlan calldata plan)
        external
        returns (uint256 used0, uint256 used1, uint256 liquidity);

    /// @notice Withdraws the floor-rounded pro rata native position units to the vault.
    /// @dev `totalShares` is the vault supply before burning the redeemed shares.
    /// @param shares Number of vault shares being redeemed.
    /// @param totalShares Vault share supply before the redemption burn.
    /// @return amount0 Actual token0 amount transferred to the vault.
    /// @return amount1 Actual token1 amount transferred to the vault.
    function withdraw(uint256 shares, uint256 totalShares) external returns (uint256 amount0, uint256 amount1);

    /// @notice Exits the complete position and transfers all resulting assets to the vault.
    /// @return amount0 Actual token0 amount transferred to the vault.
    /// @return amount1 Actual token1 amount transferred to the vault.
    function withdrawAll() external returns (uint256 amount0, uint256 amount1);
}
