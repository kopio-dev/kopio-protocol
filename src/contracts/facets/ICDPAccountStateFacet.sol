// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IICDPAccountStateFacet} from "interfaces/IICDPAccountStateFacet.sol";
import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";

import {err} from "common/Errors.sol";
import {cs} from "common/State.sol";
import {Enums} from "common/Constants.sol";
import {Asset} from "common/Types.sol";
import {fromWad} from "common/funcs/Math.sol";

import {ICDPAccount} from "icdp/Types.sol";
import {ms} from "icdp/State.sol";

/**
 * @author the kopio project
 * @title ICDPAccountStateFacet
 * @notice Views concerning account state
 */
contract ICDPAccountStateFacet is IICDPAccountStateFacet {
    using WadRay for uint256;
    using PercentageMath for uint256;

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountLiquidatable(address account) external view returns (bool) {
        return ms().isAccountLiquidatable(account);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountState(address account) external view returns (ICDPAccount memory) {
        uint256 debtValue = ms().accountTotalDebtValue(account);
        uint256 collateralValue = ms().accountTotalCollateralValue(account);
        return
            ICDPAccount({
                totalDebtValue: debtValue,
                totalCollateralValue: collateralValue,
                collateralRatio: debtValue > 0 ? collateralValue.percentDiv(debtValue) : 0
            });
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Kopios                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountMintIndex(address account, address asset) external view returns (uint256) {
        return ms().accountMintIndex(account, asset);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountMintedAssets(address account) external view returns (address[] memory) {
        return ms().mints[account];
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountTotalDebtValues(address account) external view returns (uint256 value, uint256 valueAdjusted) {
        return accountTotalDebtValues(account);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountTotalDebtValue(address account) external view returns (uint256) {
        return ms().accountTotalDebtValue(account);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountDebtAmount(address account, address asset) public view returns (uint256) {
        return ms().accountDebtAmount(account, asset, cs().assets[asset]);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountDebtValue(address account, address asset) external view returns (uint256) {
        return cs().assets[asset].toDebtValue(getAccountDebtAmount(account, asset), false);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountCollateralValue(address account, address asset) external view returns (uint256) {
        return cs().assets[asset].toCollateralValue(getAccountCollateralAmount(account, asset), false);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 Collateral                                 */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountCollateralAssets(address account) external view returns (address[] memory) {
        return ms().collateralsOf[account];
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountCollateralAmount(address account, address asset) public view returns (uint256) {
        return ms().accountCollateralAmount(account, asset, cs().assets[asset]);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountDepositIndex(address account, address collateral) external view returns (uint256 i) {
        return ms().accountDepositIndex(account, collateral);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountTotalCollateralValue(address account) public view returns (uint256) {
        return ms().accountTotalCollateralValue(account);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountTotalCollateralValues(address account) public view returns (uint256 value, uint256 valueAdjusted) {
        return accountTotalCollateralValues(account);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountCollateralValues(
        address account,
        address asset
    ) external view returns (uint256 value, uint256 adjustedValue, uint256 price) {
        Asset storage cfg = cs().assets[asset];
        return cfg.toValues(ms().accountCollateralAmount(account, asset, cfg), cfg.factor);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountMinCollateralAtRatio(address account, uint32 ratio) public view returns (uint256) {
        return ms().accountMinCollateralAtRatio(account, ratio);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountCollateralRatio(address account) public view returns (uint256 ratio) {
        uint256 collateralValue = ms().accountTotalCollateralValue(account);
        if (collateralValue == 0) {
            return 0;
        }
        uint256 debtValue = ms().accountTotalDebtValue(account);
        if (debtValue == 0) {
            return 0;
        }

        ratio = collateralValue.percentDiv(debtValue);
    }

    /// @inheritdoc IICDPAccountStateFacet
    function getAccountCollateralRatios(address[] calldata accounts) external view returns (uint256[] memory) {
        uint256[] memory ratios = new uint256[](accounts.length);
        for (uint256 i; i < accounts.length; i++) {
            ratios[i] = getAccountCollateralRatio(accounts[i]);
        }
        return ratios;
    }

    /// @inheritdoc IICDPAccountStateFacet
    function previewFee(
        address account,
        address repayKopio,
        uint256 amount,
        Enums.ICDPFee feeType
    ) external view returns (address[] memory, uint256[] memory) {
        if (uint8(feeType) > 1) {
            revert err.INVALID_FEE_TYPE(uint8(feeType), 1);
        }

        Asset storage cfg = cs().assets[repayKopio];

        // Calculate the value of the fee according to the value of the kopio
        uint256 feeValue = cfg.kopioUSD(amount).percentMul(feeType == Enums.ICDPFee.Open ? cfg.openFee : cfg.closeFee);

        address[] memory collaterals = ms().collateralsOf[account];

        ExpectedFeeRuntimeInfo memory info; // Using ExpectedFeeRuntimeInfo struct to avoid StackTooDeep error
        info.assets = new address[](collaterals.length);
        info.amounts = new uint256[](collaterals.length);

        // Return empty arrays if the fee value is 0.
        if (feeValue == 0) {
            return (info.assets, info.amounts);
        }

        for (uint256 i = collaterals.length - 1; i >= 0; i--) {
            address collateralAddr = collaterals[i];
            Asset storage collateralAsset = cs().assets[collateralAddr];

            uint256 depositAmount = ms().accountCollateralAmount(account, collateralAddr, collateralAsset);

            // Don't take the collateral asset's collateral factor into consideration.
            (uint256 depositValue, , uint256 price) = collateralAsset.toValues(depositAmount, 0);

            uint256 feeValuePaid;
            uint256 transferAmount;
            // If feeValue < depositValue, the entire fee can be charged for this collateral asset.
            if (feeValue < depositValue) {
                transferAmount = fromWad(feeValue.wadDiv(price), collateralAsset.decimals);
                feeValuePaid = feeValue;
            } else {
                transferAmount = depositAmount;
                feeValuePaid = depositValue;
            }

            if (transferAmount > 0) {
                info.assets[info.collateralTypeCount] = collateralAddr;
                info.amounts[info.collateralTypeCount] = transferAmount;
                info.collateralTypeCount = info.collateralTypeCount++;
            }

            feeValue = feeValue - feeValuePaid;
            // If the entire fee has been paid, no more action needed.
            if (feeValue == 0) {
                return (info.assets, info.amounts);
            }
        }
        return (info.assets, info.amounts);
    }
}

/**
 * @notice Gets the collateral value of an account.
 * @param account account to get value for.
 * @return value total unfactored collateral value
 * @return valueAdj total factored collateral value
 */
function accountTotalCollateralValues(address account) view returns (uint256 value, uint256 valueAdj) {
    address[] memory assets = ms().collateralsOf[account];
    for (uint256 i; i < assets.length; ) {
        Asset storage asset = cs().assets[assets[i]];
        uint256 collateralAmount = ms().accountCollateralAmount(account, assets[i], asset);
        unchecked {
            if (collateralAmount != 0) {
                (uint256 val, uint256 valAdj, ) = asset.toValues(collateralAmount, asset.factor);
                value += val;
                valueAdj += valAdj;
            }
            i++;
        }
    }
}

/**
 * @notice Gets the total debt value in USD for an account.
 * @param account account to get value for.
 * @return value total unfactored debt value
 * @return valueAdj total factored debt value
 */
function accountTotalDebtValues(address account) view returns (uint256 value, uint256 valueAdj) {
    address[] memory assets = ms().mints[account];
    for (uint256 i; i < assets.length; ) {
        Asset storage asset = cs().assets[assets[i]];
        uint256 debtAmount = ms().accountDebtAmount(account, assets[i], asset);
        unchecked {
            if (debtAmount != 0) {
                (uint256 val, uint256 valAdj, ) = asset.toValues(debtAmount, asset.dFactor);
                value += val;
                valueAdj += valAdj;
            }
            i++;
        }
    }
}
