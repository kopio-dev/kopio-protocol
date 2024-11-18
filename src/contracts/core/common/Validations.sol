// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import {err, id} from "common/Errors.sol";
import {Constants} from "common/Constants.sol";
import {scdp} from "scdp/State.sol";

// solhint-disable code-complexity
library Validations {
    function validateAddress(address addr) internal pure {
        if (addr == address(0)) revert err.ZERO_ADDRESS();
    }

    function validateOraclePrecision(uint256 _decimalPrecision) internal pure {
        if (_decimalPrecision < Constants.MIN_ORACLE_DECIMALS) {
            revert err.INVALID_PRICE_PRECISION(_decimalPrecision, Constants.MIN_ORACLE_DECIMALS);
        }
    }

    function ensureUnique(address a, address b) internal view {
        if (a == b) revert err.IDENTICAL_ASSETS(id(a));
    }

    function validateRoute(address assetIn, address assetOut) internal view {
        if (!scdp().isRoute[assetIn][assetOut]) revert err.SWAP_ROUTE_NOT_ENABLED(id(assetIn), id(assetOut));
    }

    function validateUint128(address asset, uint256 val) internal view {
        if (val > type(uint128).max) {
            revert err.UINT128_OVERFLOW(id(asset), val, type(uint128).max);
        }
    }
}
