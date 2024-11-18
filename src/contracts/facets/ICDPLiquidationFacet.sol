// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import {IICDPLiquidationFacet} from "interfaces/IICDPLiquidationFacet.sol";

import {IERC20} from "kopio/token/IERC20.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";
import {Arrays} from "libs/Arrays.sol";
import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";

import {id, err} from "common/Errors.sol";
import {valueToAmount, fromWad} from "common/funcs/Math.sol";
import {Modifiers} from "common/Modifiers.sol";
import {Asset, MaxLiqInfo} from "common/Types.sol";
import {cs} from "common/State.sol";
import {Constants, Enums} from "common/Constants.sol";

import {MEvent} from "icdp/Event.sol";
import {ms, ICDPState} from "icdp/State.sol";
import {LiquidateExecution} from "icdp/Types.sol";
import {handleFee} from "icdp/funcs/Fees.sol";
import {LiquidationArgs} from "common/Args.sol";

using Arrays for address[];
using WadRay for uint256;
using SafeTransfer for IERC20;
using PercentageMath for uint256;
using PercentageMath for uint16;

// solhint-disable code-complexity
/**
 * @title ICDPLiquidationFacet
 * @author the kopio project
 */
contract ICDPLiquidationFacet is Modifiers, IICDPLiquidationFacet {
    /// @inheritdoc IICDPLiquidationFacet
    function liquidate(LiquidationArgs calldata args) external payable usePyth(args.prices) nonReentrant {
        if (msg.sender == args.account) revert err.CANNOT_LIQUIDATE_SELF();

        Asset storage repayAsset = cs().onlyKopio(args.kopio, Enums.Action.Liquidation);
        Asset storage seizeAsset = cs().onlyCollateral(args.collateral, Enums.Action.Liquidation);

        ICDPState storage s = ms();
        // The obvious check
        s.checkAccountLiquidatable(args.account);

        // Bound to min debt value or max liquidation value
        (uint256 repayValue, uint256 amount) = repayAsset.boundRepayValue(
            _getMaxLiqValue(args.account, repayAsset, seizeAsset, args.collateral),
            args.amount
        );
        if (repayValue == 0 || amount == 0) {
            revert err.ZERO_VALUE_LIQUIDATION(id(args.kopio), id(args.collateral));
        }

        /* ------------------------------- Charge fee ------------------------------- */
        handleFee(repayAsset, args.account, amount, Enums.ICDPFee.Close);

        /* -------------------------------- Liquidate ------------------------------- */
        LiquidateExecution memory params = LiquidateExecution(
            args.account,
            amount,
            fromWad(valueToAmount(repayValue, seizeAsset.price(), seizeAsset.liqIncentive), seizeAsset.decimals),
            args.kopio,
            args.collateral
        );
        uint256 seizedAmount = _liquidateAssets(seizeAsset, repayAsset, params);

        // Send liquidator the seized collateral.
        IERC20(args.collateral).safeTransfer(msg.sender, seizedAmount);

        emit MEvent.LiquidationOccurred(args.account, msg.sender, args.kopio, amount, args.collateral, seizedAmount);
    }

    /// @inheritdoc IICDPLiquidationFacet
    function getMaxLiqValue(address account, address repayAddr, address seizedAddr) external view returns (MaxLiqInfo memory) {
        Asset storage repayAsset = cs().onlyKopio(repayAddr);
        Asset storage seizeAsset = cs().onlyCollateral(seizedAddr);
        uint256 maxLiqValue = _getMaxLiqValue(account, repayAsset, seizeAsset, seizedAddr);
        uint256 seizePrice = seizeAsset.price();
        uint256 kopioPrice = repayAsset.price();
        uint256 seizeAmount = fromWad(valueToAmount(maxLiqValue, seizePrice, seizeAsset.liqIncentive), seizeAsset.decimals);
        return
            MaxLiqInfo({
                account: account,
                repayValue: maxLiqValue,
                repayAssetAddr: repayAddr,
                repayAmount: maxLiqValue.wadDiv(kopioPrice),
                repayAssetIndex: ms().mints[account].find(repayAddr).index,
                repayAssetPrice: kopioPrice,
                seizeAssetAddr: seizedAddr,
                seizeAmount: seizeAmount,
                seizeValue: seizeAmount.wadMul(seizePrice),
                seizeAssetPrice: seizePrice,
                seizeAssetIndex: ms().collateralsOf[account].find(seizedAddr).index
            });
    }

    function _liquidateAssets(
        Asset storage collateral,
        Asset storage kopio,
        LiquidateExecution memory args
    ) internal returns (uint256 seizedAmount) {
        ICDPState storage s = ms();

        s.burn(kopio, args.kopio, args.account, args.repayAmount, msg.sender);
        uint256 depositAmount = s.accountCollateralAmount(args.account, args.collateral, collateral);

        if (depositAmount == args.seizeAmount) {
            // Remove the collateral deposits.
            s.deposits[args.account][args.collateral] = 0;
            s.collateralsOf[args.account].removeAddress(args.collateral);
            // Seized amount is the collateral deposits.
            return depositAmount;
        }

        if (depositAmount < args.seizeAmount) {
            revert err.LIQUIDATION_SEIZED_LESS_THAN_EXPECTED(id(args.kopio), depositAmount, args.seizeAmount);
        }

        /* ------------------------ Above collateral deposits ----------------------- */
        uint256 newDepositAmount = depositAmount - args.seizeAmount;

        // *EDGE CASE*: If the collateral asset is also a asset, ensure that collateral remains over minimum amount required.
        if (newDepositAmount < Constants.MIN_COLLATERAL && collateral.isKopio) {
            args.seizeAmount -= Constants.MIN_COLLATERAL - newDepositAmount;
            newDepositAmount = Constants.MIN_COLLATERAL;
        }

        s.deposits[args.account][args.collateral] = collateral.toStatic(newDepositAmount);
        return args.seizeAmount;
    }

    function _getMaxLiqValue(
        address account,
        Asset storage _repayAsset,
        Asset storage _seizeAsset,
        address seizedAddr
    ) internal view returns (uint256 maxValue) {
        uint32 maxLiquidationRatio = ms().maxLiquidationRatio;
        (uint256 totalCollateralValue, uint256 seizeAssetValue) = ms().accountTotalCollateralValue(account, seizedAddr);

        return
            _calcMaxLiqValue(
                _repayAsset,
                _seizeAsset,
                ms().accountMinCollateralAtRatio(account, maxLiquidationRatio),
                totalCollateralValue,
                seizeAssetValue,
                ms().minDebtValue,
                maxLiquidationRatio
            );
    }

    function _calcMaxLiqValue(
        Asset storage _repayAsset,
        Asset storage _seizeAsset,
        uint256 _minCollateralValue,
        uint256 _totalCollateralValue,
        uint256 _seizeAssetValue,
        uint256 _minDebtValue,
        uint32 _maxLiquidationRatio
    ) internal view returns (uint256) {
        if (!(_totalCollateralValue < _minCollateralValue)) return 0;
        // Calculate reduction percentage from seizing collateral
        uint256 seizeReductionPct = (_seizeAsset.liqIncentive + _repayAsset.closeFee).percentMul(_seizeAsset.factor);
        // Calculate adjusted seized asset value
        _seizeAssetValue = _seizeAssetValue.percentDiv(seizeReductionPct);
        // Substract reduction from increase to get liquidation factor
        uint256 liquidationFactor = _repayAsset.dFactor.percentMul(_maxLiquidationRatio) - seizeReductionPct;
        // Calculate maximum liquidation value
        uint256 maxLiquidationValue = (_minCollateralValue - _totalCollateralValue).percentDiv(liquidationFactor);
        // Clamped to minimum debt value
        if (_minDebtValue > maxLiquidationValue) return _minDebtValue;
        // Maximum value possible for the seize asset
        return maxLiquidationValue < _seizeAssetValue ? maxLiquidationValue : _seizeAssetValue;
    }
}
