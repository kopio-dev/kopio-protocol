// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {WadRay} from "vendor/WadRay.sol";
import {Strings} from "vendor/Strings.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {IMarketStatus} from "interfaces/IMarketStatus.sol";

import {err} from "common/Errors.sol";
import {cs} from "common/State.sol";
import {scdp, sdi} from "scdp/State.sol";
import {isSequencerUp} from "common/funcs/Utils.sol";
import {OraclePrice, Oracle} from "common/Types.sol";
import {Percents, Enums} from "common/Constants.sol";
import {toWad} from "common/funcs/Math.sol";
import {Prices} from "libs/Prices.sol";

using WadRay for uint256;
using PercentageMath for uint256;
using Strings for bytes32;

/**
 * @notice Gets the oracle price using safety checks for deviation and sequencer uptime
 * @notice Reverts when price deviates more than `_oracleDeviationPct`
 * @notice Allows stale price when market is closed, market status must be checked before calling this function if needed.
 * @param _ticker Ticker of the price
 * @param _oracles The list of oracle identifiers
 * @param _oracleDeviationPct the deviation percentage
 */
function safePrice(bytes32 _ticker, Enums.OracleType[2] memory _oracles, uint256 _oracleDeviationPct) view returns (uint256) {
    Oracle memory primaryConfig = cs().oracles[_ticker][_oracles[0]];
    Oracle memory referenceConfig = cs().oracles[_ticker][_oracles[1]];

    bool isClosed = (primaryConfig.isClosable || referenceConfig.isClosable) &&
        !IMarketStatus(cs().marketStatusProvider).getTickerStatus(_ticker);

    uint256 primaryPrice = Price.get(_oracles[0], primaryConfig, isClosed).result(true);
    uint256 referencePrice = Price.get(_oracles[1], referenceConfig, isClosed).result(false);

    // Enums.OracleType.Vault uses the same check, reverting if the sequencer is down.
    if (!isSequencerUp(cs().sequencerUptimeFeed, cs().sequencerGracePeriodTime)) {
        revert err.L2_SEQUENCER_DOWN();
    }

    return deducePrice(primaryPrice, referencePrice, _oracleDeviationPct);
}

/**
 * @notice Checks the primary and reference price for deviations.
 * @notice Reverts if the price deviates more than `_oracleDeviationPct`
 * @param _primaryPrice the primary price source to use
 * @param _referencePrice the reference price to compare primary against
 * @param _oracleDeviationPct the deviation percentage to use for the oracle
 * @return uint256 Primary price if its within deviation range of reference price.
 * = reverts if price deviates more than `_oracleDeviationPct`
 */
function deducePrice(uint256 _primaryPrice, uint256 _referencePrice, uint256 _oracleDeviationPct) pure returns (uint256) {
    if (_primaryPrice != 0 && _referencePrice == 0) return _primaryPrice;

    if (
        (_referencePrice.percentMul(1e4 - _oracleDeviationPct) <= _primaryPrice) &&
        (_referencePrice.percentMul(1e4 + _oracleDeviationPct) >= _primaryPrice)
    ) {
        return _primaryPrice;
    }

    // Revert if price deviates more than `_oracleDeviationPct`
    revert err.PRICE_UNSTABLE(_primaryPrice, _referencePrice, _oracleDeviationPct);
}

/// @notice Get the price of SDI in USD at 18 decimal precision.
function SDIPrice() view returns (uint256) {
    uint256 totalValue = scdp().totalDebtValueAtRatioSCDP(Percents.HUNDRED, false);
    if (totalValue == 0) {
        return 1e18;
    }
    return toWad(totalValue, cs().oracleDecimals).wadDiv(sdi().totalDebt);
}

library Price {
    function get(Enums.OracleType oracle, Oracle memory cfg, bool allowStale) internal view returns (OraclePrice memory) {
        return _get(oracle, cfg, !allowStale ? cfg.staleTime : 4 days);
    }

    function get(Enums.OracleType oracle, Oracle memory cfg) internal view returns (OraclePrice memory) {
        return _get(oracle, cfg, cfg.staleTime);
    }

    function getUnsafe(Enums.OracleType oracle, Oracle memory cfg) internal view returns (OraclePrice memory) {
        return _get(oracle, cfg, 365 days);
    }

    function _get(Enums.OracleType oracle, Oracle memory cfg, uint256 st) private view returns (OraclePrice memory r) {
        if (oracle == Enums.OracleType.Pyth)
            return Prices.pyth(cs().pythEp, cs().oracleDecimals, cfg.pythId, cfg.invertPyth, st);
        if (oracle == Enums.OracleType.Chainlink) return Prices.chainlink(cs().kopioCLV3, cfg.feed, st);
        if (oracle == Enums.OracleType.ChainlinkDerived) return Prices.chainlinkDerived(cs().kopioCLV3, cfg.feed, st);
        if (oracle == Enums.OracleType.Vault) return Prices.vault(cfg.feed, cs().oracleDecimals);
        if (oracle == Enums.OracleType.API3) return Prices.API3(cfg.feed, st, cs().oracleDecimals);
    }
}
