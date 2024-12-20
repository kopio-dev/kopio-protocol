// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {WadRay} from "vendor/WadRay.sol";
import {SCDPState} from "scdp/State.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";
import {SCDPAccountIndexes, SCDPAssetIndexes, SCDPSeizeData} from "scdp/Types.sol";

library SAccounts {
    using WadRay for uint256;

    /**
     * @notice Get accounts principal deposits.
     * @notice Uses scaled deposits if its lower than principal (realizing liquidations).
     * @param _account The account to get the amount for
     * @param _assetAddr The deposit asset address
     * @param _asset The deposit asset struct
     * @return principalDeposits The principal deposit amount for the account.
     */
    function accountDeposits(
        SCDPState storage self,
        address _account,
        address _assetAddr,
        Asset storage _asset
    ) internal view returns (uint256 principalDeposits) {
        return self.divByLiqIndex(_assetAddr, _asset.toDynamic(self.depositsPrincipal[_account][_assetAddr]));
    }

    /**
     * @notice Returns the value of the deposits for `_account`.
     * @param _account Account to get total deposit value for
     * @param _ignoreFactors Whether to ignore cFactor and dFactor
     */
    function accountDepositsValue(
        SCDPState storage self,
        address _account,
        bool _ignoreFactors
    ) internal view returns (uint256 totalValue) {
        address[] memory assets = self.collaterals;
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = cs().assets[assets[i]];
            uint256 depositAmount = self.accountDeposits(_account, assets[i], asset);
            unchecked {
                if (depositAmount != 0) {
                    totalValue += asset.toCollateralValue(depositAmount, _ignoreFactors);
                }
                i++;
            }
        }
    }

    /**
     * @notice Get accounts total fees gained for this asset.
     * @notice To get this value it compares deposit time liquidity index with current.
     * @notice If the account has endured liquidation events, separate logic is used to combine fees according to historical balance.
     * @param _account The account to get the amount for
     * @param _assetAddr The asset address
     * @param _asset The asset struct
     * @return feeAmount Amount of fees accrued.
     */
    function accountFees(
        SCDPState storage self,
        address _account,
        address _assetAddr,
        Asset storage _asset
    ) internal view returns (uint256 feeAmount) {
        SCDPAssetIndexes memory assetIndexes = self.assetIndexes[_assetAddr];
        SCDPAccountIndexes memory accountIndexes = self.accountIndexes[_account][_assetAddr];
        // Return early if there are no fees accrued.
        if (accountIndexes.lastFeeIndex == 0 || accountIndexes.lastFeeIndex == assetIndexes.currFeeIndex) return 0;

        // Get the principal deposits for the account.
        uint256 principalDeposits = _asset.toDynamic(self.depositsPrincipal[_account][_assetAddr]).wadToRay();

        // If accounts last liquidation index is lower than current, it means they endured a liquidation.
        SCDPSeizeData memory latestSeize = self.seizeEvents[_assetAddr][assetIndexes.currLiqIndex];

        if (accountIndexes.lastLiqIndex < latestSeize.liqIndex) {
            // Accumulated fees before now and after latest seize.
            uint256 feesAfterLastSeize = principalDeposits.rayMul(assetIndexes.currFeeIndex - latestSeize.feeIndex).rayDiv(
                latestSeize.liqIndex
            );

            uint256 feesBeforeLastSeize;
            // Just loop through all events until we hit the same index as the account.
            while (accountIndexes.lastLiqIndex < latestSeize.liqIndex && accountIndexes.lastFeeIndex < latestSeize.feeIndex) {
                SCDPSeizeData memory previousSeize = self.seizeEvents[_assetAddr][latestSeize.prevLiqIndex];

                if (previousSeize.liqIndex == 0) break;
                if (previousSeize.feeIndex < accountIndexes.lastFeeIndex) {
                    previousSeize.feeIndex = accountIndexes.lastFeeIndex;
                }
                uint256 feePct = latestSeize.feeIndex - previousSeize.feeIndex;
                if (feePct > 0) {
                    // Get the historical balance according to liquidation index at the time
                    // Then we simply multiply by fee index difference to get the fees accrued.
                    feesBeforeLastSeize += principalDeposits.rayMul(feePct).rayDiv(latestSeize.prevLiqIndex);
                }
                // Iterate backwards in time.
                latestSeize = previousSeize;
            }

            return (feesBeforeLastSeize + feesAfterLastSeize).rayToWad();
        }

        // If we are here, it means the account has not endured a liquidation.
        // We can simply calculate the fees by multiplying the difference in fee indexes with the principal deposits.
        return
            principalDeposits
                .rayMul(assetIndexes.currFeeIndex - accountIndexes.lastFeeIndex)
                .rayDiv(assetIndexes.currLiqIndex)
                .rayToWad();
    }

    /**
     * @notice Returns the total fees value for `_account`.
     * @notice Ignores all factors.
     * @param _account Account to get fees for
     * @return totalValue Total fees value for `_account`
     */
    function accountTotalFeeValue(SCDPState storage self, address _account) internal view returns (uint256 totalValue) {
        address[] memory assets = self.collaterals;
        for (uint256 i; i < assets.length; ) {
            Asset storage asset = cs().assets[assets[i]];
            uint256 fees = self.accountFees(_account, assets[i], asset);
            unchecked {
                if (fees != 0) totalValue += asset.toCollateralValue(fees, true);
                i++;
            }
        }
    }
}
