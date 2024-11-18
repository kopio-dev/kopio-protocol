// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {SwapArgs} from "common/Args.sol";

interface ISwapFacet {
    /**
     * @notice Preview output and fees of a swap.
     * @param assetIn asset to provide.
     * @param assetOut asset to receive.
     * @param amountIn amount of assetIn.
     * @return amountOut the amount of `assetOut` for `amountIn`.
     */
    function previewSwapSCDP(
        address assetIn,
        address assetOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut, uint256 feeAmount, uint256 protocolFee);

    /**
     * @notice Swaps kopio to another kopio.
     * Uses the prices provided to determine amount out.
     * @param args selected assets, amounts and price data.
     */
    function swapSCDP(SwapArgs calldata args) external payable;

    /**
     * @notice accumulates fees for depositors as fixed, instantaneous income.
     * @param collateral collateral to cumulate income for
     * @param amount amount of income
     * @return nextLiquidityIndex the next liquidity index for the asset.
     */
    function addGlobalIncome(address collateral, uint256 amount) external payable returns (uint256 nextLiquidityIndex);
}
