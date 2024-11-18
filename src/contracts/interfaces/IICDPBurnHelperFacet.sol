// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IICDPBurnHelperFacet {
    /**
     * @notice Attempts to close all debt positions.
     * @param account account closing the positions
     * @param prices pyth price data
     */
    function closeAllDebtPositions(address account, bytes[] calldata prices) external payable;

    /**
     * @notice Burns all debt
     * @param account account closing the positions
     * @param kopio address of the asset.
     * @param prices pyth price data
     */
    function closeDebtPosition(address account, address kopio, bytes[] calldata prices) external payable;
}
