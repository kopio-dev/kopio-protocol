// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {FlashWithdrawArgs, WithdrawArgs} from "common/Args.sol";

interface IICDPCollateralFacet {
    /**
     * @notice Deposits collateral to the protocol.
     * @param account account to deposit for
     * @param collateral the collateral asset.
     * @param amount amount to deposit.
     */
    function depositCollateral(address account, address collateral, uint256 amount) external payable;

    /**
     * @notice Withdraw collateral from the protocol.
     * @dev reverts if the resulting collateral value is below MCR.
     * @param args the withdraw arguments
     * @param prices price data
     */
    function withdrawCollateral(WithdrawArgs memory args, bytes[] calldata prices) external payable;

    /**
     * @notice Allows withdrawing full collateral if MCR is maintained by end of the call.
     * @dev calls onFlashWithdraw on the sender
     * @param args the flash withdraw arguments
     * @param prices price data
     */
    function flashWithdrawCollateral(FlashWithdrawArgs memory args, bytes[] calldata prices) external payable;
}
