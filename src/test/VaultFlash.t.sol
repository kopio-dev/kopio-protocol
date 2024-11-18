// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {VaultFlashTestBase} from "test/helpers/VaultTestBase.t.sol";
import {PLog} from "kopio/vm/PLog.s.sol";
import {Utils} from "kopio/utils/Libs.sol";
import {TRANSFER_FAILED} from "kopio/token/SafeTransfer.sol";
import {ERC20Mock} from "kopio/mocks/ERC20Mock.sol";

abstract contract Callbacks is VaultFlashTestBase {
    using PLog for *;

    function cbMintRepay(Flash calldata, bytes calldata d) internal ensureRate {
        uint256 repayShares = abi.decode(d, (uint256));
        usdc.mint(msg.sender, repayShares);
    }

    function cbMintDepositRepay(Flash calldata flash, bytes calldata d) internal ensureRate {
        vaultMint(flash.asset, flash.shares, address(this));
        assertEq(vone.exchangeRate(), vone.baseRate(), "cbMintDepositRepay-fx-rate");
        cbMintRepay(flash, d);
    }

    function cbWithdrawRepayFrom(Flash calldata, bytes calldata d) internal ensureRate {
        (address from, uint256 amount) = abi.decode(d, (address, uint256));
        vone.transferFrom(from, address(this), amount);
    }

    function cbWithdrawReturnDeposit(Flash calldata flash, bytes calldata d) internal ensureRate {
        uint256 repayAmount = abi.decode(d, (uint256));
        vone.deposit(flash.asset, repayAmount, address(this));
    }

    function cbWithdrawReturnMint(Flash calldata flash, bytes calldata d) internal ensureRate {
        uint256 repayAmount = abi.decode(d, (uint256));
        vone.mint(flash.asset, repayAmount, address(this));
    }
}

