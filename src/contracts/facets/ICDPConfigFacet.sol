// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {id, err} from "common/Errors.sol";
import {Modifiers} from "common/Modifiers.sol";
import {Percents, Role} from "common/Constants.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";
import {ValidationsConfig} from "common/ValidationsConfig.sol";

import {DSModifiers} from "diamond/DSModifiers.sol";

import {IICDPConfigFacet} from "interfaces/IICDPConfigFacet.sol";
import {MEvent} from "icdp/Event.sol";
import {ms} from "icdp/State.sol";
import {ICDPInitializer} from "icdp/Types.sol";

/**
 * @title ICDPConfigFacet
 * @author the kopio protocol
 */
contract ICDPConfigFacet is DSModifiers, Modifiers, IICDPConfigFacet {
    function initializeICDP(ICDPInitializer calldata args) external initializer(3) initializeAsAdmin {
        setMCR(args.minCollateralRatio);
        setLT(args.liquidationThreshold);
        setMinDebtValue(args.minDebtValue);
    }

    /// @inheritdoc IICDPConfigFacet
    function setMinDebtValue(uint256 newValue) public override onlyRole(Role.ADMIN) {
        ValidationsConfig.validateMinDebtValue(newValue);
        emit MEvent.MinimumDebtValueUpdated(ms().minDebtValue, newValue);
        ms().minDebtValue = newValue;
    }

    /// @inheritdoc IICDPConfigFacet
    function setMCR(uint32 newMCR) public override onlyRole(Role.ADMIN) {
        ValidationsConfig.validateMCR(newMCR, ms().liquidationThreshold);
        emit MEvent.MinCollateralRatioUpdated(ms().minCollateralRatio, newMCR);
        ms().minCollateralRatio = newMCR;
    }

    /// @inheritdoc IICDPConfigFacet
    function setLT(uint32 newLT) public override onlyRole(Role.ADMIN) {
        ValidationsConfig.validateLT(newLT, ms().minCollateralRatio);

        uint32 newMLR = newLT + Percents.ONE;

        emit MEvent.LiquidationThresholdUpdated(ms().liquidationThreshold, newLT, newMLR);
        emit MEvent.MaxLiquidationRatioUpdated(ms().maxLiquidationRatio, newMLR);

        ms().liquidationThreshold = newLT;
        ms().maxLiquidationRatio = newMLR;
    }

    /// @inheritdoc IICDPConfigFacet
    function setMLR(uint32 newMLR) public onlyRole(Role.ADMIN) {
        ValidationsConfig.validateMLR(newMLR, ms().liquidationThreshold);
        emit MEvent.MaxLiquidationRatioUpdated(ms().maxLiquidationRatio, newMLR);
        ms().maxLiquidationRatio = newMLR;
    }

    /// @inheritdoc IICDPConfigFacet
    function setLiqIncentive(address collateral, uint16 newIncentive) public onlyRole(Role.ADMIN) {
        Asset storage asset = cs().onlyCollateral(collateral);
        ValidationsConfig.validateLiqIncentive(collateral, newIncentive);

        if (newIncentive < Percents.HUNDRED || newIncentive > Percents.MAX_LIQ_INCENTIVE) {
            revert err.INVALID_LIQ_INCENTIVE(id(collateral), newIncentive, Percents.HUNDRED, Percents.MAX_LIQ_INCENTIVE);
        }
        emit MEvent.LiquidationIncentiveUpdated(id(collateral).symbol, collateral, asset.liqIncentive, newIncentive);
        asset.liqIncentive = newIncentive;
    }
}
