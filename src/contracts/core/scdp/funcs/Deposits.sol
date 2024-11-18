// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {WadRay} from "vendor/WadRay.sol";
import {Asset} from "common/Types.sol";
import {id, err} from "common/Errors.sol";
import {SCDPState} from "scdp/State.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {SCDPSeizeData} from "scdp/Types.sol";
import {SEvent} from "scdp/Event.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";

library SDeposits {
    using WadRay for uint256;
    using WadRay for uint128;
    using SafeTransfer for IERC20;

    /**
     * @notice Records a deposit of collateral asset.
     * @notice It will withdraw any pending fees first.
     * @notice Saves global deposit amount and principal for user.
     * @param cfg Asset struct for the deposit asset
     * @param account depositor
     * @param assetAddr the deposit asset
     * @param amount amount of collateral asset to deposit
     */
    function handleDepositSCDP(
        SCDPState storage self,
        Asset storage cfg,
        address account,
        address assetAddr,
        uint256 amount
    ) internal returns (uint256 feeIndex) {
        // Withdraw any fees first.
        uint256 fees = handleFeeClaim(self, cfg, account, assetAddr, account, false);
        // Save account liquidation and fee indexes if they werent saved before.
        if (fees == 0) {
            (, feeIndex) = updateAccountIndexes(self, account, assetAddr);
        }

        unchecked {
            // Save global deposits using normalized amount.
            uint128 normalizedAmount = uint128(cfg.toStatic(amount));
            self.assetData[assetAddr].totalDeposits += normalizedAmount;

            // Save account deposit amount, its scaled up by the liquidation index.
            self.depositsPrincipal[account][assetAddr] += self.mulByLiqIndex(assetAddr, normalizedAmount);

            // Check if the deposit limit is exceeded.
            if (self.userDepositAmount(assetAddr, cfg) > cfg.depositLimitSCDP) {
                revert err.EXCEEDS_ASSET_DEPOSIT_LIMIT(
                    id(assetAddr),
                    self.userDepositAmount(assetAddr, cfg),
                    cfg.depositLimitSCDP
                );
            }
        }
    }

    /**
     * @notice Records a withdrawal of collateral asset from the SCDP.
     * @notice It will withdraw any pending fees first.
     * @notice Saves global deposit amount and principal for user.
     * @param cfg Asset struct for the deposit asset
     * @param account The withdrawing account
     * @param assetAddr the deposit asset
     * @param amount The amount of collateral to withdraw
     * @param receiver The receiver of the withdrawn fees
     * @param noClaim Emergency flag to skip claiming fees
     */
    function handleWithdrawSCDP(
        SCDPState storage self,
        Asset storage cfg,
        address account,
        address assetAddr,
        uint256 amount,
        address receiver,
        bool noClaim
    ) internal returns (uint256 feeIndex) {
        // Handle fee claiming.
        uint256 fees = handleFeeClaim(self, cfg, account, assetAddr, receiver, noClaim);
        // Save account liquidation and fee indexes if they werent updated on fee claim.
        if (fees == 0) {
            (, feeIndex) = updateAccountIndexes(self, account, assetAddr);
        }

        // Get accounts principal deposits.
        uint256 depositsPrincipal = self.accountDeposits(account, assetAddr, cfg);

        // Check that we can perform the withdrawal.
        if (depositsPrincipal == 0) {
            revert err.NO_DEPOSITS(account, id(assetAddr));
        }
        if (depositsPrincipal < amount) {
            revert err.NOT_ENOUGH_DEPOSITS(account, id(assetAddr), amount, depositsPrincipal);
        }

        unchecked {
            // Save global deposits using normalized amount.
            uint128 normalizedAmount = uint128(cfg.toStatic(amount));
            self.assetData[assetAddr].totalDeposits -= normalizedAmount;

            // Save account deposit amount, the amount withdrawn is scaled up by the liquidation index.
            self.depositsPrincipal[account][assetAddr] -= self.mulByLiqIndex(assetAddr, normalizedAmount);
        }
    }

    /**
     * @notice This function seizes collateral from the shared pool.
     * @notice It will reduce all deposits in the case where swap deposits do not cover the amount.
     * @notice Each event touching user deposits will save a checkpoint of the indexes.
     * @param _sAsset asset config
     * @param assetAddr seized asset.
     * @param amount amount seized
     */
    function handleSeizeSCDP(
        SCDPState storage self,
        Asset storage _sAsset,
        address assetAddr,
        uint256 amount
    ) internal returns (uint128 prevLiqIndex, uint128 newLiqIndex) {
        uint128 swapDeposits = self.swapDepositAmount(assetAddr, _sAsset);

        if (swapDeposits >= amount) {
            uint128 amountOut = uint128(_sAsset.toStatic(amount));
            // swap deposits cover the amount
            unchecked {
                self.assetData[assetAddr].swapDeposits -= amountOut;
                self.assetData[assetAddr].totalDeposits -= amountOut;
            }
        } else {
            // swap deposits do not cover the amount
            self.assetData[assetAddr].swapDeposits = 0;
            // total deposits = user deposits at this point
            self.assetData[assetAddr].totalDeposits -= uint128(_sAsset.toStatic(amount));

            // We need this later for seize data as well.
            prevLiqIndex = self.assetIndexes[assetAddr].currLiqIndex;
            newLiqIndex = uint128(
                prevLiqIndex +
                    (amount - swapDeposits).wadToRay().rayMul(prevLiqIndex).rayDiv(
                        _sAsset.toDynamic(self.assetData[assetAddr].totalDeposits.wadToRay())
                    )
            );

            // Increase liquidation index, note this uses rebased amounts instead of normalized.
            self.assetIndexes[assetAddr].currLiqIndex = newLiqIndex;

            // Save the seize data.
            self.seizeEvents[assetAddr][self.assetIndexes[assetAddr].currLiqIndex] = SCDPSeizeData({
                prevLiqIndex: prevLiqIndex,
                feeIndex: self.assetIndexes[assetAddr].currFeeIndex,
                liqIndex: self.assetIndexes[assetAddr].currLiqIndex
            });
        }

        IERC20(assetAddr).safeTransfer(msg.sender, amount);
        return (prevLiqIndex, self.assetIndexes[assetAddr].currLiqIndex);
    }

    /**
     * @notice Fully handles fee claim.
     * @notice Checks whether some fees exists, withdrawis them and updates account indexes.
     * @param cfg The asset struct.
     * @param account The account to withdraw fees for.
     * @param assetAddr The asset address.
     * @param receiver Receiver of fees withdrawn, if 0 then the receiver is the account.
     * @param _skip Emergency flag, skips claiming fees due and logs a receipt for off-chain processing
     * @return feeAmount Amount of fees withdrawn.
     * @dev This function is used by deposit and withdraw functions.
     */
    function handleFeeClaim(
        SCDPState storage self,
        Asset storage cfg,
        address account,
        address assetAddr,
        address receiver,
        bool _skip
    ) internal returns (uint256 feeAmount) {
        if (_skip) {
            _logFeeReceipt(self, account, assetAddr);
            return 0;
        }
        uint256 fees = self.accountFees(account, assetAddr, cfg);
        if (fees > 0) {
            (uint256 prevIndex, uint256 newIndex) = updateAccountIndexes(self, account, assetAddr);
            IERC20(assetAddr).transfer(receiver, fees);
            emit SEvent.SCDPFeeClaim(account, receiver, assetAddr, fees, newIndex, prevIndex, block.timestamp);
        }

        return fees;
    }

    function _logFeeReceipt(SCDPState storage self, address account, address assetAddr) private {
        emit SEvent.SCDPFeeReceipt(
            account,
            assetAddr,
            self.depositsPrincipal[account][assetAddr],
            self.assetIndexes[assetAddr].currFeeIndex,
            self.accountIndexes[account][assetAddr].lastFeeIndex,
            self.assetIndexes[assetAddr].currLiqIndex,
            self.accountIndexes[account][assetAddr].lastLiqIndex,
            block.number,
            block.timestamp
        );
    }

    /**
     * @notice Updates account indexes to checkpoint the fee index and liquidation index at the time of action.
     * @param account The account to update indexes for.
     * @param assetAddr The asset being withdrawn/deposited.
     * @dev This function is used by deposit and withdraw functions.
     */
    function updateAccountIndexes(
        SCDPState storage self,
        address account,
        address assetAddr
    ) private returns (uint128 prevIndex, uint128 newIndex) {
        prevIndex = self.accountIndexes[account][assetAddr].lastFeeIndex;
        newIndex = self.assetIndexes[assetAddr].currFeeIndex;
        self.accountIndexes[account][assetAddr].lastFeeIndex = self.assetIndexes[assetAddr].currFeeIndex;
        self.accountIndexes[account][assetAddr].lastLiqIndex = self.assetIndexes[assetAddr].currLiqIndex;
        self.accountIndexes[account][assetAddr].timestamp = block.timestamp;
    }

    function mulByLiqIndex(SCDPState storage self, address assetAddr, uint256 amount) internal view returns (uint128) {
        return uint128(amount.wadToRay().rayMul(self.assetIndexes[assetAddr].currLiqIndex).rayToWad());
    }

    function divByLiqIndex(SCDPState storage self, address assetAddr, uint256 _depositAmount) internal view returns (uint128) {
        return uint128(_depositAmount.wadToRay().rayDiv(self.assetIndexes[assetAddr].currLiqIndex).rayToWad());
    }
}
