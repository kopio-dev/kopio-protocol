// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {VaultFlashTestBase} from "test/helpers/VaultTestBase.t.sol";
import {PLog} from "kopio/vm/PLog.s.sol";
import {Utils} from "kopio/utils/Libs.sol";

contract TestONE is VaultFlashTestBase {
    using PLog for *;
    using Utils for *;

    function setUp() public override {
        super.setUp();
        _flashApprovals(user4, type(uint256).max);

        usdc.approve(oneAddr, type(uint256).max);
        vm.prank(user1);
        usdc.approve(oneAddr, type(uint256).max);
    }

    function _ensureSupply(uint256 amount) internal view {
        assertEq(vone.totalSupply(), amount, "vault-supply");
        assertEq(vone.balanceOf(oneAddr), amount, "vault-one-balance");
        assertEq(one.totalSupply(), amount, "one-supply");
    }

    function testOneDeposit() public {
        usdc.mint(self, 1e18);
        one.vaultDeposit(address(usdc), 1e18, self);

        assertEq(usdc.balanceOf(self), 0);
        assertEq(one.balanceOf(self), 1e18);
        assertEq(usdc.balanceOf(vaultAddr), 1e18);
        assertEq(usdc.balanceOf(oneAddr), 0);

        _ensureSupply(1e18);
    }
    function testOneDepositTo() public {
        usdc.mint(user1, 1e18);
        one.vaultDeposit(address(usdc), 1e18, user1);

        assertEq(usdc.balanceOf(self), 0);
        assertEq(one.balanceOf(self), 0);
        assertEq(one.balanceOf(user1), 1e18);
        assertEq(usdc.balanceOf(vaultAddr), 1e18);
        assertEq(usdc.balanceOf(oneAddr), 0);

        _ensureSupply(1e18);
    }

    function testOneMint() public useFees(usdc, 25e2, 25e2) {
        (uint256 mintAmount, ) = vone.previewDeposit(address(usdc), 1e18);

        usdc.mint(self, 1e18);
        one.vaultMint(address(usdc), mintAmount, self);

        assertEq(one.balanceOf(self), mintAmount);
        assertEq(usdc.balanceOf(vaultAddr), 1e18);

        assertEq(usdc.balanceOf(self), 0);
        assertEq(usdc.balanceOf(oneAddr), 0);

        _ensureSupply(mintAmount);
    }
    function testOneMintTo() public useFees(usdc, 25e2, 25e2) {
        (uint256 mintAmount, ) = vone.previewDeposit(address(usdc), 1e18);

        usdc.mint(user1, 1e18);
        one.vaultMint(address(usdc), mintAmount, user1);

        assertEq(one.balanceOf(self), 0);
        assertEq(one.balanceOf(user1), mintAmount);
        assertEq(usdc.balanceOf(vaultAddr), 1e18);

        assertEq(usdc.balanceOf(self), 0);
        assertEq(usdc.balanceOf(oneAddr), 0);

        _ensureSupply(mintAmount);
    }

    function testOneMintReverts() public useFees(usdc, 25e2, 25e2) {
        (uint256 mintAmount, ) = vone.previewDeposit(address(usdc), 1e18);

        usdc.mint(self, 1e18);

        vm.expectRevert();
        one.vaultMint(address(usdc), mintAmount + 1, address(this));

        vm.expectRevert();
        one.vaultDeposit(address(usdc), 1e18 + 1, address(this));
    }

    function testOneMintWithdraw() public useFees(usdc, 20e2, 20e2) {
        (uint256 outAmount, uint256 feesWithdraw) = vone.previewWithdraw(address(usdc), 2e18);
        (uint256 depositAmount, uint256 feesMint) = vone.previewMint(address(usdc), outAmount);

        usdc.mint(self, depositAmount);
        usdc.approve(oneAddr, depositAmount);

        one.vaultMint(address(usdc), outAmount, self);
        one.vaultWithdraw(address(usdc), 1e18, self, self);
        one.vaultWithdraw(address(usdc), 1e18, user1, self);

        assertEq(usdc.balanceOf(self), 1e18, "self-balance");
        assertEq(usdc.balanceOf(user1), 1e18, "user1-balance");
        assertEq(one.balanceOf(self), 0, "one-balance");
        assertEq(vone.getFees(address(usdc)), feesWithdraw + feesMint, "fees");
        assertEq(usdc.balanceOf(vaultAddr), feesWithdraw + feesMint, "vault-fee-balance");

        _ensureSupply(0);
    }

    function testOneMintWithdrawReverts() public useFees(usdc, 0, 0) {
        (uint256 mintAmount, ) = vone.previewDeposit(address(usdc), 1e18);

        usdc.mint(self, 1e18);
        one.vaultMint(address(usdc), mintAmount, self);

        vm.expectRevert();
        one.vaultWithdraw(address(usdc), mintAmount + 1, self, self);

        vm.expectRevert();
        one.vaultRedeem(address(usdc), mintAmount + 1, self, self);

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(NO_ALLOWANCE.selector, user1, self, mintAmount, 0));
        one.vaultWithdraw(address(usdc), mintAmount, user1, self);

        vm.expectRevert(abi.encodeWithSelector(NO_ALLOWANCE.selector, user1, self, mintAmount, 0));
        one.vaultRedeem(address(usdc), mintAmount, user1, self);
        vm.stopPrank();
    }

    function testOneMintRedeem() public useFees(usdc, 20e2, 20e2) {
        uint256 mintAmount = 2e18;
        uint256 depositAmount = mintAmount.pdiv(100e2 - 20e2);
        uint256 fees = depositAmount - mintAmount;

        usdc.mint(self, depositAmount);
        one.vaultMint(address(usdc), mintAmount, self);

        one.vaultRedeem(address(usdc), 1e18, user1, self);
        (uint256 redeemOut, uint256 feesRedeem) = one.vaultRedeem(address(usdc), 1e18, self, self);
        assertEq(redeemOut, 1e18.pmul(100e2 - 20e2));

        assertEq(usdc.balanceOf(self), redeemOut);
        assertEq(usdc.balanceOf(user1), redeemOut);
        assertEq(one.balanceOf(self), 0);

        uint256 totalFees = fees + feesRedeem + feesRedeem;
        assertEq(vone.getFees(address(usdc)), totalFees);
        assertEq(usdc.balanceOf(vaultAddr), totalFees);

        _ensureSupply(0);
    }

    function testOneDepositRedeem() public useFees(usdc, 25e2, 25e2) {
        uint256 mintAmount = 2e18;
        uint256 depositAmount = mintAmount.pdiv(100e2 - 25e2);
        uint256 depositFee = depositAmount - mintAmount;
        usdc.mint(self, depositAmount);
        usdc.approve(oneAddr, depositAmount);

        one.vaultDeposit(address(usdc), depositAmount, self);

        (uint256 redeemOut, uint256 feesRedeem) = one.vaultRedeem(address(usdc), 1e18, self, self);
        one.vaultRedeem(address(usdc), 1e18, user1, self);

        assertEq(usdc.balanceOf(self), redeemOut);
        assertEq(usdc.balanceOf(user1), redeemOut);
        assertEq(one.balanceOf(self), 0);

        uint256 totalFees = depositFee + feesRedeem + feesRedeem;
        assertEq(vone.getFees(address(usdc)), totalFees);
        assertEq(usdc.balanceOf(vaultAddr), totalFees);

        _ensureSupply(0);
    }

    function testOneDepositWithdraw() public useFees(usdc, 25e2, 25e2) {
        uint256 mintAmount = 2e18;
        uint256 depositAmount = mintAmount.pdiv(100e2 - 25e2).pdiv(100e2 - 25e2);
        uint256 totalFees = depositAmount - mintAmount - 1;
        usdc.mint(self, depositAmount);
        usdc.approve(oneAddr, depositAmount);

        one.vaultDeposit(address(usdc), depositAmount, self);
        one.vaultWithdraw(address(usdc), 1e18, self, self);
        one.vaultWithdraw(address(usdc), 1e18, user1, self);

        assertEq(vone.exchangeRate(), vone.baseRate());
        one.vaultRedeem(address(usdc), 1, self, self);
        assertEq(vone.exchangeRate(), vone.baseRate());

        assertEq(vone.getFees(address(usdc)), totalFees);
        assertEq(usdc.balanceOf(self), 1e18 + 1);
        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(one.balanceOf(self), 0);
        assertEq(usdc.balanceOf(vaultAddr), totalFees);

        _ensureSupply(0);
    }
}
