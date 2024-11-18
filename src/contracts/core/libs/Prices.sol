// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {WadRay} from "vendor/WadRay.sol";
import {Oracle, OraclePrice} from "common/Types.sol";
import {Enums} from "common/Constants.sol";
import {IPyth, Price} from "kopio/vendor/Pyth.sol";
import {err} from "common/Errors.sol";
import {IKopioCLV3} from "kopio/IKopioCLV3.sol";
import {IAPI3} from "kopio/vendor/IAPI3.sol";
import {fromWad} from "common/funcs/Math.sol";
import {IVaultRateProvider} from "interfaces/IVaultRateProvider.sol";

library Prices {
    using WadRay for uint256;

    /**
     * @notice Answer from Pyth.
     * @notice Mainly JPY/USD needs to be inverted.
     * @param ep Pyth endpoint.
     * @param rdec Result precision.
     * @param id Pyth ID.
     * @param invert Invert the price?
     * @param st Time in seconds for the feed to be considered stale.
     * @return OraclePrice Price data.
     */
    function pyth(address ep, uint8 rdec, bytes32 id, bool invert, uint256 st) internal view returns (OraclePrice memory) {
        Price memory data = IPyth(ep).getPriceNoOlderThan(id, st);

        uint256 answer = getPythAnswer(data, rdec, invert);

        if (answer > type(uint56).max) {
            revert err.INVALID_PYTH_PRICE(id, answer);
        }

        return toPrice(answer, data.publishTime, st, id);
    }

    /**
     * @notice Answer from AggregatorV3 type feed.
     * @notice Zero or negative price and decimal checks done by the aggregator.
     * @param clv3 KopioCLV3 address.
     * @param feed Price feed address.
     * @param st Time in seconds for the feed to be considered stale.
     * @return OraclePrice Price data.
     */
    function chainlink(address clv3, address feed, uint256 st) internal view returns (OraclePrice memory) {
        IKopioCLV3.Answer memory data = IKopioCLV3(clv3).getAnswer(feed);
        return toPrice(data.answer, data.updatedAt, st, Enums.OracleType.Chainlink, feed, 0);
    }

    function chainlink(address clv3, Oracle memory cfg) internal view returns (OraclePrice memory) {
        return chainlink(clv3, cfg.feed, cfg.staleTime);
    }

    /**
     * @notice Derived answer from a ratio feed against an underlying (ETH for LST/LRT).
     * @notice Zero or negative price and decimal checks done by the aggregator.
     * @param clv3 KopioCLV3 address.
     * @param feed Ratio feed address.
     * @param st Time in seconds for the feed to be considered stale.
     * @return OraclePrice Price data.
     */
    function chainlinkDerived(address clv3, address feed, uint256 st) internal view returns (OraclePrice memory) {
        IKopioCLV3.Derived memory data = IKopioCLV3(clv3).getDerivedAnswer(feed);
        return toPrice(data.price, data.updatedAt, st, Enums.OracleType.ChainlinkDerived, feed, 0);
    }

    /**
     * @notice Answer from an API3 feed.
     * @dev API3 always uses 18 decimals of precision.
     * @param feed The feed address.
     * @param st Staleness threshold.
     * @param rdec Decimals to convert to.
     * @return OraclePrice Price data.
     */
    function API3(address feed, uint256 st, uint8 rdec) internal view returns (OraclePrice memory) {
        (int256 answer, uint256 updatedAt) = IAPI3(feed).read();
        return toPrice(fromWad(uint256(answer), rdec), updatedAt, st, Enums.OracleType.API3, feed, 0);
    }

    /**
     * @notice Answer from the vault.
     * @dev Vault exchange rate has 18 decimals.
     * @param vaddr The vault address.
     * @param rdec Decimals to convert to.
     * @return OraclePrice Price data.
     */
    function vault(address vaddr, uint8 rdec) internal view returns (OraclePrice memory) {
        return
            toPrice(
                fromWad(IVaultRateProvider(vaddr).exchangeRate(), rdec),
                block.timestamp,
                block.timestamp,
                Enums.OracleType.Vault,
                vaddr,
                0
            );
    }

    /**
     * @notice Answer that is not stale.
     * @param data Price data to check and get result for.
     * @param primary Is this primary price data? If false, output can be empty.
     */
    function result(OraclePrice memory data, bool primary) internal pure returns (uint256) {
        if (data.isStale) {
            revert err.STALE_ORACLE(uint8(data.oracle), data.feed, data.timestamp, data.staleTime);
        }

        if (primary) {
            require(data.oracle != Enums.OracleType.Empty && data.answer != 0, err.INVALID_ORACLE_PRICE(data));
        }

        return data.answer;
    }

    function toPrice(uint256 answer, uint256 ts, uint256 st, bytes32 pythId) internal view returns (OraclePrice memory) {
        return toPrice(answer, ts, st, Enums.OracleType.Pyth, address(0), pythId);
    }

    function toPrice(
        int256 answer,
        uint256 ts,
        uint256 st,
        address feed,
        Enums.OracleType oracle
    ) internal view returns (OraclePrice memory) {
        if (answer < 0) answer = 0;
        return toPrice(uint256(answer), ts, st, oracle, feed, 0);
    }

    function toPrice(
        uint256 answer,
        uint256 ts,
        uint256 st,
        Enums.OracleType oracle,
        address feed,
        bytes32 pythId
    ) internal view returns (OraclePrice memory r) {
        r = OraclePrice(answer, ts, st, block.timestamp - ts > st, answer <= 0, oracle, feed, pythId);
        if (answer > type(uint64).max) revert err.INVALID_ORACLE_PRICE(r);
    }

    function getPythAnswer(Price memory data, uint8 rdec, bool invert) internal pure returns (uint256) {
        return !invert ? _getPythAnswer(data, rdec) : _invertPythAnswer(data, rdec);
    }

    function _getPythAnswer(Price memory data, uint8 rdec) private pure returns (uint256 price) {
        price = uint64(data.price);
        uint256 exp = uint32(-data.expo);
        if (exp > rdec) return price / 10 ** (exp - rdec);
        if (exp < rdec) return price * 10 ** (rdec - exp);
    }

    function _invertPythAnswer(Price memory data, uint8 rdec) private pure returns (uint256) {
        data.price = int64(uint64(1 * (10 ** uint32(-data.expo)).wadDiv(uint64(data.price))));
        data.expo = -18;
        return _getPythAnswer(data, rdec);
    }
}
