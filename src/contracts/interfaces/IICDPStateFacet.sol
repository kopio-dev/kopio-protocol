// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {ICDPParams} from "icdp/Types.sol";

interface IICDPStateFacet {
    /// @notice threshold before an account is considered liquidatable.
    function getLT() external view returns (uint32);

    /// @notice max liquidation multiplier -  cr after liquidation will be this.
    function getMLR() external view returns (uint32);

    /// @notice minimum value of debt.
    function getMinDebtValue() external view returns (uint256);

    /// @notice minimum ratio of collateral to debt.
    function getMCR() external view returns (uint32);

    /// @notice checks if asset exists
    function getKopioExists(address addr) external view returns (bool);

    /// @notice checks if collateral exists
    function getCollateralExists(address addr) external view returns (bool);

    /// @notice get active parameters in icdp.
    function getICDPParams() external view returns (ICDPParams memory);

    /// @notice minted icdp supply for a given asset.
    function getMintedSupply(address) external view returns (uint256);

    /**
     * @notice Gets the value from amount of collateral asset.
     * @param collateral address of collateral.
     * @param amount amount of the asset
     * @return value unfactored value of the collateral asset.
     * @return adjustedValue factored value of the collateral asset.
     * @return price price used to calculate the value.
     */
    function getCollateralValueWithPrice(
        address collateral,
        uint256 amount
    ) external view returns (uint256 value, uint256 adjustedValue, uint256 price);

    /**
     * @notice Gets the value from asset amount.
     * @param asset address of the asset.
     * @param amount amount of the asset.
     * @return value unfactored value of the asset.
     * @return adjustedValue factored value of the asset.
     * @return price price used to calculate the value.
     */
    function getDebtValueWithPrice(
        address asset,
        uint256 amount
    ) external view returns (uint256 value, uint256 adjustedValue, uint256 price);
}
