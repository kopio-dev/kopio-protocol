// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {IERC20} from "kopio/token/IERC20.sol";
import {SafeTransfer} from "kopio/token/SafeTransfer.sol";
import {Role, Enums} from "common/Constants.sol";
import {Modifiers} from "common/Modifiers.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";

import {IICDPCollateralFacet} from "interfaces/IICDPCollateralFacet.sol";
import {IFlashWithdrawReceiver} from "interfaces/IFlashWithdrawReceiver.sol";
import {ms} from "icdp/State.sol";
import {FlashWithdrawArgs, WithdrawArgs} from "common/Args.sol";
import {MEvent} from "icdp/Event.sol";

/**
 * @author the kopio project
 * @title ICDPCollateralFacet
 * @notice handles deposits and withdrawals of collateral
 */
contract ICDPCollateralFacet is Modifiers, IICDPCollateralFacet, MEvent {
    using SafeTransfer for IERC20;

    /// @inheritdoc IICDPCollateralFacet
    function depositCollateral(address account, address collateral, uint256 amount) external payable nonReentrant {
        Asset storage cfg = cs().onlyCollateral(collateral, Enums.Action.Deposit);
        // pull tokens
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
        // record the deposit
        ms().handleDeposit(cfg, account, collateral, amount);
    }

    /// @inheritdoc IICDPCollateralFacet
    function withdrawCollateral(
        WithdrawArgs memory args,
        bytes[] calldata prices
    ) external payable nonReentrant onlyRoleIf(args.account != msg.sender, Role.MANAGER) usePyth(prices) {
        Asset storage cfg = cs().onlyCollateral(args.asset, Enums.Action.Withdraw);
        uint256 deposits = ms().accountCollateralAmount(args.account, args.asset, cfg);

        // send all deposits on overflow
        args.amount = (args.amount > deposits ? deposits : args.amount);

        // record, verify and withdraw
        ms().handleWithdrawal(cfg, args.account, args.asset, args.amount, deposits);

        ms().checkAccountCollateral(args.account);

        emit CollateralWithdrawn(args.account, args.asset, args.amount);

        IERC20(args.asset).safeTransfer(args.receiver == address(0) ? args.account : args.receiver, args.amount);
    }

    /// @inheritdoc IICDPCollateralFacet
    function flashWithdrawCollateral(
        FlashWithdrawArgs memory args,
        bytes[] calldata prices
    ) external payable onlyRoleIf(args.account != msg.sender, Role.MANAGER) usePyth(prices) {
        Asset storage cfg = cs().onlyCollateral(args.asset, Enums.Action.Withdraw);
        uint256 deposits = ms().accountCollateralAmount(args.account, args.asset, cfg);

        // send all deposits on overflow
        args.amount = (args.amount > deposits ? deposits : args.amount);

        // withdraw the collateral
        ms().handleWithdrawal(cfg, args.account, args.asset, args.amount, deposits);

        // transfer, call and verify
        IERC20(args.asset).safeTransfer(msg.sender, args.amount);

        emit CollateralFlashWithdrawn(args.account, args.asset, args.amount);

        IFlashWithdrawReceiver(msg.sender).onFlashWithdraw(args.account, args.asset, args.amount, args.data);

        ms().checkAccountCollateral(args.account);
    }
}
