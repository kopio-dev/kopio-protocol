// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {err} from "common/Errors.sol";

using WadRay for uint256;
using PercentageMath for uint256;
using PercentageMath for uint16;

/* -------------------------------------------------------------------------- */
/*                                   General                                  */
/* -------------------------------------------------------------------------- */

/**
 * @notice Calculate amount for value provided with possible incentive multiplier for value.
 * @param val Value to convert into amount.
 * @param price The price to apply.
 * @param multiplier Multiplier to apply, 1e4 = 100.00% precision.
 */
function valueToAmount(uint256 val, uint256 price, uint16 multiplier) pure returns (uint256) {
    return val.percentMul(multiplier).wadDiv(price);
}

/**
 * @notice Converts some decimal precision of `amount` to wad decimal precision, which is 18 decimals.
 * @dev Multiplies if precision is less and divides if precision is greater than 18 decimals.
 * @param amount Amount to convert.
 * @param dec Decimal precision for `amount`.
 * @return uint256 Amount converted to wad precision.
 */
function toWad(uint256 amount, uint8 dec) pure returns (uint256) {
    // Most tokens use 18 decimals.
    if (dec == 18 || amount == 0) return amount;

    if (dec < 18) {
        // Multiply for decimals less than 18 to get a wad value out.
        // If the token has 17 decimals, multiply by 10 ** (18 - 17) = 10
        // Results in a value of 1e18.
        return amount * (10 ** (18 - dec));
    }

    // Divide for decimals greater than 18 to get a wad value out.
    // Loses precision, eg. 1 wei of token with 19 decimals:
    // Results in 1 / 10 ** (19 - 18) =  1 / 10 = 0.
    return amount / (10 ** (dec - 18));
}

function toWad(int256 amount, uint8 dec) pure returns (uint256) {
    if (amount < 0) {
        revert err.TO_WAD_AMOUNT_IS_NEGATIVE(amount);
    }
    return toWad(uint256(amount), dec);
}

/**
 * @notice  Converts wad precision `amount`  to some decimal precision.
 * @dev Multiplies if precision is greater and divides if precision is less than 18 decimals.
 * @param wad Wad amount to convert.
 * @param dec Decimals for the result.
 * @return uint256 Converted amount.
 */
function fromWad(uint256 wad, uint8 dec) pure returns (uint256) {
    // Most tokens use 18 decimals.
    if (dec == 18 || wad == 0) return wad;

    if (dec < 18) {
        // Divide if decimals are less than 18 to get the correct amount out.
        // If token has 17 decimals, dividing by 10 ** (18 - 17) = 10
        // Results in a value of 1e17, which can lose precision.
        return wad / (10 ** (18 - dec));
    }
    // Multiply for decimals greater than 18 to get the correct amount out.
    // If the token has 19 decimals, multiply by 10 ** (19 - 18) = 10
    // Results in a value of 1e19.
    return wad * (10 ** (dec - 18));
}

/**
 * @notice Get the value of `amount` and convert to 18 decimal precision.
 * @param amount Amount of tokens to calculate.
 * @param dec Precision of `amount`.
 * @param price Price to use.
 * @param priceDec Precision of `price`.
 * @return uint256 Value of `amount` in 18 decimal precision.
 */
function wadUSD(uint256 amount, uint8 dec, uint256 price, uint8 priceDec) pure returns (uint256) {
    if (amount == 0 || price == 0) return 0;
    return toWad(amount, dec).wadMul(toWad(price, priceDec));
}
