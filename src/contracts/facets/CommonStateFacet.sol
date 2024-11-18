// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {ICommonStateFacet} from "interfaces/ICommonStateFacet.sol";

import {Enums} from "common/Constants.sol";
import {cs} from "common/State.sol";
import {Price} from "common/funcs/Price.sol";
import {Oracle, OraclePrice} from "common/Types.sol";

contract CommonStateFacet is ICommonStateFacet {
    /// @inheritdoc ICommonStateFacet
    function getFeeRecipient() external view returns (address) {
        return cs().feeRecipient;
    }

    /// @inheritdoc ICommonStateFacet
    function getPythEndpoint() external view returns (address) {
        return cs().pythEp;
    }

    /// @inheritdoc ICommonStateFacet
    function getOracleDecimals() external view returns (uint8) {
        return cs().oracleDecimals;
    }

    /// @inheritdoc ICommonStateFacet
    function getMarketStatusProvider() external view returns (address) {
        return cs().marketStatusProvider;
    }

    /// @inheritdoc ICommonStateFacet
    function getKCLV3() external view returns (address) {
        return cs().kopioCLV3;
    }

    /// @inheritdoc ICommonStateFacet
    function getOracleDeviationPct() external view returns (uint16) {
        return cs().maxPriceDeviationPct;
    }

    /// @inheritdoc ICommonStateFacet
    function getSequencerUptimeFeed() external view returns (address) {
        return cs().sequencerUptimeFeed;
    }

    /// @inheritdoc ICommonStateFacet
    function getSequencerGracePeriod() external view returns (uint32) {
        return cs().sequencerGracePeriodTime;
    }

    /// @inheritdoc ICommonStateFacet
    function getOracleOfTicker(bytes32 _ticker, Enums.OracleType _oracleType) public view returns (Oracle memory) {
        return cs().oracles[_ticker][_oracleType];
    }

    /// @inheritdoc ICommonStateFacet
    function getPythPrice(bytes32 _ticker) external view returns (uint256) {
        return getOraclePrice(_ticker, Enums.OracleType.Pyth).answer;
    }

    /// @inheritdoc ICommonStateFacet
    function getAPI3Price(bytes32 _ticker) external view returns (uint256) {
        return getOraclePrice(_ticker, Enums.OracleType.API3).answer;
    }

    /// @inheritdoc ICommonStateFacet
    function getVaultPrice(bytes32 _ticker) external view returns (uint256) {
        return getOraclePrice(_ticker, Enums.OracleType.Vault).answer;
    }

    /// @inheritdoc ICommonStateFacet
    function getChainlinkPrice(bytes32 _ticker) external view returns (uint256) {
        return getOraclePrice(_ticker, Enums.OracleType.Chainlink).answer;
    }

    /// @inheritdoc ICommonStateFacet
    function getChainlinkDerivedPrice(bytes32 _ticker) external view returns (uint256) {
        return getOraclePrice(_ticker, Enums.OracleType.ChainlinkDerived).answer;
    }

    /// @inheritdoc ICommonStateFacet
    function getOraclePrice(bytes32 _ticker, Enums.OracleType _oracle) public view returns (OraclePrice memory) {
        return Price.getUnsafe(_oracle, getOracleOfTicker(_ticker, _oracle));
    }
}
