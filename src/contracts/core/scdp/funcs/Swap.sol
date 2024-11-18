// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {WadRay} from "vendor/WadRay.sol";
import {mintSCDP, burnSCDP} from "common/funcs/Actions.sol";
import {Asset} from "common/Types.sol";

import {id, err} from "common/Errors.sol";
import {scdp, SCDPState} from "scdp/State.sol";
import {SCDPAssetData} from "scdp/Types.sol";

library Swaps {
    using WadRay for uint256;
    using WadRay for uint128;
    using SafeTransfer for IERC20;

    /**
     * @notice Records the assets received from account in a swap.
     * Burning any existing shared debt or increasing collateral deposits.
     * @param addrIn The asset received.
     * @param assetIn The asset in struct.
     * @param amtIn The amount of the asset received.
     * @param burnFrom The account that holds the assets to burn.
     * @return The value of the assets received into the protocol, used to calculate assets out.
     */
    function handleAssetsIn(
        SCDPState storage self,
        address addrIn,
        Asset storage assetIn,
        uint256 amtIn,
        address burnFrom
    ) internal returns (uint256) {
        SCDPAssetData storage assetData = self.assetData[addrIn];
        uint256 debt = assetIn.toDynamic(assetData.debt);

        uint256 collateralIn; // assets used increase "swap" owned collateral
        uint256 debtOut; // assets used to burn debt

        if (debt < amtIn) {
            // == Debt is less than the amount received.
            // 1. Burn full debt.
            debtOut = debt;
            // 2. Increase collateral by remainder.
            unchecked {
                collateralIn = amtIn - debt;
            }
        } else {
            // == Debt is greater than the amount.
            // 1. Burn full amount received.
            debtOut = amtIn;
            // 2. No increase in collateral.
        }

        if (collateralIn > 0) {
            uint128 collateralInNormalized = uint128(assetIn.toStatic(collateralIn));
            unchecked {
                // 1. Increase collateral deposits.
                assetData.totalDeposits += collateralInNormalized;
                // 2. Increase "swap" collateral.
                assetData.swapDeposits += collateralInNormalized;
            }
        }

        if (debtOut > 0) {
            unchecked {
                // 1. Burn debt that was repaid from the assets received.
                assetData.debt -= burnSCDP(assetIn, debtOut, burnFrom);
            }
        }

        assert(amtIn == debtOut + collateralIn);
        return assetIn.toDebtValue(amtIn, true); // ignore dFactor here
    }

    /**
     * @notice Records the assets to send out in a swap.
     * Increasing debt of the pool by minting new assets when required.
     * @param _assetOutAddr The asset to send out.
     * @param _assetOut The asset out struct.
     * @param _valueIn The value received in.
     * @param _assetsTo The asset receiver.
     * @return amountOut The amount of the asset out.
     */
    function handleAssetsOut(
        SCDPState storage self,
        address _assetOutAddr,
        Asset storage _assetOut,
        uint256 _valueIn,
        address _assetsTo
    ) internal returns (uint256 amountOut) {
        SCDPAssetData storage assetData = self.assetData[_assetOutAddr];
        uint128 swapDeposits = uint128(_assetOut.toDynamic(assetData.swapDeposits)); // current "swap" collateral

        // Calculate amount to send out from value received in.
        amountOut = _assetOut.toDebtAmount(_valueIn, true);

        uint256 collateralOut; // decrease in "swap" collateral
        uint256 debtIn; // new debt required to mint

        if (swapDeposits < amountOut) {
            // == "Swap" owned collateral is less than requested amount.
            // 1. Issue debt for remainder.
            unchecked {
                debtIn = amountOut - swapDeposits;
            }
            // 2. Reduce "swap" owned collateral to zero.
            collateralOut = swapDeposits;
        } else {
            // == "Swap" owned collateral exceeds requested amount
            // 1. No debt issued.
            // 2. Decrease collateral by full amount.
            collateralOut = amountOut;
        }

        if (collateralOut > 0) {
            uint128 collateralOutNormalized = uint128(_assetOut.toStatic(collateralOut));
            unchecked {
                // 1. Decrease collateral deposits.
                assetData.totalDeposits -= collateralOutNormalized;
                // 2. Decrease "swap" owned collateral.
                assetData.swapDeposits -= collateralOutNormalized;
            }
            if (_assetsTo != address(this)) {
                // 3. Transfer collateral to receiver if it is not this contract.
                IERC20(_assetOutAddr).safeTransfer(_assetsTo, collateralOut);
            }
        }

        if (debtIn > 0) {
            // 1. Issue required debt to the pool, minting new assets to receiver.
            unchecked {
                assetData.debt += mintSCDP(_assetOut, debtIn, _assetsTo);
                uint256 newTotalDebt = _assetOut.toDynamic(assetData.debt);
                if (newTotalDebt > _assetOut.mintLimitSCDP) {
                    revert err.EXCEEDS_ASSET_MINTING_LIMIT(id(_assetOutAddr), newTotalDebt, _assetOut.mintLimitSCDP);
                }
            }
        }

        assert(amountOut == debtIn + collateralOut);
    }

    /**
     * @notice Accumulates fees to deposits as a fixed, instantaneous income.
     * @param _assetAddr The asset address
     * @param _asset The asset struct
     * @param _amount The amount to accumulate
     * @return nextLiquidityIndex The next liquidity index of the reserve
     */
    function cumulateIncome(
        SCDPState storage self,
        address _assetAddr,
        Asset storage _asset,
        uint256 _amount
    ) internal returns (uint256 nextLiquidityIndex) {
        if (_amount == 0) {
            revert err.INCOME_AMOUNT_IS_ZERO(id(_assetAddr));
        }

        uint256 userDeposits = self.userDepositAmount(_assetAddr, _asset);
        if (userDeposits == 0) {
            revert err.NO_LIQUIDITY_TO_GIVE_INCOME_FOR(
                id(_assetAddr),
                userDeposits,
                self.totalDepositAmount(_assetAddr, _asset)
            );
        }

        // liquidity index increment is calculated this way: `(amount / totalLiquidity)`
        // division `amount / totalLiquidity` done in ray for precision
        unchecked {
            return (scdp().assetIndexes[_assetAddr].currFeeIndex += uint128(
                (_amount.wadToRay().rayDiv(userDeposits.wadToRay()))
            ));
        }
    }
}
