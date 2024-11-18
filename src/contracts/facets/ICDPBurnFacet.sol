// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Arrays} from "libs/Arrays.sol";
import {Role, Enums} from "common/Constants.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";
import {Modifiers} from "common/Modifiers.sol";
import {id, err} from "common/Errors.sol";
import {BurnArgs} from "common/Args.sol";

import {IICDPBurnFacet} from "interfaces/IICDPBurnFacet.sol";
import {ms, ICDPState} from "icdp/State.sol";
import {MEvent} from "icdp/Event.sol";
import {handleFee} from "icdp/funcs/Fees.sol";

/**
 * @author the kopio project
 * @title ICDPBurnFacet
 * @notice repays debt in the ICDP.
 */
contract ICDPBurnFacet is Modifiers, IICDPBurnFacet {
    using Arrays for address[];

    /// @inheritdoc IICDPBurnFacet
    function burnKopio(
        BurnArgs memory args,
        bytes[] calldata prices
    )
        external
        payable
        nonReentrant
        onlyRoleIf(args.account != msg.sender || args.repayee != msg.sender, Role.MANAGER)
        usePyth(prices)
    {
        Asset storage asset = cs().onlyKopio(args.kopio, Enums.Action.Repay);
        ICDPState storage s = ms();

        // Get accounts principal debt
        uint256 debtAmount = s.accountDebtAmount(args.account, args.kopio, asset);
        if (debtAmount == 0) revert err.ZERO_DEBT(id(args.kopio));

        // Ensure principal left is either 0 or >= minDebtValue
        if (args.amount < debtAmount) {
            args.amount = asset.checkDust(args.amount, debtAmount);
        } else if (args.amount > debtAmount) {
            args.amount = debtAmount;
        }

        // Charge the burn fee from collateral of args.account
        handleFee(asset, args.account, args.amount, Enums.ICDPFee.Close);

        s.burn(asset, args.kopio, args.account, args.amount, args.repayee);

        emit MEvent.KopioBurned(args.account, args.kopio, args.amount);
    }
}
