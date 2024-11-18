// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {FixedPointMath} from "vendor/FixedPointMath.sol";
import {IKopio} from "interfaces/IKopio.sol";

library Rebaser {
    using FixedPointMath for uint256;

    /**
     * @notice Unrebase a value by a given rebase struct.
     * @param self The value to unrebase.
     * @param re The rebase struct.
     * @return The unrebased value.
     */
    function unrebase(uint256 self, IKopio.Rebase storage re) internal view returns (uint256) {
        if (re.denominator == 0) return self;
        return re.positive ? self.divWadDown(re.denominator) : self.mulWadDown(re.denominator);
    }

    /**
     * @notice Rebase a value by a given rebase struct.
     * @param self The value to rebase.
     * @param re The rebase struct.
     * @return The rebased value.
     */
    function rebase(uint256 self, IKopio.Rebase storage re) internal view returns (uint256) {
        if (re.denominator == 0) return self;
        return re.positive ? self.mulWadDown(re.denominator) : self.divWadDown(re.denominator);
    }
}
