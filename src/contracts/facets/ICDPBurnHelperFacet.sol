// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Arrays} from "libs/Arrays.sol";
import {Role, Enums} from "common/Constants.sol";
import {id, err} from "common/Errors.sol";
import {Modifiers} from "common/Modifiers.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";

import {DSModifiers} from "diamond/DSModifiers.sol";
import {MEvent} from "icdp/Event.sol";
import {ms, ICDPState} from "icdp/State.sol";
import {handleFee} from "icdp/funcs/Fees.sol";
import {IICDPBurnHelperFacet} from "interfaces/IICDPBurnHelperFacet.sol";

/**
 * @author the kopio project
 * @title BurnHelperFacet
 * @notice Helper functions for reducing positions in the ICDP.
 */
contract ICDPBurnHelperFacet is IICDPBurnHelperFacet, DSModifiers, Modifiers {
    using Arrays for address[];

    /// @inheritdoc IICDPBurnHelperFacet
    function closeDebtPosition(
        address account,
        address kopio,
        bytes[] calldata prices
    ) public payable nonReentrant onlyRoleIf(account != msg.sender, Role.MANAGER) usePyth(prices) {
        _close(account, kopio);
    }

    /// @inheritdoc IICDPBurnHelperFacet
    function closeAllDebtPositions(
        address account,
        bytes[] calldata prices
    ) external payable onlyRoleIf(account != msg.sender, Role.MANAGER) usePyth(prices) {
        address[] memory minted = ms().accountDebtAssets(account);
        for (uint256 i; i < minted.length; ) {
            _close(account, minted[i]);
            unchecked {
                i++;
            }
        }
    }

    function _close(address account, address kopio) internal {
        Asset storage cfg = cs().onlyKopio(kopio, Enums.Action.Repay);

        ICDPState storage s = ms();
        // Get accounts principal debt
        uint256 principalDebt = s.accountDebtAmount(account, kopio, cfg);
        if (principalDebt == 0) revert err.ZERO_DEBT(id(kopio));

        // Charge the burn fee from collateral of account
        handleFee(cfg, account, principalDebt, Enums.ICDPFee.Close);

        // Record the burn
        s.burn(cfg, kopio, account, principalDebt, msg.sender);

        emit MEvent.DebtPositionClosed(account, kopio, principalDebt);
    }
}
