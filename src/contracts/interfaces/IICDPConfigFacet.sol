// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ICDPInitializer} from "icdp/Types.sol";

interface IICDPConfigFacet {
    function initializeICDP(ICDPInitializer calldata args) external;

    /**
     * @dev Updates the contract's minimum debt value.
     * @param newValue The new minimum debt value as a wad.
     */
    function setMinDebtValue(uint256 newValue) external;

    /**
     * @notice Updates the liquidation incentive multiplier.
     * @param collateral The collateral asset to update.
     * @param newIncentive The new liquidation incentive multiplier for the asset.
     */
    function setLiqIncentive(address collateral, uint16 newIncentive) external;

    /**
     * @dev Updates the contract's collateralization ratio.
     * @param newMCR The new minimum collateralization ratio as wad.
     */
    function setMCR(uint32 newMCR) external;

    /**
     * @dev Updates the contract's liquidation threshold value
     * @param newLT The new liquidation threshold value
     */
    function setLT(uint32 newLT) external;

    /**
     * @notice Updates the max liquidation ratior value.
     * @notice This is the maximum collateral ratio that liquidations can liquidate to.
     * @param newMLR Percent value in wad precision.
     */
    function setMLR(uint32 newMLR) external;
}
