// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// solhint-disable state-visibility, avoid-low-level-calls, no-console, max-states-count, var-name-mixedcase, no-global-import, const-name-snakecase, no-empty-blocks, no-console

import {ShortAssert} from "kopio/vm/ShortAssert.t.sol";
import {Utils, Log} from "kopio/vm/VmLibs.s.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {Deploy} from "scripts/deploy/Deploy.s.sol";
import {Kopio} from "asset/Kopio.sol";
import {ERC20Mock, MockOracle} from "mocks/Mocks.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {JSON} from "scripts/deploy/libs/LibJSON.s.sol";
import {MintArgs, SCDPLiquidationArgs, SCDPWithdrawArgs, SwapArgs} from "common/Args.sol";
import {Params} from "scripts/deploy/JSON.s.sol";
import {Tested} from "kopio/vm/Tested.t.sol";

contract ComplexTest is Tested, Deploy {
    using ShortAssert for *;
    using Log for *;
    using Utils for *;
    uint256 constant ETH_PRICE = 2000;

    IERC20 internal vaultShare;
    Params paramsJSON;
    Kopio kETH;
    address kETHAddr;
    MockOracle ethFeed;
    ERC20Mock usdc;
    ERC20Mock usdt;

    struct FeeTestRebaseConfig {
        uint248 rebaseMultiplier;
        bool positive;
        uint256 ethPrice;
        uint256 firstLiquidationPrice;
        uint256 secondLiquidationPrice;
    }

    function setUp() public {
        JSON.Config memory cfg = Deploy.deployTest("MNEMONIC_KOPIO", "test-audit", 0);
        paramsJSON = cfg.params;
        getAddr(0).clg("deployer");
        cfg.params.common.admin.clg("admin");
        // for price updates
        vm.deal(address(protocol), 1 ether);
        vm.deal(getAddr(0), 1 ether);

        usdc = ERC20Mock(Deployed.addr("USDC"));
        usdt = ERC20Mock(Deployed.addr("USDT"));
        vaultShare = IERC20(address(vault));
        kETHAddr = Deployed.addr("kETH");
        ethFeed = MockOracle(Deployed.addr("ETH.feed"));
        kETH = Kopio(payable(kETHAddr));

        prank(getAddr(0));

        _setETHPrice(ETH_PRICE);

        protocol.setSwapFees(address(kETH), 390, 390, 5000);
        vault.setAssetFees(address(usdt), 10e2, 10e2);

        usdc.approve(address(protocol), type(uint256).max);
        kETH.approve(address(protocol), type(uint256).max);
        // 1000 ONE -> 0.48 ETH
        protocol.swapSCDP(SwapArgs(getAddr(0), address(one), kETHAddr, 1000e18, 0, pyth.update));
    }

    function testRebase() external {
        prank(0);

        uint256 crBefore = protocol.getGlobalCollateralRatio();
        uint256 amountDebtBefore = protocol.getDebtSCDP(kETHAddr);
        uint256 valDebtBefore = protocol.getDebtValueSCDP(kETHAddr, false);
        amountDebtBefore.gt(0, "debt-zero");
        crBefore.gt(0, "cr-zero");
        valDebtBefore.gt(0, "valDebt-zero");
        _setETHPrice(1000);
        kETH.rebase(2e18, true, new bytes(0));
        uint256 amountDebtAfter = protocol.getDebtSCDP(kETHAddr);
        uint256 valDebtAfter = protocol.getDebtValueSCDP(kETHAddr, false);
        amountDebtBefore.eq(amountDebtAfter / 2, "debt-not-gt-after-rebase");
        crBefore.eq(protocol.getGlobalCollateralRatio(), "cr-not-equal-after-rebase");
        valDebtBefore.eq(valDebtAfter, "valDebt-not-equal-after-rebase");
    }

    function testSharedLiquidationAfterRebaseOak1() external {
        prank(getAddr(0));
        uint256 amountDebtBefore = protocol.getDebtSCDP(kETHAddr);
        amountDebtBefore.clg("amount-debt-before");
        // rebase up 2x and adjust price accordingly
        _setETHPrice(1000);
        kETH.rebase(2e18, true, new bytes(0));
        // 1000 ONE -> 0.96 ETH
        protocol.swapSCDP(SwapArgs(getAddr(0), address(one), kETHAddr, 1000e18, 0, pyth.update));
        // previous debt amount 0.48 ETH, doubled after rebase so 0.96 ETH
        uint256 amountDebtAfter = protocol.getDebtSCDP(kETHAddr);
        amountDebtAfter.eq(0.96e18 + (0.48e18 * 2), "amount-debt-after");
        // matches $1000 ETH valuation
        uint256 valueDebtAfter = protocol.getDebtValueSCDP(kETHAddr, true);
        valueDebtAfter.eq(1920e8, "value-debt-after");
        // make it liquidatable
        _setETHPrice(20000);
        uint256 crAfter = protocol.getGlobalCollateralRatio();
        crAfter.lt(paramsJSON.scdp.liquidationThreshold); // cr-after: 112.65%
        // this fails without the fix as normalized debt amount is 0.96 kETH
        // vm.expectRevert();
        _liquidate(kETHAddr, 0.96e18 + 1, address(one));
    }

    function testWithdrawPartialOak6() external {
        uint256 amount = 4000e18;
        // Setup another user
        address userOther = getAddr(55);
        one.balanceOf(userOther).eq(0, "bal-not-zero");
        one.transfer(userOther, amount);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), amount);
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(amount, "deposit-not-amount");
        one.balanceOf(userOther).eq(0, "bal-not-zero-after-deposit");
        uint256 withdrawAmount = amount / 2;

        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), withdrawAmount, userOther), pyth.update);
        one.balanceOf(userOther).eq(withdrawAmount, "bal-not-initial-after-withdraw");
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(withdrawAmount, "deposit-not-amount");
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), withdrawAmount, userOther), pyth.update);
        one.balanceOf(userOther).eq(amount, "bal-not-initial-after-withdraw");
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(0, "deposit-not-amount");
    }

    function testDepositWithdrawLiquidationOak6() external {
        uint256 amount = 4000e18;
        // Setup another user
        address userOther = getAddr(55);
        one.balanceOf(userOther).eq(0, "bal-not-zero");
        one.transfer(userOther, amount);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), amount);
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(amount, "deposit-not-amount");
        one.balanceOf(userOther).eq(0, "bal-not-zero-after-deposit");
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), amount, userOther), pyth.update);
        one.balanceOf(userOther).eq(amount, "bal-not-initial-after-withdraw");
        vm.expectRevert();
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), 1, userOther), pyth.update);
        protocol.depositSCDP(userOther, address(one), amount);
        // Make it liquidatable
        _setETHPriceAndLiquidate(80000);
        _setETHPrice(ETH_PRICE);
        prank(userOther);
        uint256 deposits = protocol.getAccountDepositSCDP(userOther, address(one));
        deposits.dlg("deposits");
        vm.expectRevert();
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), amount, userOther), pyth.update);
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), deposits, userOther), pyth.update);
        one.balanceOf(userOther).eq(deposits, "bal-not-deposits-after-withdraw");
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(0, "deposit-not-zero-after-withdarw");
    }

    function testClaimFeesOak6() external {
        uint256 amount = 4000e18;
        // Setup another user
        address userOther = getAddr(55);
        one.balanceOf(userOther).eq(0, "bal-not-zero");
        one.transfer(userOther, amount);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), amount);
        _trades(10);
        prank(userOther);
        protocol.getAccountFeesSCDP(userOther, address(one)).gt(0, "no-fees");
        uint256 feesClaimed = protocol.claimFeesSCDP(userOther, address(one), userOther);
        one.balanceOf(userOther).eq(feesClaimed, "bal-not-zero");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-not-zero-after-claim");
        uint256 withdrawAmount = amount / 2;
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), withdrawAmount, userOther), pyth.update);
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(withdrawAmount, "deposit-should-be-half-after-withdraw");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-not-zero-after-withdraw");
        one.balanceOf(userOther).eq(feesClaimed + withdrawAmount, "bal-not-zero-after-withdraw");
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), withdrawAmount, userOther), pyth.update);
        one.balanceOf(userOther).closeTo(feesClaimed + amount, 1);
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(0, "deposit-should-be-zero-in-the-end");
    }

    function testClaimFeesDuringDeposit() external {
        uint256 amount = 4000e18;
        uint256 depositAmount = amount / 2;
        // Setup another user
        address userOther = getAddr(55);
        one.balanceOf(userOther).eq(0, "bal-not-zero");
        one.transfer(userOther, amount);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), depositAmount);
        _trades(10);
        prank(userOther);
        uint256 feeAmount = protocol.getAccountFeesSCDP(userOther, address(one));
        feeAmount.gt(0, "no-fees");
        protocol.depositSCDP(userOther, address(one), depositAmount);
        one.balanceOf(userOther).eq(feeAmount, "bal-not-zero");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-not-zero-after-claim");
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(amount, "deposit-not-zero-after-withdraw");
    }

    function testClaimFeesDuringWithdrawOak6() external {
        uint256 amount = 4000e18;
        // Setup another user
        address userOther = getAddr(55);
        one.balanceOf(userOther).eq(0, "bal-not-zero");
        one.transfer(userOther, amount);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), amount);
        _trades(10);
        prank(userOther);
        uint256 feeAmount = protocol.getAccountFeesSCDP(userOther, address(one));
        feeAmount.gt(0, "no-fees");
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), amount, userOther), pyth.update);
        one.balanceOf(userOther).eq(feeAmount + amount, "bal-not-zero");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-not-zero-after-claim");
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(0, "deposit-not-zero-after-withdraw");
    }

    function testClaimFeesAfterLiquidationOak6() external {
        uint256 amount = 4000e18;
        // Setup another user
        address userOther = getAddr(55);
        one.balanceOf(userOther).eq(0, "bal-not-zero");
        one.transfer(userOther, amount);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), amount);
        _trades(10);
        prank(userOther);
        protocol.getAccountFeesSCDP(userOther, address(one)).gt(0, "no-fees");
        // Make it liquidatable
        _setETHPriceAndLiquidate(77000);
        _setETHPrice(ETH_PRICE);
        prank(userOther);
        uint256 depositsBeforeClaim = protocol.getAccountDepositSCDP(userOther, address(one));
        uint256 feesClaimed = protocol.claimFeesSCDP(userOther, address(one), userOther);
        one.balanceOf(userOther).eq(feesClaimed, "bal-not-zero");
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(depositsBeforeClaim, "deposit-should-be-same-after-claim");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-not-zero-after-claim");
        uint256 withdrawAmount = depositsBeforeClaim / 2;
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), withdrawAmount, userOther), pyth.update);
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(withdrawAmount, "deposit-should-be-half-after-withdraw");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-not-zero-after-withdraw");
        one.balanceOf(userOther).eq(feesClaimed + withdrawAmount, "bal-not-zero-after-withdraw");
        protocol.withdrawSCDP(SCDPWithdrawArgs(userOther, address(one), withdrawAmount, userOther), pyth.update);
        one.balanceOf(userOther).closeTo(feesClaimed + depositsBeforeClaim, 1);
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(0, "deposit-should-be-zero-in-the-end");
    }

    function testFeeDistributionAfterMultipleLiquidationsOak6() external {
        uint256 feePerSwapTotal = 16e18;
        uint256 feesStart = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        // Swap, 1000 ONE -> 0.96 ETH
        prank(getAddr(0));
        protocol.swapSCDP(SwapArgs(getAddr(0), address(one), kETHAddr, 2000e18, 0, pyth.update));
        uint256 feesUserAfterFirstSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 totalSwapFees = feesUserAfterFirstSwap - feesStart;
        totalSwapFees.eq(feePerSwapTotal, "fees-should-equal-total");
        // Make it liquidatable
        _setETHPriceAndLiquidate(28000);
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(feesUserAfterFirstSwap, "fee-should-not-change-after-liquidation");
        // Setup another user
        address userOther = getAddr(55);
        one.transfer(userOther, 5000e18);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), 5000e18);
        // Perform equal swap again
        _setETHPriceAndSwap(2000, 2000e18);
        uint256 feesUserAfterSecondSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feeDiff = feesUserAfterSecondSwap - feesUserAfterFirstSwap;
        uint256 feesOtherUser = protocol.getAccountFeesSCDP(userOther, address(one));
        totalSwapFees = (feesOtherUser + feeDiff);
        totalSwapFees.eq(feePerSwapTotal, "fees-should-not-change-after-second-swap");
        // Liquidate again
        _setETHPriceAndLiquidate(17500);
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(feesUserAfterSecondSwap, "fee-should-not-change-after-second-liquidation");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(feesOtherUser, "fee-should-not-change-after-second-liquidation-other-user");
        uint256 feesUserBeforeSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feesOtherUserBeforeSwap = protocol.getAccountFeesSCDP(userOther, address(one));
        // Perform equal swap again
        _setETHPriceAndSwap(2000, 2000e18);
        uint256 feesUserAfterSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feesOtherUserAfterSwap = protocol.getAccountFeesSCDP(userOther, address(one));
        totalSwapFees = (feesUserAfterSwap - feesUserBeforeSwap) + (feesOtherUserAfterSwap - feesOtherUserBeforeSwap);
        totalSwapFees.eq(feePerSwapTotal, "fees-should-not-change-after-third-swap");
        // Test claims
        prank(getAddr(0));
        uint256 balBefore = one.balanceOf(getAddr(0));
        uint256 feeAmount = protocol.claimFeesSCDP(getAddr(0), address(one), getAddr(0));
        one.balanceOf(getAddr(0)).eq(balBefore + feeAmount, "balance-should-have-fees-after-claim");
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(0, "fees-should-be-zero-after-claim-user");
        prank(userOther);
        uint256 feeAmountUserOther = protocol.claimFeesSCDP(userOther, address(one), userOther);
        one.balanceOf(userOther).eq(feeAmountUserOther);
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-should-be-zero-after-claim-user-other");
    }

    function testFeeDistributionAfterMultipleLiquidationsPositiveRebaseOak6() external {
        uint256 feePerSwapTotal = 16e18;
        uint256 feesStart = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        // Setup
        FeeTestRebaseConfig memory test = _feeTestRebaseConfig(247, true);
        prank(getAddr(0));
        _setETHPrice(test.ethPrice);
        kETH.rebase(test.rebaseMultiplier, test.positive, new bytes(0));
        // Swap, 1000 ONE -> 0.96 ETH
        protocol.swapSCDP(SwapArgs(getAddr(0), address(one), kETHAddr, 2000e18, 0, pyth.update));
        uint256 feesUserAfterFirstSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 totalSwapFees = feesUserAfterFirstSwap - feesStart;
        totalSwapFees.eq(feePerSwapTotal, "fees-should-equal-total");
        // Make it liquidatable
        _setETHPriceAndLiquidate(test.firstLiquidationPrice);
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(feesUserAfterFirstSwap, "fee-should-not-change-after-liquidation");
        // Setup another user
        address userOther = getAddr(55);
        one.transfer(userOther, 5000e18);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), 5000e18);
        // Perform equal swap again
        _setETHPriceAndSwap(test.ethPrice, 2000e18);
        uint256 feesUserAfterSecondSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feeDiff = feesUserAfterSecondSwap - feesUserAfterFirstSwap;
        uint256 feesOtherUser = protocol.getAccountFeesSCDP(userOther, address(one));
        totalSwapFees = (feesOtherUser + feeDiff);
        totalSwapFees.eq(feePerSwapTotal, "fees-should-not-change-after-second-swap");
        // Liquidate again
        _setETHPriceAndLiquidate(test.secondLiquidationPrice);
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(feesUserAfterSecondSwap, "fee-should-not-change-after-second-liquidation");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(feesOtherUser, "fee-should-not-change-after-second-liquidation-other-user");
        uint256 feesUserBeforeThirdSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feesOtherUserBeforeThirdSwap = protocol.getAccountFeesSCDP(userOther, address(one));
        // Perform equal swap again
        _setETHPriceAndSwap(test.ethPrice, 2000e18);
        uint256 feesUserAfterThirdSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feesOtherUserAfterThirdSwap = protocol.getAccountFeesSCDP(userOther, address(one));
        totalSwapFees = (feesUserAfterThirdSwap - feesUserBeforeThirdSwap) + (feesOtherUserAfterThirdSwap - feesOtherUserBeforeThirdSwap);
        totalSwapFees.eq(feePerSwapTotal, "fees-should-not-change-after-third-swap");
        // Test claims
        prank(getAddr(0));
        uint256 balBefore = one.balanceOf(getAddr(0));
        uint256 feeAmount = protocol.claimFeesSCDP(getAddr(0), address(one), getAddr(0));
        one.balanceOf(getAddr(0)).eq(balBefore + feeAmount, "balance-should-have-fees-after-claim");
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(0, "fees-should-be-zero-after-claim-user");
        prank(userOther);
        uint256 feeAmountUserOther = protocol.claimFeesSCDP(userOther, address(one), userOther);
        one.balanceOf(userOther).eq(feeAmountUserOther);
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-should-be-zero-after-claim-user-other");
    }

    function testFeeDistributionAfterMultipleLiquidationsNegativeRebaseOak6() external {
        uint256 feePerSwapTotal = 16e18;
        uint256 feesStart = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        // Setup
        FeeTestRebaseConfig memory test = _feeTestRebaseConfig(4128, false);
        prank(getAddr(0));
        _setETHPrice(test.ethPrice);
        kETH.rebase(test.rebaseMultiplier, test.positive, new bytes(0));
        // Swap, 1000 ONE -> 0.96 ETH
        protocol.swapSCDP(SwapArgs(getAddr(0), address(one), kETHAddr, 2000e18, 0, pyth.update));
        uint256 feesUserAfterFirstSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 totalSwapFees = feesUserAfterFirstSwap - feesStart;
        totalSwapFees.eq(feePerSwapTotal, "fees-should-equal-total");
        // Make it liquidatable
        _setETHPriceAndLiquidate(test.firstLiquidationPrice);
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(feesUserAfterFirstSwap, "fee-should-not-change-after-liquidation");
        // Setup another user
        address userOther = getAddr(55);
        one.transfer(userOther, 5000e18);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), 5000e18);
        // Perform equal swap again
        _setETHPriceAndSwap(test.ethPrice, 2000e18);
        uint256 feesUserAfterSecondSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feeDiff = feesUserAfterSecondSwap - feesUserAfterFirstSwap;
        uint256 feesOtherUser = protocol.getAccountFeesSCDP(userOther, address(one));
        totalSwapFees = (feesOtherUser + feeDiff);
        totalSwapFees.eq(feePerSwapTotal, "fees-should-not-change-after-second-swap");
        // Liquidate again
        _setETHPriceAndLiquidate(test.secondLiquidationPrice);
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(feesUserAfterSecondSwap, "fee-should-not-change-after-second-liquidation");
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(feesOtherUser, "fee-should-not-change-after-second-liquidation-other-user");
        uint256 feesUserBeforeThirdSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feesOtherUserBeforeThirdSwap = protocol.getAccountFeesSCDP(userOther, address(one));
        // Perform equal swap again
        _setETHPriceAndSwap(test.ethPrice, 2000e18);
        uint256 feesUserAfterThirdSwap = protocol.getAccountFeesSCDP(getAddr(0), address(one));
        uint256 feesOtherUserAfterThirdSwap = protocol.getAccountFeesSCDP(userOther, address(one));
        totalSwapFees = (feesUserAfterThirdSwap - feesUserBeforeThirdSwap) + (feesOtherUserAfterThirdSwap - feesOtherUserBeforeThirdSwap);
        totalSwapFees.eq(feePerSwapTotal, "fees-should-not-change-after-third-swap");
        // Test claims
        prank(getAddr(0));
        uint256 balBefore = one.balanceOf(getAddr(0));
        uint256 feeAmount = protocol.claimFeesSCDP(getAddr(0), address(one), getAddr(0));
        one.balanceOf(getAddr(0)).eq(balBefore + feeAmount, "balance-should-have-fees-after-claim");
        protocol.getAccountFeesSCDP(getAddr(0), address(one)).eq(0, "fees-should-be-zero-after-claim-user");
        prank(userOther);
        uint256 feeAmountUserOther = protocol.claimFeesSCDP(userOther, address(one), userOther);
        one.balanceOf(userOther).eq(feeAmountUserOther);
        protocol.getAccountFeesSCDP(userOther, address(one)).eq(0, "fees-should-be-zero-after-claim-user-other");
    }

    function testFullLiquidation() external {
        vm.skip(true);

        uint256 amount = 4000e18;
        // Setup another user
        address userOther = getAddr(55);
        one.balanceOf(userOther).eq(0, "bal-not-zero");
        one.transfer(userOther, amount);
        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), amount);
        _trades(10);
        prank(userOther);
        protocol.getAccountFeesSCDP(userOther, address(one)).gt(0, "no-fees");
        // Make it liquidatable
        _setETHPriceAndLiquidate(109021);
        _setETHPrice(ETH_PRICE);
        prank(userOther);
        protocol.getAccountDepositSCDP(userOther, address(one)).lt(1e18, "deposits");
    }

    function testCoverSCDPOak8() external {
        uint256 amount = 4000e18;
        // Setup another user
        address userOther = getAddr(55);
        one.balanceOf(userOther).eq(0, "bal-not-zero");
        one.transfer(userOther, amount);

        prank(userOther);
        one.approve(address(protocol), type(uint256).max);
        protocol.depositSCDP(userOther, address(one), amount);

        prank(userOther);
        uint256 swapDeposits = protocol.getSwapDepositsSCDP(address(one));
        uint256 depositsBeforeUser = protocol.getAccountDepositSCDP(getAddr(0), address(one));
        uint256 depositsBeforeOtherUser = protocol.getAccountDepositSCDP(userOther, address(one));
        // Make it liquidatable

        _setETHPriceAndCover(104071, 1000e18);
        prank(userOther);
        protocol.getAccountDepositSCDP(userOther, address(one)).eq(amount, "deposits");

        // Make it liquidatable
        _setETHPriceAndCoverIncentive(104071, 5000e18);
        uint256 amountFromUsers = (5000e18).pmul(paramsJSON.scdp.coverIncentive) - swapDeposits;
        protocol.getSwapDepositsSCDP(address(one)).eq(0, "swap-deps-after");
        uint256 depositsAfterUser = protocol.getAccountDepositSCDP(getAddr(0), address(one));
        depositsAfterUser.lt(depositsBeforeUser, "deposits-after-cover-user");
        uint256 depositsAfterOtherUser = protocol.getAccountDepositSCDP(userOther, address(one));
        protocol.getAccountDepositSCDP(userOther, address(one)).lt(depositsBeforeOtherUser, "deposits-after-cover-user-other");
        uint256 totalSeized = (depositsBeforeOtherUser - depositsAfterOtherUser) + (depositsBeforeUser - depositsAfterUser);
        totalSeized.eq(amountFromUsers, "total-seized");
    }

    /* -------------------------------- Util -------------------------------- */
    function _feeTestRebaseConfig(uint248 multiplier, bool positive) internal pure returns (FeeTestRebaseConfig memory) {
        if (positive) {
            return
                FeeTestRebaseConfig({
                    positive: positive,
                    rebaseMultiplier: multiplier * 1e18,
                    ethPrice: ETH_PRICE / multiplier,
                    firstLiquidationPrice: 28000 / multiplier,
                    secondLiquidationPrice: 17500 / multiplier
                });
        }
        return
            FeeTestRebaseConfig({
                positive: positive,
                rebaseMultiplier: multiplier * 1e18,
                ethPrice: ETH_PRICE * multiplier,
                firstLiquidationPrice: 28000 * multiplier,
                secondLiquidationPrice: 17500 * multiplier
            });
    }

    function _setETHPriceAndSwap(uint256 price, uint256 swapAmount) internal {
        prank(getAddr(0));
        _setETHPrice(price);
        protocol.setDFactor(kETHAddr, 1.2e4);
        protocol.swapSCDP(SwapArgs(getAddr(0), address(one), kETHAddr, swapAmount, 0, pyth.update));
    }

    function _setETHPriceAndLiquidate(uint256 price) internal {
        prank(getAddr(0));
        uint256 debt = protocol.getDebtSCDP(kETHAddr);
        if (debt < kETH.balanceOf(getAddr(0))) {
            usdc.mint(getAddr(0), 100_000e6);
            protocol.depositCollateral(getAddr(0), address(usdc), 100_000e6);
            protocol.mintKopio(MintArgs(getAddr(0), kETHAddr, debt, getAddr(0)), pyth.update);
        }
        protocol.setDFactor(kETHAddr, 1e4);
        _setETHPrice(price);
        protocol.getGlobalCollateralRatio().plg("CR: before-liq");
        _liquidate(kETHAddr, debt, address(one));
    }

    function _setETHPriceAndLiquidate(uint256 price, uint256 amount) internal {
        prank(getAddr(0));
        if (amount < kETH.balanceOf(getAddr(0))) {
            usdc.mint(getAddr(0), 100_000e6);
            protocol.depositCollateral(getAddr(0), address(usdc), 100_000e6);
            protocol.mintKopio(MintArgs(getAddr(0), kETHAddr, amount, getAddr(0)), pyth.update);
        }
        protocol.setDFactor(kETHAddr, 1e4);
        _setETHPrice(price);
        protocol.getGlobalCollateralRatio().plg("CR: before-liq");
        _liquidate(kETHAddr, amount.wdiv(price * 1e18), address(one));
    }

    function _setETHPriceAndCover(uint256 price, uint256 amount) internal {
        prank(getAddr(0));
        // uint256 debt = protocol.getDebtSCDP(kETHAddr);
        usdc.mint(getAddr(0), 100_000e6);
        usdc.approve(address(one), type(uint256).max);
        one.vaultMint(address(usdc), amount, getAddr(0));
        one.approve(address(protocol), type(uint256).max);
        protocol.setDFactor(kETHAddr, 1e4);
        _setETHPrice(price);
        protocol.getGlobalCollateralRatio().plg("CR: before-cover");
        _cover(amount);
        protocol.getGlobalCollateralRatio().plg("CR: after-cover");
    }

    function _setETHPriceAndCoverIncentive(uint256 price, uint256 amount) internal {
        prank(getAddr(0));
        // uint256 debt = protocol.getDebtSCDP(kETHAddr);
        usdc.mint(getAddr(0), 100_000e6);
        usdc.approve(address(one), type(uint256).max);
        one.vaultMint(address(usdc), amount, getAddr(0));
        one.approve(address(protocol), type(uint256).max);
        protocol.setDFactor(kETHAddr, 1e4);
        _setETHPrice(price);
        protocol.getGlobalCollateralRatio().plg("CR: before-cover");
        _coverIncentive(amount, address(one));
        protocol.getGlobalCollateralRatio().plg("CR: after-cover");
    }

    function _trades(uint256 count) internal {
        address trader = getAddr(777);
        uint256 mintAmount = 20000e6;
        usdc.mint(trader, mintAmount * count);

        prank(trader);
        usdc.approve(address(one), type(uint256).max);
        one.approve(address(protocol), type(uint256).max);
        kETH.approve(address(protocol), type(uint256).max);
        (uint256 tradeAmount, ) = one.vaultDeposit(address(usdc), mintAmount * count, trader);
        for (uint256 i = 0; i < count; i++) {
            protocol.swapSCDP(SwapArgs(trader, address(one), kETHAddr, tradeAmount / count, 0, pyth.update));
            protocol.swapSCDP(SwapArgs(trader, kETHAddr, address(one), kETH.balanceOf(trader), 0, pyth.update));
        }
    }

    function _cover(uint256 _coverAmount) internal returns (uint256 crAfter, uint256 debtValAfter) {
        protocol.coverSCDP(address(one), _coverAmount, pyth.update);
        return (protocol.getGlobalCollateralRatio(), protocol.getTotalDebtValueSCDP(true));
    }

    function _coverIncentive(uint256 _coverAmount, address _seizeAsset) internal returns (uint256 crAfter, uint256 debtValAfter) {
        protocol.coverWithIncentiveSCDP(address(one), _coverAmount, _seizeAsset, pyth.update);
        return (protocol.getGlobalCollateralRatio(), protocol.getTotalDebtValueSCDP(true));
    }

    function _liquidate(address _repayAsset, uint256 _repayAmount, address _seizeAsset) internal returns (uint256 crAfter, uint256 debtValAfter, uint256 debtAmountAfter) {
        protocol.liquidateSCDP(SCDPLiquidationArgs(_repayAsset, _repayAmount, _seizeAsset), pyth.update);
        return (protocol.getGlobalCollateralRatio(), protocol.getDebtValueSCDP(_repayAsset, true), protocol.getDebtSCDP(_repayAsset));
    }

    function _previewSwap(address _assetIn, address _assetOut, uint256 _amountIn) internal view returns (uint256 amountOut_) {
        (amountOut_, , ) = protocol.previewSwapSCDP(_assetIn, _assetOut, _amountIn);
    }

    function _setETHPrice(uint256 _newPrice) internal {
        ethFeed.setPrice(_newPrice * 1e8);
        JSON.TickerConfig[] memory tickers = JSON.getAssetConfig("test", "test-audit").tickers;
        for (uint256 i = 0; i < tickers.length; i++) {
            if (tickers[i].ticker.equals("ETH")) {
                tickers[i].mockPrice = _newPrice * 1e8;
            }
        }
        updatePythLocal(tickers);
    }
}
