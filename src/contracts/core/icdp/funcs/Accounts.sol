// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {id, err} from "common/Errors.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";
import {ICDPState} from "icdp/State.sol";
import {Arrays} from "libs/Arrays.sol";

library MAccounts {
    using WadRay for uint256;
    using PercentageMath for uint256;
    using Arrays for address[];

    /**
     * @notice Checks if accounts collateral value is less than required.
     * @notice Reverts if account is not liquidatable.
     * @param acc Account to check.
     */
    function checkAccountLiquidatable(ICDPState storage self, address acc) internal view {
        uint256 collateralValue = self.accountTotalCollateralValue(acc);
        uint256 minCollateralValue = self.accountMinCollateralAtRatio(acc, self.liquidationThreshold);
        if (collateralValue >= minCollateralValue) {
            revert err.NOT_LIQUIDATABLE(acc, collateralValue, minCollateralValue, self.liquidationThreshold);
        }
    }

    /**
     * @notice Gets the liquidatable status of an account.
     * @param acc Account to check.
     * @return bool Indicating if the account is liquidatable.
     */
    function isAccountLiquidatable(ICDPState storage self, address acc) internal view returns (bool) {
        return self.accountTotalCollateralValue(acc) < self.accountMinCollateralAtRatio(acc, self.liquidationThreshold);
    }

    /**
     * @notice verifies that the account has enough collateral value
     * @param acc The address of the account to verify the collateral for.
     */
    function checkAccountCollateral(ICDPState storage self, address acc) internal view {
        uint256 collateralValue = self.accountTotalCollateralValue(acc);
        // Get the account's minimum collateral value.
        uint256 minCollateralValue = self.accountMinCollateralAtRatio(acc, self.minCollateralRatio);

        if (collateralValue < minCollateralValue) {
            revert err.ACCOUNT_COLLATERAL_TOO_LOW(acc, collateralValue, minCollateralValue, self.minCollateralRatio);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                Account Debt                                */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the total debt value in USD for an account.
     * @param acc Account to calculate the kopio value for.
     * @return value Total asset debt value of `acc`.
     */
    function accountTotalDebtValue(ICDPState storage self, address acc) internal view returns (uint256 value) {
        address[] memory assets = self.mints[acc];
        for (uint256 i; i < assets.length; ) {
            Asset storage cfg = cs().assets[assets[i]];
            uint256 debt = self.accountDebtAmount(acc, assets[i], cfg);
            unchecked {
                if (debt != 0) {
                    value += cfg.toDebtValue(debt, false);
                }
                i++;
            }
        }
        return value;
    }

    /**
     * @notice Gets `acc` debt for `_asset`
     * @dev Principal debt is rebase adjusted due to possible stock splits/reverse splits
     * @param acc account to get debt amount for.
     * @param asset kopio address
     * @param cfg configuration of the asset
     * @return debtAmount debt `acc` has for `_asset`
     */
    function accountDebtAmount(
        ICDPState storage self,
        address acc,
        address asset,
        Asset storage cfg
    ) internal view returns (uint256 debtAmount) {
        return cfg.toDynamic(self.debt[acc][asset]);
    }

    /**
     * @notice Gets an array of assets the account has minted.
     * @param acc Account to get the minted assets for.
     * @return address[] of assets the account has minted.
     */
    function accountDebtAssets(ICDPState storage self, address acc) internal view returns (address[] memory) {
        return self.mints[acc];
    }

    /**
     * @notice Gets accounts min collateral value required to cover debt at a given collateralization ratio.
     * @notice Account with min collateral value under MCR cannot borrow.
     * @notice Account with min collateral value under LT can be liquidated up to maxLiquidationRatio.
     * @param acc Account to calculate the minimum collateral value for.
     * @param ratio Collateralization ratio to apply for the minimum collateral value.
     * @return uint256 Minimum collateral value required for the account with `ratio`.
     */
    function accountMinCollateralAtRatio(ICDPState storage self, address acc, uint32 ratio) internal view returns (uint256) {
        return self.accountTotalDebtValue(acc).percentMul(ratio);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Account Collateral                             */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Gets the array of collateral assets the account has deposited.
     * @param acc Account to get the deposited collateral assets for.
     * @return address[] deposited collaterals for `acc`.
     */
    function accountCollateralAssets(ICDPState storage self, address acc) internal view returns (address[] memory) {
        return self.collateralsOf[acc];
    }

    /**
     * @notice Gets the deposit amount for an account
     * @notice Performs rebasing conversion if necessary
     * @param acc account
     * @param asset the collateral asset
     * @param cfg asset configuration
     * @return uint256 Collateral deposit amount of `_asset` for `acc`
     */
    function accountCollateralAmount(
        ICDPState storage self,
        address acc,
        address asset,
        Asset storage cfg
    ) internal view returns (uint256) {
        return cfg.toDynamic(self.deposits[acc][asset]);
    }

    /**
     * @notice Gets the collateral value of an account.
     * @param acc Account to get the value for
     * @return totalValue of a particular account.
     */
    function accountTotalCollateralValue(ICDPState storage self, address acc) internal view returns (uint256 totalValue) {
        address[] memory assets = self.collateralsOf[acc];
        for (uint256 i; i < assets.length; ) {
            Asset storage cfg = cs().assets[assets[i]];
            uint256 amount = self.accountCollateralAmount(acc, assets[i], cfg);
            unchecked {
                if (amount != 0) {
                    totalValue += cfg.toCollateralValue(amount, false);
                }
                i++;
            }
        }

        return totalValue;
    }

    /**
     * @notice Gets the total collateral deposits value of an account while extracting value for `collateral`.
     * @param acc Account to calculate the collateral value for.
     * @param collateral Collateral asset to extract value for.
     * @return totalValue Total collateral value of `acc`
     * @return assetValue Collateral value of `collateral` for `acc`
     */
    function accountTotalCollateralValue(
        ICDPState storage self,
        address acc,
        address collateral
    ) internal view returns (uint256 totalValue, uint256 assetValue) {
        address[] memory assets = self.collateralsOf[acc];
        for (uint256 i; i < assets.length; ) {
            Asset storage cfg = cs().assets[assets[i]];
            uint256 amount = self.accountCollateralAmount(acc, assets[i], cfg);

            unchecked {
                if (amount != 0) {
                    uint256 value = cfg.toCollateralValue(amount, false);
                    totalValue += value;
                    if (assets[i] == collateral) assetValue = value;
                }
                i++;
            }
        }
    }

    /**
     * @notice Gets the deposit index of the asset for the account.
     * @param acc account
     * @param collateral the asset deposited
     * @return uint256 index of the asset or revert.
     */
    function accountDepositIndex(ICDPState storage self, address acc, address collateral) internal view returns (uint256) {
        Arrays.FindResult memory item = self.collateralsOf[acc].find(collateral);
        if (!item.exists) {
            revert err.NOT_DEPOSITED(acc, id(collateral), self.collateralsOf[acc]);
        }
        return item.index;
    }

    /**
     * @notice Gets the mint index for an asset the account has minted.
     * @param acc account
     * @param asset the minted asset
     * @return uint256 index of the asset or revert.
     */
    function accountMintIndex(ICDPState storage self, address acc, address asset) internal view returns (uint256) {
        Arrays.FindResult memory item = self.mints[acc].find(asset);
        if (!item.exists) {
            revert err.NOT_MINTED(acc, id(asset), self.mints[acc]);
        }
        return item.index;
    }
}
