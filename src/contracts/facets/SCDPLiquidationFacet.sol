// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {ISCDPLiquidationFacet, MaxLiqInfo, SCDPLiquidationArgs} from "interfaces/ISCDPLiquidationFacet.sol";
import {Modifiers} from "common/Modifiers.sol";
import {Asset} from "common/Types.sol";
import {scdp, sdi} from "scdp/State.sol";
import {fromWad, valueToAmount} from "common/funcs/Math.sol";
import {cs} from "common/State.sol";
import {handlePythUpdate} from "common/funcs/Utils.sol";
import {SCDPAssetData} from "scdp/Types.sol";
import {Enums} from "common/Constants.sol";
import {err, id} from "common/Errors.sol";
import {burnSCDP} from "common/funcs/Actions.sol";
import {SEvent} from "scdp/Event.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {WadRay} from "vendor/WadRay.sol";

contract SCDPLiquidationFacet is ISCDPLiquidationFacet, Modifiers {
    using PercentageMath for uint256;
    using PercentageMath for uint16;
    using WadRay for uint256;

    /// @inheritdoc ISCDPLiquidationFacet
    function getLiquidatableSCDP() external view returns (bool) {
        return scdp().totalCollateralValueSCDP(false) < sdi().effectiveDebtValue().percentMul(scdp().liquidationThreshold);
    }

    /// @inheritdoc ISCDPLiquidationFacet
    function getMaxLiqValueSCDP(address repayKopio, address seizedAddr) external view returns (MaxLiqInfo memory) {
        Asset storage kopio = cs().onlySwapMintable(repayKopio);
        Asset storage seized = cs().onlyGlobalDepositable(seizedAddr);
        uint256 maxValue = _getMaxLiqValue(kopio, seized, seizedAddr);
        uint256 seizePrice = seized.price();
        uint256 kopioPrice = kopio.price();
        uint256 seizeAmount = fromWad(valueToAmount(maxValue, seizePrice, kopio.liqIncentiveSCDP), seized.decimals);
        return
            MaxLiqInfo({
                account: address(0),
                repayValue: maxValue,
                repayAssetAddr: repayKopio,
                repayAmount: maxValue.wadDiv(kopioPrice),
                repayAssetIndex: 0,
                repayAssetPrice: kopioPrice,
                seizeAssetAddr: seizedAddr,
                seizeAmount: seizeAmount,
                seizeValue: seizeAmount.wadMul(seizePrice),
                seizeAssetPrice: seizePrice,
                seizeAssetIndex: 0
            });
    }

    /// @inheritdoc ISCDPLiquidationFacet
    function liquidateSCDP(SCDPLiquidationArgs memory args, bytes[] calldata prices) external payable nonReentrant {
        handlePythUpdate(prices);

        // begin liquidation logic
        scdp().ensureLiquidatableSCDP();

        Asset storage seized = cs().onlyGlobalDeposited(args.collateral, Enums.Action.SCDPLiquidation);
        Asset storage kopio = cs().onlySwapMintable(args.kopio, Enums.Action.SCDPLiquidation);
        SCDPAssetData storage repayData = scdp().assetData[args.kopio];

        if (args.amount > kopio.toDynamic(repayData.debt)) {
            revert err.LIQUIDATION_AMOUNT_GREATER_THAN_DEBT(id(args.kopio), args.amount, kopio.toDynamic(repayData.debt));
        }

        uint256 repayValue = _getMaxLiqValue(kopio, seized, args.collateral);

        // Bound to max liquidation value
        (repayValue, args.amount) = kopio.boundRepayValue(repayValue, args.amount);
        if (repayValue == 0 || args.amount == 0) {
            revert err.ZERO_VALUE_LIQUIDATION(id(args.kopio), id(args.collateral));
        }

        uint256 seizedAmount = fromWad(valueToAmount(repayValue, seized.price(), kopio.liqIncentiveSCDP), seized.decimals);

        repayData.debt -= burnSCDP(kopio, args.amount, msg.sender);
        (uint128 prevLiqIndex, uint128 nextLiqIndex) = scdp().handleSeizeSCDP(seized, args.collateral, seizedAmount);

        emit SEvent.SCDPLiquidationOccured(
            // solhint-disable-next-line avoid-tx-origin
            tx.origin,
            args.kopio,
            args.amount,
            args.collateral,
            seizedAmount,
            prevLiqIndex,
            nextLiqIndex,
            block.timestamp
        );
    }

    function _getMaxLiqValue(
        Asset storage _repayAsset,
        Asset storage _seizeAsset,
        address _seizeAssetAddr
    ) internal view returns (uint256 maxLiquidatableUSD) {
        uint32 maxLiquidationRatio = scdp().maxLiquidationRatio;
        (uint256 totalCollateralValue, uint256 seizeAssetValue) = scdp().totalCollateralValueSCDP(_seizeAssetAddr, false);
        return
            _calcMaxLiqValue(
                _repayAsset,
                _seizeAsset,
                sdi().effectiveDebtValue().percentMul(maxLiquidationRatio),
                totalCollateralValue,
                seizeAssetValue,
                maxLiquidationRatio
            );
    }

    function _calcMaxLiqValue(
        Asset storage _repayAsset,
        Asset storage _seizeAsset,
        uint256 _minCollateralValue,
        uint256 _totalCollateralValue,
        uint256 _seizeAssetValue,
        uint32 _maxLiquidationRatio
    ) internal view returns (uint256) {
        if (!(_totalCollateralValue < _minCollateralValue)) return 0;
        // Calculate reduction percentage from seizing collateral
        uint256 seizeReductionPct = _repayAsset.liqIncentiveSCDP.percentMul(_seizeAsset.factor);
        // Calculate adjusted seized asset value
        _seizeAssetValue = _seizeAssetValue.percentDiv(seizeReductionPct);
        // Substract reductions from gains to get liquidation factor
        uint256 liquidationFactor = _repayAsset.dFactor.percentMul(_maxLiquidationRatio) - seizeReductionPct;
        // Calculate maximum liquidation value
        uint256 maxLiquidationValue = (_minCollateralValue - _totalCollateralValue).percentDiv(liquidationFactor);
        // Maximum value possible for the seize asset
        return maxLiquidationValue < _seizeAssetValue ? maxLiquidationValue : _seizeAssetValue;
    }
}
