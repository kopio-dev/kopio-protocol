// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "kopio/vm/chain/ArbTest.t.sol";
import {BurnArgs, MintArgs, WithdrawArgs} from "kopio/IKopioCore.sol";

abstract contract ArbCoreTest is ArbTest {
    using ShortAssert for *;
    using Log for *;

    uint256 depositAmount = 15_000e6;
    address depositAsset = usdceAddr;
    uint256 depositValue;

    bool enableCoreTest;

    function setupCoreTest() internal {
        deal(bank, 1 ether);
        deal(user0, 10 ether);
        allApprovals(user0);

        depositValue = core.getValue(depositAsset, depositAmount);
        enableCoreTest = true;
    }

    modifier withDeposits(address user) {
        vm.skip(!enableCoreTest);

        prank(user);
        dealAsset(depositAsset, depositAmount);
        core.depositCollateral(user, depositAsset, depositAmount);
        dealONE(user, 15000 ether);
        core.depositSCDP(user, oneAddr, 15000 ether);
        _;
    }

    function testCollateralDeposit() public virtual withDeposits(user0) {
        core.getAccountCollateralAmount(user0, depositAsset).eq(depositAmount, "invalid-deposit-amount");
        core.getAccountTotalCollateralValue(user0).eq(depositValue, "invalid-deposit-value");
        IERC20(depositAsset).balanceOf(user0).eq(0, "invalid-deposit-balance");
    }

    function testCollateralWithdraw() public virtual withDeposits(user0) {
        uint256 balBefore = IERC20(depositAsset).balanceOf(user0);
        core.withdrawCollateral(WithdrawArgs(user0, usdceAddr, depositAmount, user0), noPyth);

        core.getAccountCollateralAmount(user0, usdceAddr).eq(0, "invalid-withdraw-amount");
        core.getAccountTotalCollateralValue(user0).eq(0, "invalid-withdraw-value");
        IERC20(depositAsset).balanceOf(user0).eq(balBefore + depositAmount, "invalid-withdraw-balance");
    }

    function testMintKopio() public virtual withDeposits(user0) {
        _testMintKopio(oneAddr, 1000 ether);
    }

    function testBurnKopio() public virtual withDeposits(user0) {
        _testMintKopio(oneAddr, 1000 ether);
        _testBurnKopio(oneAddr, 500 ether);
        _testBurnKopio(oneAddr, 500 ether);
    }

    function testSwapSCDP() public virtual withDeposits(user0) {
        core.getAccountCollateralValue(user0, depositAsset).clg("deposit-value");
        _testMintKopio(kETHAddr, 1 ether);

        uint256 approxValue = core.getValue(kETHAddr, 1 ether);
        swap(user0, kETHAddr, kJPYAddr, 1 ether);

        uint256 balJPY = kJPY.balanceOf(user0);
        balJPY.gtz("invalid-swap-balance");
        core.getValue(kJPYAddr, balJPY).closeTo(approxValue, 5e8, "invalid-swap-value-received");

        swap(user0, kJPYAddr, kEURAddr, balJPY);
        swap(user0, kEURAddr, kETHAddr, kEUR.balanceOf(user0));

        uint256 balkETH = kETH.balanceOf(user0);
        balkETH.gtz("invalid-swap-2-balance");
        core.getValue(kETHAddr, balkETH).closeTo(approxValue, 15e8, "invalid-swap-2-value-received");
    }

    function _testMintKopio(address mintAsset, uint256 mintAmount) internal virtual {
        uint256 totalValueBefore = core.getAccountTotalDebtValue(user0);
        uint256 minted = core.getAccountDebtAmount(user0, mintAsset);
        uint256 mintValue = core.getDebtValue(mintAsset, mintAmount);
        uint256 balBefore = IERC20(mintAsset).balanceOf(user0);

        core.mintKopio(MintArgs(user0, mintAsset, mintAmount, user0), noPyth);
        core.getAccountDebtAmount(user0, mintAsset).eq(minted + mintAmount, "invalid-mint-amount");
        core.getAccountTotalDebtValue(user0).eq(totalValueBefore + mintValue, "invalid-mint-value");
        IERC20(mintAsset).balanceOf(user0).eq(balBefore + mintAmount, "invalid-mint-balance");
    }

    function _testBurnKopio(address mintAsset, uint256 mintAmount) internal virtual {
        uint256 totalValueBefore = core.getAccountTotalDebtValue(user0);
        uint256 minted = core.getAccountDebtAmount(user0, mintAsset);
        uint256 mintValue = core.getDebtValue(mintAsset, mintAmount);
        uint256 balBefore = IERC20(mintAsset).balanceOf(user0);

        core.burnKopio(BurnArgs(user0, mintAsset, mintAmount, user0), noPyth);
        core.getAccountDebtAmount(user0, mintAsset).eq(minted - mintAmount, "invalid-debt-amount");
        core.getAccountTotalDebtValue(user0).eq(totalValueBefore - mintValue, "invalid-debt-value");
        IERC20(mintAsset).balanceOf(user0).eq(balBefore - mintAmount, "invalid-burn-balance");
    }
}
