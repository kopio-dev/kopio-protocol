// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {WadRay} from "vendor/WadRay.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";
import {fromWad, toWad, wadUSD} from "common/funcs/Math.sol";
import {SDIPrice} from "common/funcs/Price.sol";
import {id, err} from "common/Errors.sol";
import {scdp, SDIState} from "scdp/State.sol";

library SDebtIndex {
    using SafeTransfer for IERC20;
    using WadRay for uint256;

    function cover(SDIState storage self, address asset, uint256 amount, uint256 value) internal {
        scdp().checkCoverableSCDP();
        if (amount == 0) revert err.ZERO_AMOUNT(id(asset));

        IERC20(asset).safeTransferFrom(msg.sender, self.coverRecipient, amount);
        self.totalCover += valueToSDI(value);
    }

    function valueToSDI(uint256 valueWad) internal view returns (uint256) {
        return toWad(valueWad, cs().oracleDecimals).wadDiv(SDIPrice());
    }

    /// @notice Returns the total effective debt amount of the SCDP.
    function effectiveDebt(SDIState storage self) internal view returns (uint256) {
        uint256 currentCover = self.totalCoverAmount();
        uint256 totalDebt = self.totalDebt;
        if (currentCover >= totalDebt) {
            return 0;
        }
        return (totalDebt - currentCover);
    }

    /// @notice Returns the total effective debt value of the SCDP.
    /// @notice Calculation is done in wad precision but returned as oracle precision.
    function effectiveDebtValue(SDIState storage self) internal view returns (uint256 result) {
        uint256 sdiPrice = SDIPrice();
        uint256 coverValue = self.totalCoverValue();
        uint256 coverAmount = coverValue != 0 ? coverValue.wadDiv(sdiPrice) : 0;
        uint256 totalDebt = self.totalDebt;

        if (coverAmount >= totalDebt) return 0;

        if (coverValue == 0) {
            result = totalDebt;
        } else {
            result = (totalDebt - coverAmount);
        }

        return fromWad(result.wadMul(sdiPrice), cs().oracleDecimals);
    }

    function totalCoverAmount(SDIState storage self) internal view returns (uint256) {
        return self.totalCoverValue().wadDiv(SDIPrice());
    }

    /// @notice Gets the total cover debt value, wad precision
    function totalCoverValue(SDIState storage self) internal view returns (uint256 result) {
        address[] memory assets = self.coverAssets;
        for (uint256 i; i < assets.length; ) {
            unchecked {
                result += coverAssetValue(self, assets[i]);
                i++;
            }
        }
    }

    /// @notice Simply returns the total supply of SDI.
    function totalSDI(SDIState storage self) internal view returns (uint256) {
        return self.totalDebt + self.totalCoverAmount();
    }

    /// @notice Get total deposit value of `asset` in USD, wad precision.
    function coverAssetValue(SDIState storage self, address asset) internal view returns (uint256) {
        uint256 bal = IERC20(asset).balanceOf(self.coverRecipient);
        if (bal == 0) return 0;

        Asset storage cfg = cs().assets[asset];
        if (!cfg.isCoverAsset) return 0;

        return wadUSD(bal, cfg.decimals, cfg.price(), cs().oracleDecimals);
    }
}
