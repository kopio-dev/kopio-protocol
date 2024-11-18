// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {ms} from "icdp/State.sol";
import {cs} from "common/State.sol";
import {IICDPStateFacet} from "interfaces/IICDPStateFacet.sol";
import {ICDPParams} from "icdp/Types.sol";

/**
 * @author the kopio project
 * @title View functions for protocol parameters and asset values
 */
contract ICDPStateFacet is IICDPStateFacet {
    /// @inheritdoc IICDPStateFacet
    function getMCR() external view returns (uint32) {
        return ms().minCollateralRatio;
    }

    /// @inheritdoc IICDPStateFacet
    function getLT() external view returns (uint32) {
        return ms().liquidationThreshold;
    }

    /// @inheritdoc IICDPStateFacet
    function getMinDebtValue() external view returns (uint256) {
        return ms().minDebtValue;
    }

    /// @inheritdoc IICDPStateFacet
    function getMLR() external view returns (uint32) {
        return ms().maxLiquidationRatio;
    }

    /// @inheritdoc IICDPStateFacet
    function getICDPParams() external view returns (ICDPParams memory) {
        return ICDPParams(ms().minCollateralRatio, ms().liquidationThreshold, ms().maxLiquidationRatio, ms().minDebtValue);
    }

    /// @inheritdoc IICDPStateFacet
    function getKopioExists(address addr) external view returns (bool) {
        return cs().assets[addr].isKopio;
    }

    /// @inheritdoc IICDPStateFacet
    function getCollateralExists(address addr) external view returns (bool) {
        return cs().assets[addr].isCollateral;
    }

    /// @inheritdoc IICDPStateFacet
    function getCollateralValueWithPrice(
        address collateral,
        uint256 amount
    ) external view returns (uint256 value, uint256 adjustedValue, uint256 price) {
        return cs().assets[collateral].toValues(amount, cs().assets[collateral].factor);
    }

    /// @inheritdoc IICDPStateFacet
    function getDebtValueWithPrice(
        address asset,
        uint256 amount
    ) external view returns (uint256 value, uint256 adjustedValue, uint256 price) {
        return cs().assets[asset].toValues(amount, cs().assets[asset].dFactor);
    }

    function getMintedSupply(address asset) external view returns (uint256) {
        return cs().assets[asset].getMintedSupply(asset);
    }
}
