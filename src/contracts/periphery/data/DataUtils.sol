// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Asset} from "common/Types.sol";
import {toWad} from "common/funcs/Math.sol";
import {ICDPState} from "icdp/State.sol";
import {cs} from "common/State.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {WadRay} from "vendor/WadRay.sol";
import {PythView, pushPrice, pythView} from "periphery/Helpers.sol";

using PercentageMath for uint256;
using WadRay for uint256;

library DataUtils {
    using DataUtils for Asset;
    function toDebtValue(
        Asset storage self,
        uint256 price,
        uint256 amount,
        bool noFactor
    ) internal view returns (uint256 value) {
        value = price.wadMul(amount);
        if (!noFactor) value = value.percentMul(self.dFactor);
    }

    function toCollateralValues(
        Asset storage self,
        uint256 price,
        uint256 amount
    ) internal view returns (uint256 value, uint256 valueAdj) {
        value = toCollateralValue(self, price, amount, true);
        valueAdj = value.percentMul(self.factor);
    }

    function toCollateralValue(
        Asset storage self,
        uint256 price,
        uint256 amount,
        bool noFactor
    ) internal view returns (uint256 value) {
        value = toWad(amount, self.decimals).wadMul(price);
        if (!noFactor) value = value.percentMul(self.factor);
    }

    function toValues(
        Asset storage self,
        uint256 price,
        uint256 amount,
        uint256 factor
    ) internal view returns (uint256 value, uint256 valueAdj) {
        value = toWad(amount, self.decimals).wadMul(price);
        valueAdj = value.percentMul(factor);
    }

    function getPrice(Asset storage self, PythView calldata prices) internal view returns (uint256) {
        return
            uint256(
                prices.ids.length == 0 ? pushPrice(self.oracles, self.ticker).answer : pythView(self.ticker, prices).answer
            );
    }

    function accountTotalDebtValue(
        ICDPState storage self,
        PythView calldata prices,
        address acc
    ) internal view returns (uint256 value) {
        address[] memory assets = self.mints[acc];
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = cs().assets[assets[i]];
            unchecked {
                value += asset.toDebtValue(asset.getPrice(prices), self.accountDebtAmount(acc, assets[i], asset), false);
                ++i;
            }
        }
        return value;
    }

    function accountTotalCollateralValue(
        ICDPState storage self,
        PythView calldata prices,
        address acc
    ) internal view returns (uint256 totalVal) {
        address[] memory assets = self.collateralsOf[acc];
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = cs().assets[assets[i]];
            unchecked {
                totalVal += asset.toCollateralValue(
                    asset.getPrice(prices),
                    self.accountCollateralAmount(acc, assets[i], asset),
                    false
                );
                ++i;
            }
        }

        return totalVal;
    }
}
