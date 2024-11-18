// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {id, err} from "common/Errors.sol";
import {Role, Enums} from "common/Constants.sol";
import {Modifiers} from "common/Modifiers.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";
import {Strings} from "vendor/Strings.sol";

import {IICDPMintFacet} from "interfaces/IICDPMintFacet.sol";

import {MEvent} from "icdp/Event.sol";
import {ms, ICDPState} from "icdp/State.sol";
import {handleFee} from "icdp/funcs/Fees.sol";
import {Arrays} from "libs/Arrays.sol";
import {MintArgs} from "common/Args.sol";

/**
 * @title ICDPMintFacet
 * @author the kopio project
 */
contract ICDPMintFacet is IICDPMintFacet, Modifiers {
    using Strings for bytes32;
    using Arrays for address[];

    /// @inheritdoc IICDPMintFacet
    function mintKopio(
        MintArgs memory args,
        bytes[] calldata prices
    ) external payable onlyRoleIf(args.account != msg.sender, Role.MANAGER) nonReentrant usePyth(prices) {
        Asset storage asset = cs().onlyKopio(args.kopio, Enums.Action.Borrow);
        if (!asset.isMarketOpen()) revert err.MARKET_CLOSED(id(args.kopio), asset.ticker.toString());

        ICDPState storage s = ms();

        if (asset.openFee != 0) handleFee(asset, args.account, args.amount, Enums.ICDPFee.Open);

        s.mint(asset, args.kopio, args.account, args.amount, args.receiver);

        // Check if the account has sufficient collateral to back the new debt
        s.checkAccountCollateral(args.account);

        // Emit logs
        emit MEvent.KopioMinted(args.account, args.kopio, args.amount, args.receiver);
    }
}
