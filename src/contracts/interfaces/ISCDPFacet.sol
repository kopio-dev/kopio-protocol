// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {SCDPRepayArgs, SCDPWithdrawArgs} from "common/Args.sol";

interface ISCDPFacet {
    /**
     * @notice Deposits global collateral for the account
     * @param account account to deposit for
     * @param collateral collateral to deposit
     * @param amount amount to deposit
     */
    function depositSCDP(address account, address collateral, uint256 amount) external payable;

    /**
     * @notice Withdraws global collateral.
     * @param args asset and amount to withdraw.
     */
    function withdrawSCDP(SCDPWithdrawArgs memory args, bytes[] calldata prices) external payable;

    /**
     * @notice Withdraw collateral without caring about fees.
     * @param args asset and amount to withdraw.
     */
    function emergencyWithdrawSCDP(SCDPWithdrawArgs memory args, bytes[] calldata prices) external payable;

    /**
     * @notice Claim pending fees.
     * @param account account to claim fees for.
     * @param collateral collateral with accumulated fees.
     * @param receiver reciver of the fees, 0 -> account.
     * @return fees amount claimed
     */
    function claimFeesSCDP(address account, address collateral, address receiver) external payable returns (uint256 fees);

    /**
     * @notice Repays debt and withdraws protocol collateral with no fees.
     * @notice self deposits from the protocol must exists, otherwise reverts.
     * @param args the selected assets, amounts and prices.
     */
    function repaySCDP(SCDPRepayArgs calldata args) external payable;
}
