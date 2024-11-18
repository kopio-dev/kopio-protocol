// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {SafeTransfer} from "kopio/token/SafeTransfer.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {WadRay} from "vendor/WadRay.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";

import {id, err} from "common/Errors.sol";
import {burnSCDP} from "common/funcs/Actions.sol";
import {fromWad} from "common/funcs/Math.sol";
import {Modifiers, Enums} from "common/Modifiers.sol";
import {cs} from "common/State.sol";
import {Asset} from "common/Types.sol";

import {SEvent} from "scdp/Event.sol";
import {SCDPAssetData} from "scdp/Types.sol";
import {ISCDPFacet} from "interfaces/ISCDPFacet.sol";
import {scdp, SCDPState} from "scdp/State.sol";
import {Role} from "common/Constants.sol";
import {SCDPRepayArgs, SCDPWithdrawArgs} from "common/Args.sol";
import {handlePythUpdate} from "common/funcs/Utils.sol";

using PercentageMath for uint256;
using PercentageMath for uint16;
using SafeTransfer for IERC20;
using WadRay for uint256;

// solhint-disable avoid-tx-origin

contract SCDPFacet is ISCDPFacet, Modifiers {
    /// @inheritdoc ISCDPFacet
    function depositSCDP(address account, address collateral, uint256 amount) external payable nonReentrant {
        // Transfer tokens into this contract prior to any state changes as an extra measure against re-entrancy.
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);

        emit SEvent.SCDPDeposit(
            account,
            collateral,
            amount,
            scdp().handleDepositSCDP(cs().onlyCumulated(collateral, Enums.Action.SCDPDeposit), account, collateral, amount),
            block.timestamp
        );
    }

    /// @inheritdoc ISCDPFacet
    function withdrawSCDP(
        SCDPWithdrawArgs memory args,
        bytes[] calldata prices
    ) external payable onlyRoleIf(args.account != msg.sender, Role.MANAGER) nonReentrant usePyth(prices) {
        SCDPState storage s = scdp();
        args.receiver = args.receiver == address(0) ? args.account : args.receiver;

        // When principal deposits are less or equal to requested amount. We send full deposit + fees in this case.
        uint256 feeIndex = s.handleWithdrawSCDP(
            cs().onlyGlobalDeposited(args.collateral, Enums.Action.SCDPWithdraw),
            args.account,
            args.collateral,
            args.amount,
            args.receiver,
            false
        );

        // ensure that global pool is left with CR over MCR.
        s.ensureCollateralRatio(s.minCollateralRatio);

        // Send out the collateral.
        IERC20(args.collateral).safeTransfer(args.receiver, args.amount);

        // Emit event.
        emit SEvent.SCDPWithdraw(
            args.account,
            args.receiver,
            args.collateral,
            msg.sender,
            args.amount,
            feeIndex,
            block.timestamp
        );
    }

    /// @inheritdoc ISCDPFacet
    function emergencyWithdrawSCDP(
        SCDPWithdrawArgs memory args,
        bytes[] calldata prices
    ) external payable onlyRoleIf(args.account != msg.sender, Role.MANAGER) nonReentrant usePyth(prices) {
        SCDPState storage s = scdp();
        args.receiver = args.receiver == address(0) ? args.account : args.receiver;

        // When principal deposits are less or equal to requested amount. We send full deposit + fees in this case.
        uint256 feeIndex = s.handleWithdrawSCDP(
            cs().onlyGlobalDeposited(args.collateral, Enums.Action.SCDPWithdraw),
            args.account,
            args.collateral,
            args.amount,
            args.receiver,
            true
        );

        // ensure that global pool is left with CR over MCR.
        s.ensureCollateralRatio(s.minCollateralRatio);

        // Send out the collateral.
        IERC20(args.collateral).safeTransfer(args.receiver, args.amount);

        // Emit event.
        emit SEvent.SCDPWithdraw(
            args.account,
            args.receiver,
            args.collateral,
            msg.sender,
            args.amount,
            feeIndex,
            block.timestamp
        );
    }

    /// @inheritdoc ISCDPFacet
    function claimFeesSCDP(
        address account,
        address collateral,
        address _receiver
    ) external payable onlyRoleIf(account != msg.sender, Role.MANAGER) returns (uint256 feeAmount) {
        feeAmount = scdp().handleFeeClaim(
            cs().onlyCumulated(collateral, Enums.Action.SCDPFeeClaim),
            account,
            collateral,
            _receiver == address(0) ? account : _receiver,
            false
        );
        if (feeAmount == 0) revert err.NO_FEES_TO_CLAIM(id(collateral), account);
    }

    /// @inheritdoc ISCDPFacet
    function repaySCDP(SCDPRepayArgs calldata args) external payable nonReentrant {
        handlePythUpdate(args.prices);
        Asset storage repayAsset = cs().onlySwapMintable(args.kopio, Enums.Action.SCDPRepay);
        Asset storage seizeAsset = cs().onlySwapMintable(args.collateral, Enums.Action.SCDPRepay);

        SCDPAssetData storage repayData = scdp().assetData[args.kopio];
        SCDPAssetData storage seizeData = scdp().assetData[args.collateral];

        if (args.amount > repayAsset.toDynamic(repayData.debt)) {
            revert err.REPAY_OVERFLOW(id(args.kopio), id(args.collateral), args.amount, repayAsset.toDynamic(repayData.debt));
        }

        uint256 seizedAmount = fromWad(repayAsset.kopioUSD(args.amount).wadDiv(seizeAsset.price()), seizeAsset.decimals);

        if (seizedAmount == 0) {
            revert err.ZERO_REPAY(id(args.kopio), args.amount, seizedAmount);
        }

        uint256 swapDeposits = seizeAsset.toDynamic(seizeData.swapDeposits);
        if (seizedAmount > swapDeposits) {
            revert err.NOT_ENOUGH_SWAP_DEPOSITS_TO_SEIZE(id(args.kopio), id(args.collateral), seizedAmount, swapDeposits);
        }

        repayData.debt -= burnSCDP(repayAsset, args.amount, msg.sender);

        uint128 seizedAmountInternal = uint128(seizeAsset.toStatic(seizedAmount));
        seizeData.swapDeposits -= seizedAmountInternal;
        seizeData.totalDeposits -= seizedAmountInternal;

        IERC20(args.collateral).safeTransfer(msg.sender, seizedAmount);
        // solhint-disable-next-line avoid-tx-origin
        emit SEvent.SCDPRepay(tx.origin, args.kopio, args.amount, args.collateral, seizedAmount, block.timestamp);
    }
}
