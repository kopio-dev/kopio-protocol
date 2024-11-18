// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {ICommonConfigFacet} from "interfaces/ICommonConfigFacet.sol";
import {IAuthorizationFacet} from "interfaces/IAuthorizationFacet.sol";

import {Strings} from "vendor/Strings.sol";
import {Modifiers} from "common/Modifiers.sol";
import {DSModifiers} from "diamond/DSModifiers.sol";
import {ds} from "diamond/State.sol";
import {MEvent} from "icdp/Event.sol";

import {CommonInitializer, TickerOracles, Oracle, OraclePrice, PythConfig} from "common/Types.sol";
import {Role, Enums, Constants} from "common/Constants.sol";
import {err} from "common/Errors.sol";
import {cs} from "common/State.sol";
import {Auth} from "common/Auth.sol";
import {ValidationsConfig} from "common/ValidationsConfig.sol";
import {ICommonStateFacet} from "interfaces/ICommonStateFacet.sol";

contract CommonConfigFacet is ICommonConfigFacet, Modifiers, DSModifiers {
    using Strings for bytes32;

    function initializeCommon(CommonInitializer calldata args) external initializer(2) {
        cs().entered = Constants.NOT_ENTERED;

        // Setup ADMIN role for configuration
        Auth._grantRole(Role.ADMIN, msg.sender);
        // Council must be a contract.
        Auth.setupSecurityCouncil(args.council);
        setFeeRecipient(args.treasury);
        setOracleDecimals(args.oracleDecimals);
        setSequencerUptimeFeed(args.sequencerUptimeFeed);
        setOracleDeviation(args.maxPriceDeviationPct);
        setSequencerGracePeriod(args.sequencerGracePeriodTime);
        setPythEPs(args.pythEp, args.pythEp);
        setMarketStatusProvider(args.marketStatusProvider);
        setKCLV3(args.kopioCLV3);
        ds().supportedInterfaces[type(IAuthorizationFacet).interfaceId] = true;
        // Revoke admin role from deployer
        Auth._revokeRole(Role.ADMIN, msg.sender);

        // Setup the admin
        Auth._grantRole(Role.DEFAULT_ADMIN, args.admin);
        Auth._grantRole(Role.ADMIN, args.admin);
    }

    /// @inheritdoc ICommonConfigFacet
    function setFeeRecipient(address newRecipient) public override onlyRole(Role.ADMIN) {
        ValidationsConfig.validateFeeRecipient(newRecipient);
        emit MEvent.FeeRecipientUpdated(cs().feeRecipient, newRecipient);
        cs().feeRecipient = newRecipient;
    }

    /// @inheritdoc ICommonConfigFacet
    function setMarketStatusProvider(address newProvider) public override onlyRole(Role.ADMIN) {
        cs().marketStatusProvider = newProvider;
    }

    /// @inheritdoc ICommonConfigFacet
    function setPythEPs(address newEP, address newRelayer) public override onlyRole(Role.ADMIN) {
        if (newEP == address(0)) revert err.ZERO_ADDRESS();
        if (newRelayer == address(0)) newRelayer = newEP;
        cs().pythEp = newEP;
        cs().pythRelayer = newRelayer;
    }

    function setKCLV3(address _kclv3) public onlyRole(Role.ADMIN) {
        if (_kclv3 == address(0)) revert err.ZERO_ADDRESS();
        cs().kopioCLV3 = _kclv3;
    }

    /// @inheritdoc ICommonConfigFacet
    function setOracleDecimals(uint8 newDec) public onlyRole(Role.ADMIN) {
        ValidationsConfig.validateOraclePrecision(newDec);
        cs().oracleDecimals = newDec;
    }

    /// @inheritdoc ICommonConfigFacet
    function setOracleDeviation(uint16 newDeviation) public onlyRole(Role.ADMIN) {
        ValidationsConfig.validatePriceDeviationPct(newDeviation);
        cs().maxPriceDeviationPct = newDeviation;
    }

    /// @inheritdoc ICommonConfigFacet
    function setFeedsForTicker(bytes32 ticker, TickerOracles calldata cfg) external onlyRole(Role.ADMIN) {
        for (uint256 i; i < cfg.oracleIds.length; i++) {
            Enums.OracleType oracle = cfg.oracleIds[i];
            (uint256 st, address feed) = (cfg.staleTimes[i], cfg.feeds[i]);
            if (oracle == Enums.OracleType.Chainlink) setChainLinkFeed(ticker, feed, st, cfg.isClosable);
            if (oracle == Enums.OracleType.API3) setAPI3Feed(ticker, feed, st, cfg.isClosable);
            if (oracle == Enums.OracleType.Vault) setVaultFeed(ticker, feed);
            if (oracle == Enums.OracleType.Pyth)
                setPythFeed(ticker, PythConfig(cfg.pythId, st, cfg.invertPyth, cfg.isClosable));
            if (oracle == Enums.OracleType.ChainlinkDerived) setChainLinkDerivedFeed(ticker, feed, st, cfg.isClosable);
        }
    }

    /// @inheritdoc ICommonConfigFacet
    function setPythFeeds(bytes32[] calldata tickers, PythConfig[] calldata cfg) public onlyRole(Role.ADMIN) {
        if (tickers.length != cfg.length) revert err.ARRAY_LENGTH_MISMATCH("", tickers.length, cfg.length);

        for (uint256 i; i < tickers.length; i++) {
            setPythFeed(tickers[i], cfg[i]);
        }
    }

    function setPythFeed(bytes32 ticker, PythConfig memory cfg) public onlyRole(Role.ADMIN) {
        if (cfg.pythId == bytes32(0)) revert err.PYTH_ID_ZERO(ticker.toString());
        Oracle storage oracle = cs().oracles[ticker][Enums.OracleType.Pyth];

        oracle.pythId = cfg.pythId;
        oracle.staleTime = cfg.staleTime;
        oracle.invertPyth = cfg.invertPyth;
        oracle.isClosable = cfg.isClosable;
    }

    /// @inheritdoc ICommonConfigFacet
    function setChainLinkFeed(bytes32 ticker, address feed, uint256 st, bool closable) public onlyRole(Role.ADMIN) {
        if (feed == address(0)) revert err.FEED_ZERO_ADDRESS(ticker.toString());
        Oracle storage cfg = cs().oracles[ticker][Enums.OracleType.Chainlink];
        cfg.feed = feed;
        cfg.staleTime = st;
        cfg.isClosable = closable;
        _ensurePrice(ticker, Enums.OracleType.Chainlink);
    }

    function setChainLinkDerivedFeed(bytes32 ticker, address feed, uint256 st, bool closable) public onlyRole(Role.ADMIN) {
        if (feed == address(0)) revert err.FEED_ZERO_ADDRESS(ticker.toString());
        Oracle storage cfg = cs().oracles[ticker][Enums.OracleType.ChainlinkDerived];
        cfg.feed = feed;
        cfg.staleTime = st;
        cfg.isClosable = closable;
        _ensurePrice(ticker, Enums.OracleType.ChainlinkDerived);
    }

    /// @inheritdoc ICommonConfigFacet
    function setAPI3Feed(bytes32 ticker, address feed, uint256 st, bool closable) public onlyRole(Role.ADMIN) {
        if (feed == address(0)) revert err.FEED_ZERO_ADDRESS(ticker.toString());
        Oracle storage cfg = cs().oracles[ticker][Enums.OracleType.API3];
        cfg.feed = feed;
        cfg.staleTime = st;
        cfg.isClosable = closable;

        _ensurePrice(ticker, Enums.OracleType.API3);
    }

    /// @inheritdoc ICommonConfigFacet
    function setVaultFeed(bytes32 ticker, address vault) public onlyRole(Role.ADMIN) {
        if (vault == address(0)) revert err.FEED_ZERO_ADDRESS(ticker.toString());
        cs().oracles[ticker][Enums.OracleType.Vault].feed = vault;

        _ensurePrice(ticker, Enums.OracleType.Vault);
    }

    function _ensurePrice(bytes32 ticker, Enums.OracleType oracle) internal view {
        OraclePrice memory price = ICommonStateFacet(address(this)).getOraclePrice(ticker, oracle);
        if (price.answer == 0 || price.oracle != oracle) revert err.INVALID_ORACLE_PRICE(price);
    }

    /// @inheritdoc ICommonConfigFacet
    function setSequencerUptimeFeed(address seqUptimeFeed) public override onlyRole(Role.ADMIN) {
        cs().sequencerUptimeFeed = seqUptimeFeed;
    }

    /// @inheritdoc ICommonConfigFacet
    function setSequencerGracePeriod(uint32 seqGracePeriod) public onlyRole(Role.ADMIN) {
        cs().sequencerGracePeriodTime = seqGracePeriod;
    }
}
