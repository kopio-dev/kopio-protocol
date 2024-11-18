// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {MaxLiqInfo} from "common/Types.sol";
import {LiquidationArgs} from "common/Args.sol";

interface IICDPLiquidationFacet {
    /**
     * @notice Attempts to liquidate an account by repaying debt, seizing collateral in return.
     * @param args LiquidationArgs the amount, assets and prices for the liquidation.
     */
    function liquidate(LiquidationArgs calldata args) external payable;

    /**
     * @dev Calculate total value that can be liquidated from the account (if any)
     * @param account account to liquidate
     * @param kopio kopio to repay
     * @param collateral collateral to seize
     * @return MaxLiqInfo the maximum values for the liquidation.
     */
    function getMaxLiqValue(address account, address kopio, address collateral) external view returns (MaxLiqInfo memory);
}
