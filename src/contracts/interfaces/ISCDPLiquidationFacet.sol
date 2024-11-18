// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {MaxLiqInfo} from "common/Types.sol";
import {SCDPLiquidationArgs} from "common/Args.sol";

interface ISCDPLiquidationFacet {
    /**
     * @notice Liquidate the global position.
     * @notice affects every depositor if self deposits from the protocol cannot cover it.
     * @param args selected assets and amounts.
     */
    function liquidateSCDP(SCDPLiquidationArgs memory args, bytes[] calldata prices) external payable;

    /**
     * @dev Calculates the total value that is allowed to be liquidated from SCDP (if it is liquidatable)
     * @param kopio Address of the asset to repay
     * @param collateral Address of collateral to seize
     * @return MaxLiqInfo Calculated information about the maximum liquidation.
     */
    function getMaxLiqValueSCDP(address kopio, address collateral) external view returns (MaxLiqInfo memory);

    function getLiquidatableSCDP() external view returns (bool);
}
