// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Arrays} from "libs/Arrays.sol";
import {WadRay} from "vendor/WadRay.sol";

import {id, err} from "common/Errors.sol";
import {Asset} from "common/Types.sol";
import {burnAssets, mintAssets} from "common/funcs/Actions.sol";

import {MEvent} from "icdp/Event.sol";
import {ICDPState} from "icdp/State.sol";

library MCore {
    using Arrays for address[];
    using WadRay for uint256;

    function mint(ICDPState storage s, Asset storage a, address asset, address account, uint256 amount, address to) internal {
        unchecked {
            a.ensureMintLimitICDP(asset, amount);
            // Mint and record it.
            uint256 minted = mintAssets(amount, to == address(0) ? account : to, a.share);
            uint256 debt = (s.debt[account][asset] += minted);
            // The synthetic asset debt position must be greater than the minimum debt position value
            a.ensureMinDebtValue(asset, debt);

            // If this is the first time the account mints this asset, add to its minted assets
            if (debt == minted) s.mints[account].pushUnique(asset);
        }
    }

    function burn(ICDPState storage s, Asset storage a, address asset, address account, uint256 amount, address from) internal {
        if ((s.debt[account][asset] -= burnAssets(amount, from, a.share)) == 0) {
            s.mints[account].removeAddress(asset);
        }
    }

    /**
     * @notice Records a collateral deposit.
     * @param cfg asset configuration
     * @param acc account receiving the deposit.
     * @param collateral address of the asset.
     * @param amount amount to deposit
     */
    function handleDeposit(
        ICDPState storage self,
        Asset storage cfg,
        address acc,
        address collateral,
        uint256 amount
    ) internal {
        if (amount == 0) revert err.ZERO_DEPOSIT(id(collateral));

        unchecked {
            uint256 stored = cfg.toStatic(amount);
            uint256 deposits = (self.deposits[acc][collateral] += stored);

            // ensure new amount is not < 1e12
            cfg.ensureMinCollateralAmount(collateral, deposits);
            if (deposits == stored) self.collateralsOf[acc].pushUnique(collateral);
        }

        emit MEvent.CollateralDeposited(acc, collateral, amount);
    }

    /**
     * @notice Verifies that account has enough collateral for the withdrawal and then records it
     * @param cfg asset configuration
     * @param acc the account withdrawing.
     * @param collateral asset withdrawn
     * @param amount amount to withdraw
     * @param deposits existing deposits of the account
     */
    function handleWithdrawal(
        ICDPState storage self,
        Asset storage cfg,
        address acc,
        address collateral,
        uint256 amount,
        uint256 deposits
    ) internal {
        if (amount == 0) revert err.ZERO_WITHDRAW(id(collateral));
        uint256 newAmount = deposits - amount;

        // If no deposits remain, remove from the deposited collaterals
        if (newAmount == 0) self.collateralsOf[acc].removeAddress(collateral);
        else {
            // ensure new amount is not < 1e12
            cfg.ensureMinCollateralAmount(collateral, newAmount);
        }

        // Record the withdrawal.
        self.deposits[acc][collateral] = cfg.toStatic(newAmount);
    }
}
