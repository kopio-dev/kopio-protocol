// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {PercentageMath} from "vendor/PercentageMath.sol";
import {WadRay} from "vendor/WadRay.sol";
import {Asset} from "common/Types.sol";
import {cs} from "common/State.sol";
import {scdp} from "scdp/State.sol";

/* -------------------------------------------------------------------------- */
/*                                   Helpers                                  */
/* -------------------------------------------------------------------------- */
using WadRay for uint256;
using PercentageMath for uint256;

/**
 * @notice Calculates the total collateral value of collateral assets in the pool.
 * @return value in USD
 * @return valueAdj Value adjusted by cFactors in USD
 */
function totalCollateralValuesSCDP() view returns (uint256 value, uint256 valueAdj) {
    address[] memory assets = scdp().collaterals;
    for (uint256 i; i < assets.length; ) {
        Asset storage asset = cs().assets[assets[i]];
        uint256 amount = scdp().totalDepositAmount(assets[i], asset);
        if (amount != 0) {
            (uint256 val, uint256 valAdj, ) = asset.toValues(amount, asset.factor);
            value += val;
            valueAdj += valAdj;
        }

        unchecked {
            i++;
        }
    }
}

/**
 * @notice Returns the values of the kopio held in the pool at a ratio.
 * @param _ratio ratio
 * @return value in USD
 * @return valueAdj Value adjusted by dFactors in USD
 */
function totalDebtValuesAtRatioSCDP(uint32 _ratio) view returns (uint256 value, uint256 valueAdj) {
    address[] memory assets = scdp().kopios;
    for (uint256 i; i < assets.length; ) {
        Asset storage asset = cs().assets[assets[i]];
        uint256 amount = asset.toDynamic(scdp().assetData[assets[i]].debt);
        unchecked {
            if (amount != 0) {
                (uint256 val, uint256 valAdj, ) = asset.toValues(amount, asset.dFactor);
                value += val;
                valueAdj += valAdj;
            }
            i++;
        }
    }

    if (_ratio != 1e4) {
        value = value.percentMul(_ratio);
        valueAdj = valueAdj.percentMul(_ratio);
    }
}
