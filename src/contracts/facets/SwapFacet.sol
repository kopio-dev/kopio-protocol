// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IERC20} from "kopio/token/IERC20.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";

import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {Modifiers} from "common/Modifiers.sol";
import {cs} from "common/State.sol";
import {Asset, Enums} from "common/Types.sol";
import {id, err} from "common/Errors.sol";
import {Validations} from "common/Validations.sol";

import {ISwapFacet} from "interfaces/ISwapFacet.sol";
import {scdp} from "scdp/State.sol";
import {SEvent} from "scdp/Event.sol";
import {SwapArgs} from "common/Args.sol";

contract SwapFacet is ISwapFacet, Modifiers {
    using SafeTransfer for IERC20;
    using WadRay for uint256;
    using PercentageMath for uint256;

    /// @inheritdoc ISwapFacet
    function addGlobalIncome(address collateral, uint256 amount) external payable nonReentrant returns (uint256) {
        Asset storage cfg = cs().onlyIncomeAsset(collateral);
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

        emit SEvent.Income(collateral, amount);
        return scdp().cumulateIncome(collateral, cfg, amount);
    }

    /// @inheritdoc ISwapFacet
    function previewSwapSCDP(
        address _assetInAddr,
        address _assetOutAddr,
        uint256 _amountIn
    ) external view returns (uint256 amountOut, uint256 feeAmount, uint256 feeAmountProtocol) {
        Validations.ensureUnique(_assetInAddr, _assetOutAddr);
        Validations.validateRoute(_assetInAddr, _assetOutAddr);

        Asset storage assetIn = cs().onlySwapMintable(_assetInAddr);
        Asset storage assetOut = cs().onlySwapMintable(_assetOutAddr);

        (uint256 feePercentage, uint256 protocolFee) = getSwapFees(assetIn, assetOut);

        // Get the fees from amount in when asset out is not a fee asset.
        if (_assetOutAddr != scdp().feeAsset) {
            feeAmount = _amountIn.percentMul(feePercentage);
            amountOut = assetIn.kopioUSD(_amountIn - feeAmount).wadDiv(assetOut.price());
            feeAmountProtocol = feeAmount.percentMul(protocolFee);
            feeAmount -= feeAmountProtocol;
            // Get the fees from amount out when asset out is a fee asset.
        } else {
            amountOut = assetIn.kopioUSD(_amountIn).wadDiv(assetOut.price());
            feeAmount = amountOut.percentMul(feePercentage);
            amountOut = amountOut - feeAmount;
            feeAmountProtocol = feeAmount.percentMul(protocolFee);
            feeAmount -= feeAmountProtocol;
        }
    }

    /// @inheritdoc ISwapFacet
    function swapSCDP(SwapArgs calldata _args) external payable nonReentrant usePyth(_args.prices) {
        if (_args.amountIn == 0) revert err.SWAP_ZERO_AMOUNT_IN(id(_args.assetIn));
        address receiver = _args.receiver == address(0) ? msg.sender : _args.receiver;
        IERC20(_args.assetIn).safeTransferFrom(msg.sender, address(this), _args.amountIn);

        Asset storage assetIn = cs().onlySwapMintable(_args.assetIn, Enums.Action.SCDPSwap);
        emit SEvent.Swap(
            msg.sender,
            _args.assetIn,
            _args.assetOut,
            _args.amountIn,
            _args.assetOut == scdp().feeAsset
                ? _swapFeeAssetOut(receiver, _args.assetIn, assetIn, _args.amountIn, _args.amountOutMin)
                : _swap(receiver, _args.assetIn, assetIn, _args.assetOut, _args.amountIn, _args.amountOutMin),
            block.timestamp
        );
    }

    /**
     * @notice Swaps assets in the collateral pool.
     * @param _receiver The address to receive the swapped assets.
     * @param _assetInAddr The asset to swap in.
     * @param _assetIn The asset in struct.
     * @param _assetOutAddr The asset to swap out.
     * @param _amountIn The amount of `_assetIn` to swap in.
     * @param _amountOutMin The minimum amount of `_assetOut` to receive.
     */
    function _swap(
        address _receiver,
        address _assetInAddr,
        Asset storage _assetIn,
        address _assetOutAddr,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) private returns (uint256 amountOut) {
        Validations.ensureUnique(_assetInAddr, _assetOutAddr);
        Validations.validateRoute(_assetInAddr, _assetOutAddr);
        Asset storage assetOut = cs().onlySwapMintable(_assetOutAddr, Enums.Action.SCDPSwap);
        // Check that assets can be swapped, get the fee percentages.

        (uint256 feePercentage, uint256 protocolFee) = getSwapFees(_assetIn, assetOut);

        // Get the fees from amount received.
        uint256 feeAmount = _amountIn.percentMul(feePercentage);

        unchecked {
            _amountIn -= feeAmount;
        }
        // Assets received pay off debt and/or increase SCDP owned collateral.
        uint256 valueIn = scdp().handleAssetsIn(
            _assetInAddr,
            _assetIn,
            _amountIn, // Work with fee reduced amount from here.
            address(this)
        );

        // Assets sent out are newly minted debt and/or SCDP owned collateral.
        amountOut = scdp().handleAssetsOut(_assetOutAddr, assetOut, valueIn, _receiver);

        // State modifications done, check MCR and slippage.
        _checkAndPayFees(_assetInAddr, _assetIn, amountOut, _amountOutMin, feeAmount, protocolFee);
    }

    /**
     * @notice Swaps asset to the fee asset in the collateral pool.
     * @param _receiver The address to receive the swapped assets.
     * @param _assetInAddr The asset to swap in.
     * @param _assetIn The asset in struct.
     * @param _amountIn The amount of `_assetIn` to swap in.
     * @param _amountOutMin The minimum amount of `_assetOut` to receive.
     */
    function _swapFeeAssetOut(
        address _receiver,
        address _assetInAddr,
        Asset storage _assetIn,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) private returns (uint256 amountOut) {
        address assetOutAddr = scdp().feeAsset;
        Asset storage assetOut = cs().onlySwapMintable(assetOutAddr, Enums.Action.SCDPSwap);
        // Check that assets can be swapped, get the fee percentages.
        Validations.ensureUnique(_assetInAddr, assetOutAddr);
        Validations.validateRoute(_assetInAddr, assetOutAddr);

        // Get the fee percentages.
        (uint256 feePercentage, uint256 protocolFee) = getSwapFees(_assetIn, assetOut);

        // Assets sent out are newly minted debt and/or SCDP owned collateral.
        amountOut = scdp().handleAssetsOut(
            assetOutAddr,
            assetOut,
            // Assets received pay off debt and/or increase SCDP owned collateral.
            scdp().handleAssetsIn(_assetInAddr, _assetIn, _amountIn, address(this)),
            address(this)
        );

        uint256 feeAmount = amountOut.percentMul(feePercentage);
        unchecked {
            amountOut -= feeAmount;
        }

        IERC20(assetOutAddr).safeTransfer(_receiver, amountOut);

        // State modifications done, check MCR and slippage.
        _checkAndPayFees(assetOutAddr, assetOut, amountOut, _amountOutMin, feeAmount, protocolFee);
    }

    /**
     * @notice Swaps assets in the collateral pool.
     * @param _receiver The address to receive the swapped assets.
     * @param _assetInAddr The asset to swap in.
     * @param _assetIn The asset in struct.
     * @param _assetOutAddr The asset to swap out.
     * @param _assetOut The asset out struct.
     * @param _amountIn The amount of `_assetIn` to swap in
     */
    function _swapToFeeAsset(
        address _receiver,
        address _assetInAddr,
        Asset storage _assetIn,
        address _assetOutAddr,
        Asset storage _assetOut,
        uint256 _amountIn
    ) private returns (uint256) {
        Validations.ensureUnique(_assetInAddr, _assetOutAddr);
        return
            scdp().handleAssetsOut(
                _assetOutAddr,
                _assetOut,
                scdp().handleAssetsIn(_assetInAddr, _assetIn, _amountIn, address(this)),
                _receiver
            );
    }

    function _checkAndPayFees(
        address _payAssetAddr,
        Asset storage _payAsset,
        uint256 _amountOut,
        uint256 _amountOutMin,
        uint256 _feeAmount,
        uint256 _protocolFeePct
    ) private {
        // State modifications done, check MCR and slippage.
        if (_amountOut < _amountOutMin) {
            revert err.RECEIVED_LESS_THAN_DESIRED(id(_payAssetAddr), _amountOut, _amountOutMin);
        }

        if (_feeAmount > 0) {
            address feeAssetAddr = scdp().feeAsset;
            _paySwapFees(feeAssetAddr, cs().assets[feeAssetAddr], _payAssetAddr, _payAsset, _feeAmount, _protocolFeePct);
        }
        scdp().ensureCollateralRatio(scdp().minCollateralRatio);
    }

    function _paySwapFees(
        address _feeAssetAddress,
        Asset storage _feeAsset,
        address _payAssetAddress,
        Asset storage _payAsset,
        uint256 _feeAmount,
        uint256 _protocolFeePct
    ) private {
        if (_feeAssetAddress != _payAssetAddress) {
            _feeAmount = _swapToFeeAsset(address(this), _payAssetAddress, _payAsset, _feeAssetAddress, _feeAsset, _feeAmount);
        }

        uint256 protocolFeeTaken = _feeAmount.percentMul(_protocolFeePct);
        unchecked {
            _feeAmount -= protocolFeeTaken;
        }

        if (_feeAmount != 0) scdp().cumulateIncome(_feeAssetAddress, _feeAsset, _feeAmount);
        if (protocolFeeTaken != 0) {
            IERC20 feeToken = IERC20(_feeAssetAddress);
            uint256 balance = feeToken.balanceOf(address(this));
            uint256 protocolFeeToSend = balance < protocolFeeTaken ? balance : protocolFeeTaken;
            feeToken.safeTransfer(cs().feeRecipient, protocolFeeToSend);
        }

        emit SEvent.SwapFee(_feeAssetAddress, _payAssetAddress, _feeAmount, protocolFeeTaken, block.timestamp);
    }
}

/**
 * @notice Get fee percentage for a swap pair.
 * @return feePercentage fee percentage for this swap
 * @return protocolFee protocol fee percentage taken from the fee
 */
function getSwapFees(
    Asset storage _assetIn,
    Asset storage _assetOut
) view returns (uint256 feePercentage, uint256 protocolFee) {
    unchecked {
        feePercentage = _assetIn.swapInFee + _assetOut.swapOutFee;
        protocolFee = _assetIn.protocolFeeShareSCDP + _assetOut.protocolFeeShareSCDP;
    }
}
