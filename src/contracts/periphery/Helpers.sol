// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Enums, Prices, Oracle, OraclePrice} from "common/Types.sol";
import {Price, err, cs} from "common/funcs/Price.sol";
import {PythView} from "kopio/vendor/Pyth.sol";
import {Utils} from "kopio/utils/Libs.sol";

/**
 * @notice Answer from any push-oracle for the given ticker.
 * @param _oracles Oracles.
 * @param _ticker Ticker of the asset.
 * @return OraclePrice Price data.
 */
function pushPrice(Enums.OracleType[2] memory _oracles, bytes32 _ticker) view returns (OraclePrice memory) {
    for (uint256 i; i < _oracles.length; i++) {
        Enums.OracleType oracle = _oracles[i];
        if (oracle != Enums.OracleType.Empty && oracle != Enums.OracleType.Pyth) {
            return Price.getUnsafe(_oracles[i], cs().oracles[_ticker][_oracles[i]]);
        }
    }

    // Revert if no answer is found
    revert err.NO_ORACLE_SET(Utils.str(_ticker));
}

function pythView(bytes32 _ticker, PythView calldata data) view returns (OraclePrice memory) {
    uint8 oracleDec = cs().oracleDecimals;
    if (_ticker == "ONE") return Prices.vault(cs().oracles[_ticker][Enums.OracleType.Vault].feed, oracleDec);

    Oracle memory config = cs().oracles[_ticker][Enums.OracleType.Pyth];

    for (uint256 i; i < data.ids.length; i++) {
        if (data.ids[i] == config.pythId) {
            return
                Prices.toPrice(
                    Prices.getPythAnswer(data.prices[i], oracleDec, config.invertPyth),
                    block.timestamp,
                    block.timestamp,
                    config.pythId
                );
        }
    }

    revert err.PYTH_ID_ZERO(Utils.str(_ticker));
}
