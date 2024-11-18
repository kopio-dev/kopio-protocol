// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {Percents} from "common/Constants.sol";
import {cs} from "common/State.sol";
import {err} from "common/Errors.sol";
import {Asset} from "common/Types.sol";
import {SCDPState, sdi} from "scdp/State.sol";

library SGlobal {
    using WadRay for uint256;
    using WadRay for uint128;
    using PercentageMath for uint256;

    /**
     * @notice Checks whether the shared debt pool can be liquidated.
     * @notice Reverts if collateral value .
     */
    function ensureLiquidatableSCDP(SCDPState storage self) internal view {
        uint256 collateralValue = self.totalCollateralValueSCDP(false);
        uint256 minCollateralValue = sdi().effectiveDebtValue().percentMul(self.liquidationThreshold);
        if (collateralValue >= minCollateralValue) {
            revert err.COLLATERAL_VALUE_GREATER_THAN_REQUIRED(collateralValue, minCollateralValue, self.liquidationThreshold);
        }
    }

    /**
     * @notice Checks whether the shared debt pool can be liquidated.
     * @notice Reverts if collateral value .
     */
    function checkCoverableSCDP(SCDPState storage self) internal view {
        uint256 collateralValue = self.totalCollateralValueSCDP(false);
        uint256 minCoverValue = sdi().effectiveDebtValue().percentMul(sdi().coverThreshold);
        if (collateralValue >= minCoverValue) {
            revert err.COLLATERAL_VALUE_GREATER_THAN_COVER_THRESHOLD(collateralValue, minCoverValue, sdi().coverThreshold);
        }
    }

    /**
     * @notice Checks whether the collateral value is less than minimum required.
     * @notice Reverts when collateralValue is below minimum required.
     * @param _ratio Ratio to check in 1e4 percentage precision (uint32).
     */
    function ensureCollateralRatio(SCDPState storage self, uint32 _ratio) internal view {
        uint256 collateralValue = self.totalCollateralValueSCDP(false);
        uint256 minCollateralValue = sdi().effectiveDebtValue().percentMul(_ratio);
        if (collateralValue < minCollateralValue) {
            revert err.COLLATERAL_TOO_LOW(collateralValue, minCollateralValue, _ratio);
        }
    }

    /**
     * @notice Returns the value of the kopio held in the pool at a ratio.
     * @param _ratio Percentage ratio to apply for the value in 1e4 percentage precision (uint32).
     * @param noFactors Whether to ignore dFactor
     * @return totalValue Total value in USD
     */
    function totalDebtValueAtRatioSCDP(
        SCDPState storage self,
        uint32 _ratio,
        bool noFactors
    ) internal view returns (uint256 totalValue) {
        address[] memory assets = self.kopios;
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = cs().assets[assets[i]];
            uint256 debtAmount = asset.toDynamic(self.assetData[assets[i]].debt);
            unchecked {
                if (debtAmount != 0) {
                    totalValue += asset.toDebtValue(debtAmount, noFactors);
                }
                i++;
            }
        }

        // Multiply if needed
        if (_ratio != Percents.HUNDRED) {
            totalValue = totalValue.percentMul(_ratio);
        }
    }

    /**
     * @notice Calculates the total collateral value of collateral assets in the pool.
     * @param noFactors Whether to ignore cFactor.
     * @return totalValue Total value in USD
     */
    function totalCollateralValueSCDP(SCDPState storage self, bool noFactors) internal view returns (uint256 totalValue) {
        address[] memory assets = self.collaterals;
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = cs().assets[assets[i]];
            uint256 depositAmount = self.totalDepositAmount(assets[i], asset);
            if (depositAmount != 0) {
                unchecked {
                    totalValue += asset.toCollateralValue(depositAmount, noFactors);
                }
            }

            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Calculates total collateral value while extracting single asset value.
     * @param _collateralAsset Collateral asset to extract value for
     * @param noFactors Whether to ignore cFactor.
     * @return totalValue Total value in USD
     * @return assetValue Asset value in USD
     */
    function totalCollateralValueSCDP(
        SCDPState storage self,
        address _collateralAsset,
        bool noFactors
    ) internal view returns (uint256 totalValue, uint256 assetValue) {
        address[] memory assets = self.collaterals;
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = cs().assets[assets[i]];
            uint256 depositAmount = self.totalDepositAmount(assets[i], asset);
            unchecked {
                if (depositAmount != 0) {
                    uint256 value = asset.toCollateralValue(depositAmount, noFactors);
                    totalValue += value;
                    if (assets[i] == _collateralAsset) {
                        assetValue = value;
                    }
                }
                i++;
            }
        }
    }

    /**
     * @notice Get pool collateral deposits of an asset.
     * @param _assetAddress The asset address
     * @param _asset The asset struct
     * @return Effective collateral deposit amount for this asset.
     */
    function totalDepositAmount(
        SCDPState storage self,
        address _assetAddress,
        Asset storage _asset
    ) internal view returns (uint128) {
        return uint128(_asset.toDynamic(self.assetData[_assetAddress].totalDeposits));
    }

    /**
     * @notice Get pool user collateral deposits of an asset.
     * @param _assetAddress The asset address
     * @param _asset The asset struct
     * @return Collateral deposits originating from users.
     */
    function userDepositAmount(
        SCDPState storage self,
        address _assetAddress,
        Asset storage _asset
    ) internal view returns (uint256) {
        return
            _asset.toDynamic(self.assetData[_assetAddress].totalDeposits) -
            _asset.toDynamic(self.assetData[_assetAddress].swapDeposits);
    }

    /**
     * @notice Get "swap" collateral deposits.
     * @param _assetAddress The asset address
     * @param _asset The asset struct.
     * @return Amount of debt.
     */
    function swapDepositAmount(
        SCDPState storage self,
        address _assetAddress,
        Asset storage _asset
    ) internal view returns (uint128) {
        return uint128(_asset.toDynamic(self.assetData[_assetAddress].swapDeposits));
    }
}
