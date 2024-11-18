// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {SCDPInitializer, SwapRouteSetter, SCDPParameters} from "scdp/Types.sol";

interface ISCDPConfigFacet {
    function initializeSCDP(SCDPInitializer memory _init) external;

    /// @notice Gets the active parameters in SCDP.
    function getGlobalParameters() external view returns (SCDPParameters memory);

    /**
     * @notice Set the asset to cumulate swap fees into.
     * @param collateral Asset that is validated to be a deposit asset.
     */
    function setGlobalIncome(address collateral) external;

    /// @notice Set the MCR for SCDP.
    function setGlobalMCR(uint32 newMCR) external;

    /// @notice Set LT for SCDP. Updates MLR to LT + 1%.
    function setGlobalLT(uint32 newLT) external;

    /// @notice Set the max liquidation ratio for SCDP.
    /// @notice MLR is also updated automatically when setLiquidationThresholdSCDP is used.
    function setGlobalMLR(uint32 newMLR) external;

    /// @notice Set the liquidation incentive for a kopio in SCDP.
    /// @param kopio kopio asset to update.
    /// @param newIncentive new incentive multiplier, bound 1e4 <-> 1.25e4.
    function setGlobalLiqIncentive(address kopio, uint16 newIncentive) external;

    /**
     * @notice Update the asset deposit limit.
     * @param collateral collateral to update
     * @param newLimit the new deposit limit for the collateral
     */
    function setGlobalDepositLimit(address collateral, uint256 newLimit) external;

    /**
     * @notice Enable/disable explicit global deposits for an asset.
     * @param collateral asset to update.
     * @param enabled enable or disable deposits
     */
    function setGlobalDepositEnabled(address collateral, bool enabled) external;

    /**
     * @notice Enable/disable asset from total global collateral value.
     * * Reverts if asset has user deposits.
     * @param asset asset to update.
     * @param enabled whether to enable or disable deposits.
     */
    function setGlobalCollateralEnabled(address asset, bool enabled) external;

    /**
     * @notice Enable/disable an asset in all swaps.
     * Enabling also adds it to total collateral value calculations.
     * @param kopio asset to update.
     * @param enabled whether to enable or disable swaps.
     */
    function setSwapEnabled(address kopio, bool enabled) external;

    /**
     * @notice Sets the swap fees of a kopio.
     * @param kopio kopio to set the fees for.
     * @param feeIn new fee when swapping in.
     * @param feeOut new fee when swapping out.
     * @param protocolShare percentage of fees the protocol takes.
     */
    function setSwapFees(address kopio, uint16 feeIn, uint16 feeOut, uint16 protocolShare) external;

    /**
     * @notice Enable/disable swaps between assets.
     * @param routes routes to enable/disable.
     */
    function setSwapRoutes(SwapRouteSetter[] calldata routes) external;

    /**
     * @notice Enable/disable a swap direction between two assets.
     * @param route the route to enable/disable.
     */
    function setSwapRoute(SwapRouteSetter calldata route) external;
}
