// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Strings} from "vendor/Strings.sol";
import {SDIPrice} from "common/funcs/Price.sol";
import {cs} from "common/State.sol";
import {Role, Enums} from "common/Constants.sol";
import {Modifiers} from "common/Modifiers.sol";
import {id, err} from "common/Errors.sol";
import {ValidationsConfig} from "common/ValidationsConfig.sol";
import {Asset} from "common/Types.sol";

import {DSModifiers} from "diamond/DSModifiers.sol";

import {sdi, scdp} from "scdp/State.sol";
import {ISDIFacet} from "interfaces/ISDIFacet.sol";
import {fromWad, valueToAmount} from "common/funcs/Math.sol";
import {SEvent} from "scdp/Event.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";

contract SDIFacet is ISDIFacet, DSModifiers, Modifiers {
    using Strings for bytes32;
    using PercentageMath for uint256;
    using PercentageMath for uint16;
    using SafeTransfer for IERC20;

    function totalSDI() external view returns (uint256) {
        return sdi().totalSDI();
    }

    function getTotalSDIDebt() external view returns (uint256) {
        return sdi().totalDebt;
    }

    function getEffectiveSDIDebt() external view returns (uint256) {
        return sdi().effectiveDebt();
    }

    function getEffectiveSDIDebtUSD() external view returns (uint256) {
        return sdi().effectiveDebtValue();
    }

    function getSDICoverAmount() external view returns (uint256) {
        return sdi().totalCoverAmount();
    }

    function previewSCDPBurn(address kopio, uint256 amount, bool noFactors) external view returns (uint256 shares) {
        return cs().assets[kopio].debtToSDI(amount, noFactors);
    }

    function previewSCDPMint(address kopio, uint256 amount, bool noFactors) external view returns (uint256 shares) {
        return cs().assets[kopio].debtToSDI(amount, noFactors);
    }

    /// @notice Get the price of SDI in USD, oracle precision.
    function getSDIPrice() external view returns (uint256) {
        return SDIPrice();
    }

    function getCoverAssetsSDI() external view returns (address[] memory) {
        return sdi().coverAssets;
    }

    /* -------------------------------------------------------------------------- */
    /*                                Functionality                               */
    /* -------------------------------------------------------------------------- */

    function coverSCDP(
        address asset,
        uint256 amount,
        bytes[] calldata prices
    ) external payable usePyth(prices) returns (uint256 value) {
        value = cs().onlyCoverAsset(asset, Enums.Action.SCDPCover).assetUSD(amount);
        sdi().cover(asset, amount, value);
    }

    function coverWithIncentiveSCDP(
        address asset,
        uint256 amount,
        address seizeAsset,
        bytes[] calldata prices
    ) external payable usePyth(prices) returns (uint256 value, uint256 seizedAmount) {
        Asset storage cfg = cs().onlyCoverAsset(asset, Enums.Action.SCDPCover);
        Asset storage cfgSeize = cs().onlyCumulated(seizeAsset, Enums.Action.SCDPCover);

        (value, amount) = cfg.boundRepayValue(_getMaxCoverValue(cfg, cfgSeize, seizeAsset), amount);
        sdi().cover(asset, amount, value);

        seizedAmount = fromWad(valueToAmount(value, cfgSeize.price(), uint16(sdi().coverIncentive)), cfgSeize.decimals);

        if (seizedAmount == 0) {
            revert err.ZERO_REPAY(id(asset), amount, seizedAmount);
        }

        (uint128 prevLiqIndex, uint128 nextLiqIndex) = scdp().handleSeizeSCDP(cfgSeize, seizeAsset, seizedAmount);

        emit SEvent.SCDPCoverOccured(
            // solhint-disable-next-line avoid-tx-origin
            tx.origin,
            asset,
            amount,
            seizeAsset,
            seizedAmount,
            prevLiqIndex,
            nextLiqIndex,
            block.timestamp
        );
    }

    /* -------------------------------------------------------------------------- */
    /*                                    Admin                                   */
    /* -------------------------------------------------------------------------- */

    function enableCoverAssetSDI(address asset) external onlyRole(Role.ADMIN) {
        Asset storage cfg = ValidationsConfig.validateSDICoverAsset(asset);

        cfg.isCoverAsset = true;
        bool shouldPushToAssets = true;
        for (uint256 i; i < sdi().coverAssets.length; i++) {
            if (sdi().coverAssets[i] == asset) {
                shouldPushToAssets = false;
            }
        }
        if (shouldPushToAssets) {
            sdi().coverAssets.push(asset);
        }
    }

    function disableCoverAssetSDI(address asset) external onlyRole(Role.ADMIN) {
        if (!cs().assets[asset].isCoverAsset) {
            revert err.ASSET_ALREADY_DISABLED(id(asset));
        }

        cs().assets[asset].isCoverAsset = false;
    }

    function setCoverRecipientSDI(address newRecipient) external onlyRole(Role.ADMIN) {
        if (newRecipient == address(0)) revert err.ZERO_ADDRESS();
        sdi().coverRecipient = newRecipient;
    }

    function _getMaxCoverValue(
        Asset storage kopio,
        Asset storage seizeAsset,
        address seizeAssetAddr
    ) internal view returns (uint256 maxLiquidatableUSD) {
        uint48 seizeThreshold = sdi().coverThreshold;
        (uint256 totalCollateralValue, uint256 seizeAssetValue) = scdp().totalCollateralValueSCDP(seizeAssetAddr, false);
        return
            _calcMaxCoverValue(
                kopio,
                seizeAsset,
                sdi().effectiveDebtValue().percentMul(seizeThreshold),
                totalCollateralValue,
                seizeAssetValue,
                seizeThreshold
            );
    }

    function _calcMaxCoverValue(
        Asset storage kopio,
        Asset storage seizeAsset,
        uint256 minCollateral,
        uint256 totalCollateral,
        uint256 seizeValue,
        uint48 seizeThreshold
    ) internal view returns (uint256) {
        if (!(totalCollateral < minCollateral)) return 0;
        // Calculate reduction percentage from seizing collateral
        uint256 seizeReductionPct = uint256(sdi().coverIncentive).percentMul(seizeAsset.factor);
        // Calculate adjusted seized asset value
        seizeValue = seizeValue.percentDiv(seizeReductionPct);
        // Substract reductions from gains to get liquidation factor
        uint256 liquidationFactor = kopio.dFactor.percentMul(seizeThreshold) - seizeReductionPct;
        // Calculate maximum liquidation value
        uint256 maxLiquidationValue = (minCollateral - totalCollateral).percentDiv(liquidationFactor);
        // Maximum value possible for the seize asset
        return maxLiquidationValue < seizeValue ? maxLiquidationValue : seizeValue;
    }
}
