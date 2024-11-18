// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IERC20} from "kopio/token/IERC20.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";
import {Arrays} from "libs/Arrays.sol";
import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";

import {fromWad} from "common/funcs/Math.sol";
import {Enums} from "common/Constants.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";

import {ms} from "icdp/State.sol";
import {MEvent} from "icdp/Event.sol";

using WadRay for uint256;
using SafeTransfer for IERC20;
using PercentageMath for uint256;
using Arrays for address[];

/* -------------------------------------------------------------------------- */
/*                                    Fees                                    */
/* -------------------------------------------------------------------------- */

/**
 * @notice Charges the protocol open fee based off the value of the minted asset.
 * @dev Takes the fee from the account's collateral assets. Attempts collateral assets
 *   in reverse order of the account's deposited collateral assets array.
 * @param cfg Asset struct of the asset being minted.
 * @param account Account to charge the open fee from.
 * @param amount Amount of the asset being minted.
 * @param fee ICDPFee type
 */
function handleFee(Asset storage cfg, address account, uint256 amount, Enums.ICDPFee fee) {
    // Calculate the value of the fee according to the value of the kopios being minted.
    uint256 feeValue = cfg.kopioUSD(amount).percentMul(fee == Enums.ICDPFee.Open ? cfg.openFee : cfg.closeFee);

    // Do nothing if the fee value is 0.
    if (feeValue == 0) return;

    address[] memory collaterals = ms().collateralsOf[account];
    // Iterate backward through the account's deposited collateral assets to safely
    // traverse the array while still being able to remove elements if necessary.
    // This is because removing the last element of the array does not shift around
    // other elements in the array.
    for (uint256 i = collaterals.length - 1; i >= 0; i--) {
        address collateralAddr = collaterals[i];
        Asset storage collateral = cs().assets[collateralAddr];

        (uint256 transferAmount, uint256 feeValuePaid) = _calcFeeAndHandleCollateralRemoval(
            collateral,
            collateralAddr,
            account,
            feeValue,
            i
        );

        // Remove the transferAmount from the stored deposit for the account.
        ms().deposits[account][collateralAddr] -= collateral.toStatic(transferAmount);

        // Transfer the fee to the feeRecipient.
        IERC20(collateralAddr).safeTransfer(cs().feeRecipient, transferAmount);

        emit MEvent.FeePaid(account, collateralAddr, uint8(fee), transferAmount, feeValuePaid, feeValue);

        // If the entire fee has been paid, no more action needed.
        if ((feeValue = feeValue - feeValuePaid) == 0) return;
    }
}

/**
 * @notice Calculates the fee to be taken from a user's deposited collateral asset.
 * @param cfg Asset struct of the collateral asset.
 * @param collateral The collateral asset from which to take to the fee.
 * @param account The owner of the collateral.
 * @param value The original value of the fee.
 * @param depositIdx The collateral asset's index in the user's collateralsOf array.
 * @return transferAmount to be received as a uint256
 * @return feeValuePaid wad representing the fee value paid.
 */
function _calcFeeAndHandleCollateralRemoval(
    Asset storage cfg,
    address collateral,
    address account,
    uint256 value,
    uint256 depositIdx
) returns (uint256 transferAmount, uint256 feeValuePaid) {
    uint256 depositAmount = ms().accountCollateralAmount(account, collateral, cfg);

    // Don't take the collateral asset's collateral factor into consideration.
    (uint256 depositValue, , uint256 oraclePrice) = cfg.toValues(depositAmount, 0);

    if (value < depositValue) {
        // If feeValue < depositValue, the entire fee can be charged for this collateral asset.
        transferAmount = fromWad(value.wadDiv(oraclePrice), cfg.decimals);
        feeValuePaid = value;
    } else {
        // If the feeValue >= depositValue, the entire deposit should be taken as the fee.
        transferAmount = depositAmount;
        feeValuePaid = depositValue;
    }

    if (transferAmount == depositAmount) {
        // Because the entire deposit is taken, remove it from the depositCollateralAssets array.
        ms().collateralsOf[account].removeAddress(collateral, depositIdx);
    }

    return (transferAmount, feeValuePaid);
}