contract VaultFlashTest is Callbacks {
    using PLog for *;
    using Utils for *;

    function setUp() public override {
        super.setUp();
        _flashApprovals(user4, type(uint256).max);
    }

    function testFlashMintRepay() public useCallback(cbMintRepay) useDFee(usdc, 25e2) {
        uint256 shareAmount = 1000 ether;
        (uint256 usdcAmount, uint256 usdcFee) = vone.previewMint(address(usdc), shareAmount);

        vone.flash(address(usdc), shareAmount, self, abi.encode(usdcAmount));

        assertEq(usdc.balanceOf(self), 0, "testFlashMintRepay-usdc-user");
        assertEq(vone.balanceOf(self), shareAmount, "testFlashMintRepay-shares-user");
        assertEq(vone.totalSupply(), shareAmount, "testFlashMintRepayReverts-share-supply");

        assertEq(vone.getFees(address(usdc)), usdcFee, "testFlashMintRepay-fees");
        assertEq(usdc.balanceOf(vaultAddr), usdcAmount, "testFlashMintRepay-assets-sent");
        assertEq(usdc.totalSupply(), usdc.balanceOf(vaultAddr), "testFlashMintDepositRepay-asset-supply");
    }

    function testFlashMintRepayReverts() public useCallback(cbMintRepay) useDFee(usdc, 25e2) {
        uint256 shareAmount = 1000 ether;
        (uint256 usdcAmount, ) = vone.previewMint(address(usdc), shareAmount);

        vm.expectRevert(abi.encodeWithSelector(INSUFFICIENT_ASSETS.selector, address(usdc), usdcAmount - 2, usdcAmount));
        vone.flash(address(usdc), shareAmount, self, abi.encode(usdcAmount - 2));
    }

    function testFlashMintDepositRepay() public useCallback(cbMintDepositRepay) useDFee(usdc, 25e2) {
        uint256 shareAmount = 1000 ether;
        (uint256 usdcAmount, ) = vone.previewMint(address(usdc), shareAmount);

        uint256 expectedShares = shareAmount * 2;
        (uint256 expectedUSDC, uint256 expectedFee) = vone.previewMint(address(usdc), expectedShares);

        uint256 repayUSDC = expectedUSDC - usdcAmount;

        vone.flash(address(usdc), shareAmount, self, abi.encode(repayUSDC));

        assertEq(usdc.balanceOf(self), 0, "testFlashMintDepositRepay-usdc-user");
        assertEq(vone.balanceOf(self), expectedShares, "testFlashMintDepositRepay-shares-user");

        assertEq(vone.getFees(address(usdc)), expectedFee, "testFlashMintDepositRepay-fees");
        assertEq(usdc.balanceOf(vaultAddr), expectedUSDC, "testFlashMintDepositRepay-assets-sent");

        assertEq(vone.totalSupply(), expectedShares, "testFlashMintDepositRepay-share-supply");
        assertEq(usdc.totalSupply(), expectedUSDC, "testFlashMintDepositRepay-asset-supply");
    }

    function testFlashMintDepositRepayReverts() public useCallback(cbMintDepositRepay) {
        uint256 shareAmount = 1000 ether;
        (uint256 usdcAmount, ) = vone.previewMint(address(usdc), shareAmount);

        uint256 expectedShares = shareAmount * 2;
        (uint256 expectedUSDC, ) = vone.previewMint(address(usdc), expectedShares);

        uint256 repayUSDC = expectedUSDC - usdcAmount;
        vm.expectRevert(abi.encodeWithSelector(INSUFFICIENT_ASSETS.selector, address(usdc), expectedUSDC - 10, expectedUSDC));
        vone.flash(address(usdc), shareAmount, self, abi.encode(repayUSDC - 10));
    }

    function testFlashWithdrawFullRepayFrom() public setDeposits(usdc, 1000 ether.pdiv(100e2 - 25e2), true) useCallback(cbWithdrawRepayFrom) {
        _testFlashWithdrawRepayFrom(usdc, 1000 ether, 25e2, 25e2);
    }
    function testFlashWithdrawPartialRepayFrom18DEC() public setDeposits(usdc, 2000 ether, true) useCallback(cbWithdrawRepayFrom) {
        _testFlashWithdrawRepayFrom(usdc, 1000 ether, 25e2, 25e2);
    }
    function testFlashWithdrawPartialRepayFrom6DEC() public setDeposits(usdt, 2000e6, true) useCallback(cbWithdrawRepayFrom) {
        _testFlashWithdrawRepayFrom(usdt, 1000e6, 25e2, 25e2);
    }

    function _testFlashWithdrawRepayFrom(ERC20Mock asset, uint256 withdrawAmount, uint16 dfee, uint16 wfee) public useFees(usdc, dfee, wfee) {
        uint256 assetsBefore = asset.balanceOf(vaultAddr);
        uint256 supplyBefore = vone.totalSupply();

        (uint256 shareAmount, uint256 fees) = vone.previewWithdraw(address(asset), withdrawAmount);

        vone.flash(address(asset), withdrawAmount, self, self, abi.encode(user4, shareAmount));

        assertEq(vone.balanceOf(self), 0, "FlashWithdrawRepayFrom-shares-user");

        uint256 expectedSharesAfter = supplyBefore - shareAmount;
        assertEq(vone.balanceOf(user4), expectedSharesAfter, "FlashWithdrawRepayFrom-shares-user4");
        assertEq(vone.totalSupply(), expectedSharesAfter, "FlashWithdrawRepayFrom-share-supply");
        assertEq(vone.getFees(address(asset)), fees, "FlashWithdrawRepayFrom-fees");

        assertEq(asset.balanceOf(vaultAddr), assetsBefore - withdrawAmount, "FlashWithdrawRepayFrom-assets-vault");
        assertEq(asset.balanceOf(self), withdrawAmount, "FlashWithdrawRepayFrom-assets-self");
        assertEq(asset.totalSupply(), assetsBefore, "FlashWithdrawRepayFrom-asset-totalsupply");
    }

    function testFlashWithdrawReturnMint() public useFees(usdc, 0, 0) setDeposits(usdc, 1000 ether, true) useCallback(cbWithdrawReturnMint) {
        uint256 supplyBefore = vone.totalSupply();
        uint256 usdcBefore = usdc.balanceOf(vaultAddr);

        uint256 usdcAmount = 1000 ether;
        vone.flash(address(usdc), usdcAmount, self, self, abi.encode(usdcAmount));

        assertEq(usdc.balanceOf(self), 0, "testFlashWithdrawReturnMint-usdc-user");
        assertEq(vone.balanceOf(self), 0, "testFlashWithdrawReturnMint-shares-user");
        assertEq(vone.totalSupply(), supplyBefore, "testFlashWithdrawReturnMint-share-supply");

        assertEq(vone.getFees(address(usdc)), 0, "testFlashWithdrawReturnMint-fees");
        assertEq(usdc.balanceOf(vaultAddr), usdcBefore, "testFlashWithdrawReturnMint-assets-sent");
        assertEq(usdc.totalSupply(), usdcBefore, "testFlashWithdrawReturnMint-asset-supply");
    }

    uint256 dFee;
    uint256 wFee;
    function testFlashWithdrawReturnDeposit() public useFees(usdc, dFee = 10, wFee = 20) setDeposits(usdc, 1000 ether, true) useCallback(cbWithdrawReturnDeposit) {
        uint256 supplyBefore = vone.totalSupply();

        uint256 usdcAmount = 1000 ether;
        uint256 usdcRequired = usdcAmount.pdiv(100e2 - dFee).pdiv(100e2 - wFee) - 1;
        uint256 expectedFees = usdcRequired - usdcAmount;

        usdc.mint(self, expectedFees);
        vone.flash(address(usdc), usdcAmount, self, self, abi.encode(usdcRequired));

        assertEq(usdc.balanceOf(self), 0, "testFlashWithdrawReturnWithFees-usdc-user");
        assertEq(vone.balanceOf(self), 0, "testFlashWithdrawReturnWithFees-shares-user");
        assertEq(vone.totalSupply(), supplyBefore, "testFlashWithdrawReturnWithFees-share-supply");

        assertEq(vone.getFees(address(usdc)), expectedFees, "testFlashWithdrawReturnWithFees-fees");
        assertEq(usdc.balanceOf(vaultAddr), 1000 ether + expectedFees, "testFlashWithdrawReturnWithFees-assets-sent");
        assertEq(usdc.totalSupply(), 1000 ether + expectedFees, "testFlashWithdrawReturnWithFees-asset-supply");
        assertEq(vone.balanceOf(user4), vone.totalSupply(), "testFlashWithdrawReturnWithFees-asset-supply-location");
    }

    function testFlashWithdrawReverts() public useFees(usdc, dFee = 0, wFee = 0) setDeposits(usdc, 1000 ether, true) useCallback(cbWithdrawReturnDeposit) {
        uint256 depositsAvailable = 1000 ether;

        vm.expectRevert(abi.encodeWithSelector(NOT_ENOUGH_BALANCE.selector, address(this), depositsAvailable - 1, depositsAvailable));
        vone.flash(address(usdc), depositsAvailable, self, self, abi.encode(depositsAvailable - 1));
    }

    function testFlashWithdrawRevertsMax() public useFees(usdc, dFee = 0, wFee = 0) setDeposits(usdc, 1000 ether, true) useCallback(cbWithdrawReturnDeposit) {
        uint256 withdrawAmount = 1001 ether;

        vm.expectRevert(abi.encodeWithSelector(TRANSFER_FAILED.selector, address(usdc), address(this), address(this), withdrawAmount));
        vone.flash(address(usdc), withdrawAmount, self, self, abi.encode(withdrawAmount));
    }
}
