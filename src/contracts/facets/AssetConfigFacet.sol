// solhint-disable avoid-low-level-calls
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import {CommonConfigFacet} from "facets/CommonConfigFacet.sol";
import {IAssetConfigFacet} from "interfaces/IAssetConfigFacet.sol";
import {DSModifiers} from "diamond/DSModifiers.sol";
import {Modifiers} from "common/Modifiers.sol";

import {WadRay} from "vendor/WadRay.sol";
import {Arrays} from "libs/Arrays.sol";
import {Strings} from "vendor/Strings.sol";

import {scdp} from "scdp/State.sol";
import {MEvent} from "icdp/Event.sol";
import {ms} from "icdp/State.sol";

import {id, err} from "common/Errors.sol";
import {Role, Enums} from "common/Constants.sol";
import {Asset, TickerOracles} from "common/Types.sol";
import {cs} from "common/State.sol";
import {ValidationsConfig} from "common/ValidationsConfig.sol";
import {SCDPSeizeData} from "scdp/Types.sol";

// solhint-disable code-complexity
contract AssetConfigFacet is IAssetConfigFacet, Modifiers, DSModifiers {
    using Strings for bytes32;
    using Arrays for address[];
    using Arrays for address[2];
    using ValidationsConfig for Asset;
    using ValidationsConfig for address;

    /// @inheritdoc IAssetConfigFacet
    function addAsset(
        address asset,
        Asset memory newCfg,
        TickerOracles memory _feedConfig
    ) external onlyRole(Role.ADMIN) returns (Asset memory) {
        (string memory symbol, string memory tickerStr, uint8 decimals) = asset.validateAddAssetArgs(newCfg);
        newCfg.decimals = decimals;

        if (ValidationsConfig.validateCollateral(asset, newCfg)) {
            ms().collaterals.push(asset);

            emit MEvent.CollateralAdded(tickerStr, symbol, asset, newCfg.factor, newCfg.share, newCfg.liqIncentive);
        }
        if (ValidationsConfig.validateKopio(asset, newCfg)) {
            emit MEvent.KopioAdded(
                tickerStr,
                symbol,
                asset,
                newCfg.share,
                newCfg.dFactor,
                newCfg.mintLimit,
                newCfg.closeFee,
                newCfg.openFee
            );
            ms().kopios.push(asset);
        }
        if (ValidationsConfig.validateSCDPDepositable(asset, newCfg)) {
            scdp().assetIndexes[asset].currFeeIndex = WadRay.RAY128;
        }
        if (ValidationsConfig.validateSCDPKopio(asset, newCfg)) {
            scdp().kopios.push(asset);
        }
        if (newCfg.isSwapMintable || newCfg.isGlobalDepositable) {
            newCfg.isGlobalCollateral = true;
            scdp().assetIndexes[asset].currLiqIndex = WadRay.RAY128;
            scdp().seizeEvents[asset][WadRay.RAY] = SCDPSeizeData({
                prevLiqIndex: 0,
                feeIndex: scdp().assetIndexes[asset].currFeeIndex,
                liqIndex: WadRay.RAY128
            });
            scdp().isEnabled[asset] = true;
            scdp().collaterals.push(asset);
        }

        /* ------------------------------- Save Asset ------------------------------- */
        cs().assets[asset] = newCfg;

        // possibly save feeds
        if (!_feedConfig.feeds.empty()) {
            (bool success, ) = address(this).delegatecall(
                abi.encodeWithSelector(CommonConfigFacet.setFeedsForTicker.selector, newCfg.ticker, _feedConfig)
            );
            if (!success) {
                revert err.ASSET_SET_FEEDS_FAILED(id(asset));
            }
        }
        ValidationsConfig.validatePushPrice(asset);
        return newCfg;
    }

    /// @inheritdoc IAssetConfigFacet
    function updateAsset(address asset, Asset memory newCfg) external onlyRole(Role.ADMIN) returns (Asset memory) {
        (string memory symbol, string memory tickerStr, Asset storage cfg) = asset.validateUpdateAssetArgs(newCfg);

        cfg.ticker = newCfg.ticker;
        cfg.oracles = newCfg.oracles;

        if (ValidationsConfig.validateCollateral(asset, newCfg)) {
            cfg.factor = newCfg.factor;
            cfg.liqIncentive = newCfg.liqIncentive;
            cfg.isCollateral = true;
            ms().collaterals.pushUnique(asset);
            emit MEvent.CollateralUpdated(tickerStr, symbol, asset, newCfg.factor, newCfg.share, newCfg.liqIncentive);
        } else if (cfg.isCollateral) {
            cfg.liqIncentive = 0;
            cfg.isCollateral = false;
            ms().collaterals.removeExisting(asset);
        }

        if (ValidationsConfig.validateKopio(asset, newCfg)) {
            cfg.dFactor = newCfg.dFactor;
            cfg.mintLimit = newCfg.mintLimit;
            cfg.closeFee = newCfg.closeFee;
            cfg.openFee = newCfg.openFee;
            cfg.share = newCfg.share;
            cfg.isKopio = true;
            ms().kopios.pushUnique(asset);

            emit MEvent.KopioUpdated(
                tickerStr,
                symbol,
                asset,
                newCfg.share,
                newCfg.dFactor,
                newCfg.mintLimit,
                newCfg.closeFee,
                newCfg.openFee
            );
        } else if (cfg.isKopio) {
            cfg.mintLimit = 0;
            cfg.isKopio = false;
            ms().kopios.removeExisting(asset);
        }

        if (ValidationsConfig.validateSCDPDepositable(asset, newCfg)) {
            if (scdp().assetIndexes[asset].currFeeIndex == 0) {
                scdp().assetIndexes[asset].currFeeIndex = WadRay.RAY128;
            }
            cfg.depositLimitSCDP = newCfg.depositLimitSCDP;
            cfg.isGlobalDepositable = true;
        } else if (cfg.isGlobalDepositable) {
            cfg.depositLimitSCDP = 0;
            cfg.isGlobalDepositable = false;
        }

        if (ValidationsConfig.validateSCDPKopio(asset, newCfg)) {
            cfg.swapInFee = newCfg.swapInFee;
            cfg.swapOutFee = newCfg.swapOutFee;
            cfg.protocolFeeShareSCDP = newCfg.protocolFeeShareSCDP;
            cfg.liqIncentiveSCDP = newCfg.liqIncentiveSCDP;
            cfg.mintLimitSCDP = newCfg.mintLimitSCDP;
            cfg.isSwapMintable = true;
            scdp().kopios.pushUnique(asset);
        } else if (cfg.isSwapMintable) {
            cfg.isSwapMintable = false;
            cfg.liqIncentiveSCDP = 0;
            scdp().kopios.removeExisting(asset);
        }

        if (cfg.isGlobalDepositable || cfg.isSwapMintable) {
            cfg.isGlobalCollateral = true;
            if (scdp().assetIndexes[asset].currLiqIndex == 0) {
                scdp().assetIndexes[asset].currLiqIndex = WadRay.RAY128;
                scdp().seizeEvents[asset][WadRay.RAY] = SCDPSeizeData({
                    prevLiqIndex: 0,
                    feeIndex: scdp().assetIndexes[asset].currFeeIndex,
                    liqIndex: WadRay.RAY128
                });
            }
            scdp().collaterals.pushUnique(asset);
        } else {
            cfg.isGlobalCollateral = false;
        }

        ValidationsConfig.validatePushPrice(asset);

        return cfg;
    }

    /// @inheritdoc IAssetConfigFacet
    function setCFactor(address asset, uint16 newFactor) public onlyRole(Role.ADMIN) {
        Asset storage cfg = cs().onlyExistingAsset(asset);
        ValidationsConfig.validateCFactor(asset, newFactor);

        emit MEvent.CFactorUpdated(id(asset).symbol, asset, cfg.factor, newFactor);
        cfg.factor = newFactor;
    }

    /// @inheritdoc IAssetConfigFacet
    function setDFactor(address asset, uint16 newFactor) public onlyRole(Role.ADMIN) {
        Asset storage cfg = cs().onlyExistingAsset(asset);
        ValidationsConfig.validateDFactor(asset, newFactor);

        emit MEvent.DFactorUpdated(id(asset).symbol, asset, cfg.dFactor, newFactor);
        cfg.dFactor = newFactor;
    }

    /// @inheritdoc IAssetConfigFacet
    function setOracleTypes(address asset, Enums.OracleType[2] memory newTypes) external onlyRole(Role.ADMIN) {
        Asset storage cfg = cs().assets[asset];
        if (!cfg.exists()) revert err.INVALID_ASSET(asset);
        cfg.oracles = newTypes;
        ValidationsConfig.validatePushPrice(asset);
    }

    /// @inheritdoc IAssetConfigFacet
    function validateAssetConfig(address asset, Asset memory cfg) external view returns (bool) {
        return ValidationsConfig.validateAsset(asset, cfg);
    }
}
