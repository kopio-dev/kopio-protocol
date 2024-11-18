// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Arrays} from "libs/Arrays.sol";
import {DSModifiers} from "diamond/DSModifiers.sol";
import {Asset} from "common/Types.sol";
import {Modifiers} from "common/Modifiers.sol";
import {cs} from "common/State.sol";
import {Percents, Role} from "common/Constants.sol";
import {id, err} from "common/Errors.sol";
import {ValidationsConfig} from "common/ValidationsConfig.sol";

import {ISCDPConfigFacet} from "interfaces/ISCDPConfigFacet.sol";
import {SCDPInitializer, SwapRouteSetter, SCDPParameters} from "scdp/Types.sol";
import {scdp, sdi} from "scdp/State.sol";
import {SEvent} from "scdp/Event.sol";

contract SCDPConfigFacet is ISCDPConfigFacet, DSModifiers, Modifiers {
    using Arrays for address[];

    /// @inheritdoc ISCDPConfigFacet
    function initializeSCDP(SCDPInitializer calldata args) external initializer(4) initializeAsAdmin {
        setGlobalMCR(args.minCollateralRatio);
        setGlobalLT(args.liquidationThreshold);
        setCoverThreshold(args.coverThreshold);
        setCoverIncentive(args.coverIncentive);
    }

    /// @inheritdoc ISCDPConfigFacet
    function getGlobalParameters() external view override returns (SCDPParameters memory) {
        return
            SCDPParameters({
                feeAsset: scdp().feeAsset,
                minCollateralRatio: scdp().minCollateralRatio,
                liquidationThreshold: scdp().liquidationThreshold,
                maxLiquidationRatio: scdp().maxLiquidationRatio,
                coverThreshold: sdi().coverThreshold,
                coverIncentive: sdi().coverIncentive
            });
    }

    function setCoverThreshold(uint48 newThreshold) public onlyRole(Role.ADMIN) {
        ValidationsConfig.validateCoverThreshold(newThreshold, scdp().minCollateralRatio);
        sdi().coverThreshold = newThreshold;
    }

    function setCoverIncentive(uint48 newIncentive) public onlyRole(Role.ADMIN) {
        ValidationsConfig.validateCoverIncentive(newIncentive);
        sdi().coverIncentive = newIncentive;
    }

    function setGlobalIncome(address collateral) external onlyRole(Role.ADMIN) {
        cs().onlyGlobalDepositable(collateral);
        scdp().feeAsset = collateral;
    }

    /// @inheritdoc ISCDPConfigFacet
    function setGlobalMCR(uint32 newMCR) public onlyRole(Role.ADMIN) {
        ValidationsConfig.validateMCR(newMCR, scdp().liquidationThreshold);

        emit SEvent.GlobalMCRUpdated(scdp().minCollateralRatio, newMCR);
        scdp().minCollateralRatio = newMCR;
    }

    /// @inheritdoc ISCDPConfigFacet
    function setGlobalLT(uint32 newLT) public onlyRole(Role.ADMIN) {
        ValidationsConfig.validateLT(newLT, scdp().minCollateralRatio);

        uint32 newMLR = newLT + Percents.ONE;

        emit SEvent.GlobalLTUpdated(scdp().liquidationThreshold, newLT, newMLR);
        emit SEvent.GlobalMLRUpdated(scdp().maxLiquidationRatio, newMLR);

        scdp().liquidationThreshold = newLT;
        scdp().maxLiquidationRatio = newMLR;
    }

    function setGlobalMLR(uint32 newMLR) external onlyRole(Role.ADMIN) {
        ValidationsConfig.validateMLR(newMLR, scdp().liquidationThreshold);

        emit SEvent.GlobalMLRUpdated(scdp().maxLiquidationRatio, newMLR);
        scdp().maxLiquidationRatio = newMLR;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Assets                                   */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ISCDPConfigFacet
    function setGlobalDepositLimit(address asset, uint256 newLimit) external onlyRole(Role.ADMIN) {
        Asset storage cfg = cs().onlyGlobalDepositable(asset);
        cfg.depositLimitSCDP = newLimit;
    }

    /// @inheritdoc ISCDPConfigFacet
    function setGlobalLiqIncentive(address kopio, uint16 newIncentive) external onlyRole(Role.ADMIN) {
        ValidationsConfig.validateLiqIncentive(kopio, newIncentive);
        Asset storage cfg = cs().onlySwapMintable(kopio);

        emit SEvent.GlobalLiqIncentiveUpdated(id(kopio).symbol, kopio, cfg.liqIncentiveSCDP, newIncentive);
        cfg.liqIncentiveSCDP = newIncentive;
    }

    /// @inheritdoc ISCDPConfigFacet
    function setGlobalDepositEnabled(address collateral, bool enabled) external onlyRole(Role.ADMIN) {
        Asset storage cfg = cs().onlyExistingAsset(collateral);
        if (enabled && cfg.isGlobalDepositable) revert err.ASSET_ALREADY_ENABLED(id(collateral));
        if (!enabled && !cfg.isGlobalDepositable) revert err.ASSET_ALREADY_DISABLED(id(collateral));
        cfg.isGlobalDepositable = enabled;

        if (!ValidationsConfig.validateSCDPDepositable(collateral, cfg)) {
            cfg.depositLimitSCDP = 0;
            return;
        }
        scdp().collaterals.pushUnique(collateral);
    }

    /// @inheritdoc ISCDPConfigFacet
    function setSwapEnabled(address kopio, bool enabled) external onlyRole(Role.ADMIN) {
        Asset storage cfg = cs().onlyExistingAsset(kopio);
        if (enabled && cfg.isSwapMintable) revert err.ASSET_ALREADY_ENABLED(id(kopio));
        if (!enabled && !cfg.isSwapMintable) revert err.ASSET_ALREADY_DISABLED(id(kopio));

        cfg.isSwapMintable = enabled;

        if (!ValidationsConfig.validateSCDPKopio(kopio, cfg)) {
            if (cfg.toDynamic(scdp().assetData[kopio].debt) != 0) {
                revert err.CANNOT_REMOVE_SWAPPABLE_ASSET_THAT_HAS_DEBT(id(kopio));
            }
            scdp().kopios.removeExisting(kopio);
            cfg.liqIncentiveSCDP = 0;
            return;
        }
        scdp().collaterals.pushUnique(kopio);
        scdp().kopios.pushUnique(kopio);
    }

    function setGlobalCollateralEnabled(address asset, bool enabled) external onlyRole(Role.ADMIN) {
        Asset storage cfg = cs().onlyExistingAsset(asset);
        if (enabled && cfg.isGlobalCollateral) revert err.ASSET_ALREADY_ENABLED(id(asset));
        if (!enabled && !cfg.isGlobalCollateral) revert err.ASSET_ALREADY_DISABLED(id(asset));

        if (enabled) {
            scdp().collaterals.pushUnique(asset);
        } else {
            if (scdp().userDepositAmount(asset, cfg) != 0) {
                revert err.CANNOT_REMOVE_COLLATERAL_THAT_HAS_USER_DEPOSITS(id(asset));
            }
            scdp().collaterals.removeExisting(asset);
            cfg.depositLimitSCDP = 0;
        }
        cfg.isGlobalCollateral = enabled;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Swap                                    */
    /* -------------------------------------------------------------------------- */
    /// @inheritdoc ISCDPConfigFacet
    function setSwapFees(address asset, uint16 feeIn, uint16 feeOut, uint16 protocolShare) external onlyRole(Role.ADMIN) {
        ValidationsConfig.validateFees(asset, feeIn, feeOut);
        ValidationsConfig.validateFees(asset, protocolShare, protocolShare);

        cs().assets[asset].swapInFee = feeIn;
        cs().assets[asset].swapOutFee = feeOut;
        cs().assets[asset].protocolFeeShareSCDP = protocolShare;

        emit SEvent.FeeSet(asset, feeIn, feeOut, protocolShare);
    }

    /// @inheritdoc ISCDPConfigFacet
    function setSwapRoutes(SwapRouteSetter[] calldata pairs) external onlyRole(Role.ADMIN) {
        for (uint256 i; i < pairs.length; i++) {
            scdp().isRoute[pairs[i].assetIn][pairs[i].assetOut] = pairs[i].enabled;
            scdp().isRoute[pairs[i].assetOut][pairs[i].assetIn] = pairs[i].enabled;

            emit SEvent.PairSet(pairs[i].assetIn, pairs[i].assetOut, pairs[i].enabled);
            emit SEvent.PairSet(pairs[i].assetOut, pairs[i].assetIn, pairs[i].enabled);
        }
    }

    /// @inheritdoc ISCDPConfigFacet
    function setSwapRoute(SwapRouteSetter calldata pair) external onlyRole(Role.ADMIN) {
        scdp().isRoute[pair.assetIn][pair.assetOut] = pair.enabled;
        emit SEvent.PairSet(pair.assetIn, pair.assetOut, pair.enabled);
    }
}
