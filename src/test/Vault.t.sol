// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {VaultTestBase} from "test/helpers/VaultTestBase.t.sol";
import {PLog} from "kopio/vm/PLog.s.sol";

// solhint-disable private-vars-leading-underscore
// solhint-disable contract-name-camelcase
// solhint-disable max-states-count

contract VaultTest is VaultTestBase {
    using PLog for *;

    function setUp() public override {
        super.setUp();
    }

    function testDepositsSingleToken() public {
        _deposit(user1, usdc, 1e18);
        assertEq(usdc.balanceOf(address(vone)), 1e18);
        assertEq(vone.balanceOf(user1), 1e18);
    }

    function testFuzzExchangeRateDepositRedeem(uint256 depositAmount, uint256 newUsdcPrice) public {
        depositAmount = bound(depositAmount, 0.001 ether, 100_000_000 ether);
        newUsdcPrice = bound(newUsdcPrice, 0.01e8, 10000e8);

        _deposit(user1, usdc, depositAmount);
        assertEq(usdc.balanceOf(address(vone)), depositAmount, "dep-amount-0");
        assertEq(vone.balanceOf(user1), depositAmount, "vone-bal-0");
        assertEq(vone.exchangeRate(), vone.baseRate(), "t-price-0");

        usdcOracle.setPrice(newUsdcPrice);

        _redeem(user1, usdc, vone.balanceOf(user1));
        assertApproxEqAbs(usdc.balanceOf(user1), depositAmount, 1000, "usdc-bal-1");
        assertEq(vone.exchangeRate(), vone.baseRate(), "t-price-1");

        usdcOracle.setPrice(1e8);
        assertEq(vone.exchangeRate(), vone.baseRate(), "t-price-2");
        _deposit(user1, usdc, depositAmount);
        assertApproxEqAbs(usdc.balanceOf(address(vone)), depositAmount, 1000, "dep-amount-2");
        assertEq(vone.balanceOf(user1), depositAmount, "vone bal-2");
    }

    function testFuzzExchangeRateDepositWithdraw(uint256 depositAmount, uint256 newUsdcPrice) public {
        depositAmount = bound(depositAmount, 0.001 ether, 100_000_000 ether);
        newUsdcPrice = bound(newUsdcPrice, 0.0005e8, 10000e8);

        _deposit(user1, usdc, depositAmount);
        assertEq(usdc.balanceOf(address(vone)), depositAmount, "dep-amount-0");
        assertEq(vone.balanceOf(user1), depositAmount, "vone-bal-0");
        assertEq(vone.exchangeRate(), vone.baseRate(), "t-price-0");

        usdcOracle.setPrice(newUsdcPrice);

        _withdraw(user1, usdc, usdc.balanceOf(address(vone)));
        assertApproxEqAbs(usdc.balanceOf(user1), depositAmount, 1000, "usdc-bal-1");
        assertEq(vone.exchangeRate(), vone.baseRate(), "t-price-1");

        usdcOracle.setPrice(1e8);
        assertEq(vone.exchangeRate(), vone.baseRate(), "t-price-2");
        _deposit(user1, usdc, depositAmount);
        assertApproxEqAbs(usdc.balanceOf(address(vone)), depositAmount, 1000, "dep-amount-2");
        assertEq(vone.balanceOf(user1), depositAmount, "vone bal-2");
    }

    function testDepositsSingleTokenPricing() public {
        usdcOracle.setPrice(1.01e8);
        _deposit(user1, usdc, 500e18);
        _deposit(user2, usdc, 100e18);
        assertEq(usdc.balanceOf(address(vone)), 600e18);
        assertEq(vone.balanceOf(user1), 505.0e18);
        assertEq(vone.balanceOf(user2), 101.0e18);

        usdcOracle.setPrice(0.5e8);

        _redeem(user1, usdc, 505e18);
        _redeem(user2, usdc, 101e18);

        assertEq(usdc.balanceOf(user1), 500e18);
        assertEq(usdc.balanceOf(user2), 100e18);
    }

    function testDepositsMultiToken() public {
        _deposit(user1, usdc, 1e18);
        _deposit(user1, usdt, 1e6);
        _deposit(user1, dai, 1e18);
        assertEq(usdc.balanceOf(address(vone)), 1e18);
        assertEq(usdt.balanceOf(address(vone)), 1e6);
        assertEq(dai.balanceOf(address(vone)), 1e18);
        assertEq(vone.balanceOf(user1), 3e18);
    }

    function testRedeemSingleToken() public {
        assertEq(_deposit(user1, usdc, 1e18), 1e18);
        assertEq(_maxRedeem(user1, usdc), 1e18);
        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(vone.balanceOf(address(vone)), 0);
        assertEq(vone.balanceOf(user1), 0);
    }

    function testRedeemMultiToken() public {
        _deposit(user1, usdc, 1e18);
        _deposit(user1, usdt, 1e6);
        _deposit(user1, dai, 1e18);

        assertEq(_redeem(user1, usdc, 1e18), 1e18);
        assertEq(_redeem(user1, usdt, 1e18), 1e6);
        assertEq(_redeem(user1, dai, 1e18), 1e18);

        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(usdt.balanceOf(user1), 1e6);
        assertEq(dai.balanceOf(user1), 1e18);
        assertEq(vone.balanceOf(user1), 0);
        assertEq(vone.totalSupply(), 0);
        assertEq(vone.totalAssets(), 0);
    }

    function testMaxRedeem() public {
        _deposit(user1, usdc, 1e18);
        _deposit(user1, usdt, 1e6);
        _deposit(user1, dai, 1e18);

        assertEq(_maxRedeem(user1, usdc), 1e18);
        assertEq(_maxRedeem(user1, usdt), 1e6);
        assertEq(_maxRedeem(user1, dai), 1e18);

        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(usdt.balanceOf(user1), 1e6);
        assertEq(dai.balanceOf(user1), 1e18);

        assertEq(vone.balanceOf(user1), 0);
        assertEq(vone.totalSupply(), 0);
        assertEq(vone.totalAssets(), 0);
    }

    function testMaxWithdraw() public {
        _deposit(user1, usdc, 1e18);
        _deposit(user1, usdt, 1e6);
        _deposit(user1, dai, 1e18);
        _logBalances(usdt, "usdt");

        assertEq(_maxWithdraw(user1, usdc), 1e18);
        assertEq(_maxWithdraw(user1, usdt), 1e18); // shares in, not token amount
        assertEq(_maxWithdraw(user1, dai), 1e18);

        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(usdt.balanceOf(user1), 1e6);
        assertEq(dai.balanceOf(user1), 1e18);

        assertEq(vone.balanceOf(user1), 0);
        assertEq(vone.totalSupply(), 0);
        assertEq(vone.totalAssets(), 0);

        _deposit(user1, usdc, 1e18);
        _deposit(user1, usdt, 1e6);

        _setWithdrawFee(usdc, 0.25e4);
        _setWithdrawFee(usdt, 0.25e4);

        assertEq(vone.maxWithdraw(address(usdc)), 0.75e18, "max-usdc");
        assertEq(vone.maxWithdraw(address(usdt)), 0.75e6, "max-usdt");
        assertEq(_maxWithdraw(user1, usdc), 1e18, "withdraw-max-shares-usdc");
        assertEq(_maxWithdraw(user1, usdt), 1e18, "withdraw-max-shares-usdt");
        assertEq(usdt.balanceOf(address(vone)), 0.25e6);
        assertEq(usdc.balanceOf(address(vone)), 0.25e18);
    }

    function testDepositFeePreview() public {
        _setDepositFee(usdc, 0.25e4);

        (uint256 oneOut, uint256 fee) = vone.previewDeposit(address(usdc), 1e18);
        assertEq(fee, 0.25e18, "fee should be 50%");
        assertEq(oneOut, 0.75e18, "one should be 50%");
    }

    function testDepositFee() public {
        _setDepositFee(usdc, 0.25e4);
        usdc.mint(user1, 1e18);

        vm.prank(user1);
        (uint256 oneOut, uint256 fee) = vone.deposit(address(usdc), 1e18, user1);

        assertEq(fee, 0.25e18, "fee should be equal to percentage");
        assertEq(oneOut, 0.75e18, "one out should be reduced according to fees");
        assertEq(vone.balanceOf(user1), 0.75e18, "one balance should equal oneOut");
        assertEq(vone.exchangeRate(), 1e18, "one price should be 1 regardless of fees");
        assertEq(vone.getFees(address(usdc)), 0.25e18, "fee recipient should have some");

        vm.prank(user1);
        vm.expectRevert();
        vone.feeWithdraw(address(usdc));

        _withdrawFees(usdc);
        assertEq(usdc.balanceOf(feeRecipient), 0.25e18, "fees-out");
    }

    function testMintFeePreview() public {
        _setDepositFee(usdc, 0.25e4);

        (uint256 assetsIn, uint256 fee) = vone.previewMint(address(usdc), 1e18);
        assertEq(fee, 0.333333333333333333e18, "fee should be equal to percentage");
        assertEq(assetsIn, 1.333333333333333333e18, "assets in should be mint requested times fee");
    }

    function testMintDeposit() public {
        _setDepositFee(usdt, 10);

        vm.prank(user0);
        usdtOracle.setPrice(0.99249925e8);

        (uint256 assetsIn, uint256 feeMint) = vone.previewMint(address(usdt), 1 ether);

        _mint(user1, usdt, 1 ether);
        assertEq(vone.balanceOf(user1), 1e18, "usdt-mint-bal");
        assertEq(vone.getFees(address(usdt)), feeMint, "usdt-mint-fee");
        assertApproxEqAbs(vone.exchangeRate(), vone.baseRate(), 1e12, "usdt-mint-ex");

        _deposit(user1, usdt, assetsIn);
        assertApproxEqAbs(vone.exchangeRate(), vone.baseRate(), 1e12, "usdt-dep-ex");
        assertEq(vone.getFees(address(usdt)), feeMint * 2, "usdt-mint-fee");
        assertEq(vone.balanceOf(user1), 2e18, "usdt-dep-bal");
    }

    function testMintFee() public {
        _setDepositFee(usdc, 0.25e4);

        usdc.mint(user1, 1.333333333333333333e18);

        vm.startPrank(user1);
        (uint256 assetsIn, uint256 fee) = vone.mint(address(usdc), 1e18, user1);
        vm.stopPrank();

        assertEq(fee, 0.333333333333333333e18, "fee should be equal to percentage");
        assertEq(assetsIn, 1.333333333333333333e18, "one out should be greater than mint requested times fee");
        assertEq(vone.exchangeRate(), 1e18, "one price should be 1 regardless of fees");
        assertEq(vone.getFees(address(usdc)), 0.333333333333333333e18, "fee recipient should have some USDC");
        assertEq(usdc.balanceOf(address(vone)), 1.333333333333333333e18, "vone should have 1 USDC + fees");
    }

    function testWithdrawFeePreview() public {
        _deposit(user1, usdc, 2e18);
        _setWithdrawFee(usdc, 0.25e4);

        uint256 expectedFee = 0.333333333333333333e18;
        (uint256 sharesIn, uint256 fee) = vone.previewWithdraw(address(usdc), 1e18);
        assertEq(fee, expectedFee, "fee should be equal to percentage");
        assertEq(sharesIn, 1e18 + expectedFee, "assets in should be adjusted by fees");
    }

    function testCannotDeposit0() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vone.deposit(address(usdc), 0, user1);
        vm.stopPrank();
    }

    function testCannotMint0() public {
        vm.startPrank(user1);
        vm.expectRevert();
        vone.mint(address(usdc), 0, user1);
        vm.stopPrank();
    }

    function testCannotWithdraw0() public {
        _deposit(user1, usdc, 1e18);
        vm.startPrank(user1);
        vm.expectRevert();
        vone.withdraw(address(usdc), 0, user1, user1);
        vm.stopPrank();
    }

    function testCannotRedeem() public {
        _deposit(user1, usdc, 1e18);
        vm.startPrank(user1);
        vm.expectRevert();
        vone.redeem(address(usdc), 0, user1, user1);
        vm.stopPrank();
    }

    function testCanWithdrawRounding() public {
        _setWithdrawFee(usdc, 0.25e4);

        uint256 expectedFee = 0.333333333333333333e18;
        _deposit(user1, usdc, 1e18 + expectedFee);

        vm.startPrank(user1);
        (uint256 sharesIn, uint256 fee) = vone.withdraw(address(usdc), 1e18, user1, user1);
        vm.stopPrank();
        assertEq(sharesIn, 1e18 + expectedFee, "assets in should equal full amount");
        assertEq(fee, expectedFee, "fee should be equal to percentage");
    }

    function testCanRedeemRounding() public {
        _setWithdrawFee(usdc, 0.25e4);

        uint256 expectedFee = 0.333333333333333333e18;
        _deposit(user1, usdc, 1e18 + expectedFee);

        vm.startPrank(user1);
        (uint256 assetsOut, uint256 fee) = vone.redeem(address(usdc), 1e18 + expectedFee, user1, user1);
        vm.stopPrank();
        assertEq(fee, expectedFee, "fee should be equal to percentage");
        assertEq(assetsOut, 1e18, "assets in should be adjusted by fees");
    }

    function testWithdrawFee() public {
        uint256 expectedFee = 0.5e18;
        _deposit(user1, usdc, 2e18);

        _setWithdrawFee(usdc, 0.25e4);

        vm.prank(user1);
        (uint256 sharesIn, uint256 fee) = vone.withdraw(address(usdc), 1.5e18, user1, user1);

        assertEq(fee, expectedFee, "fee should be equal to percentage");

        assertEq(sharesIn, 2e18, "one required should be greater than withdrawal amount requested times fee");
        assertEq(vone.exchangeRate(), 1e18, "one price should be 1 regardless of fees");
        assertEq(usdc.balanceOf(user1), 1.5e18, "user should have some USDC");
        assertEq(vone.getFees(address(usdc)), expectedFee, "fee recipient should have some USDC");
        assertEq(usdc.balanceOf(address(vone)), expectedFee, "vone should have fees USDC");
        assertEq(vone.totalSupply(), 0, "vone should have 0 USDC");

        _withdrawFees(usdc);
        assertEq(usdc.balanceOf(feeRecipient), expectedFee, "fee recipient should have fees USDC");
    }

    function testRedeemFeePreview() public {
        _setWithdrawFee(usdc, 0.25e4);

        (uint256 assetsOut, uint256 fee) = vone.previewRedeem(address(usdc), 1e18);
        assertEq(fee, 0.25e18, "fee should be equal to percentage");
        assertEq(assetsOut, 0.75e18, "assets out should be less than shares requested");
    }

    function testRedeemFee() public {
        _deposit(user1, usdc, 1e18);

        _setWithdrawFee(usdc, 0.25e4);

        vm.startPrank(user1);
        (uint256 assetsOut, uint256 fee) = vone.redeem(address(usdc), 1e18, user1, user1);
        vm.stopPrank();

        assertEq(fee, 0.25e18, "fee should be equal to percentage");
        assertEq(assetsOut, 0.75e18, "assetsOut should be less than shares burned");
        assertEq(usdc.balanceOf(user1), 0.75e18, "usdc balance should be equal to assetsOut");
        assertEq(vone.exchangeRate(), 1e18, "one price should be 1 regardless of fees");
        assertEq(vone.getFees(address(usdc)), 0.25e18, "fee recipient should have some USDC");
        assertEq(usdc.balanceOf(address(vone)), 0.25e18, "vone should have fees USDC");
        assertEq(vone.totalSupply(), 0, "vone should have 0 USDC");
    }

    function testDepositWithdrawFee() public {
        _setFees(usdc, 0.25e4, 0.25e4);

        uint256 oneOut = _deposit(user1, usdc, 1e18);

        assertEq(oneOut, 0.75e18);

        vm.prank(user1);
        (uint256 assetsOut, ) = vone.redeem(address(usdc), oneOut, user1, user1);

        uint256 expectedAssetsOut = 0.5625e18;
        assertEq(assetsOut, expectedAssetsOut, "assetsOut should be reduced by both fees");

        // assertEq(fee, 0.25e18, "fee should be equal to percentage");
        assertEq(usdc.balanceOf(user1), assetsOut, "usdc balance should be equal to assetsOut");
        assertEq(vone.exchangeRate(), 1e18, "one price should be 1 regardless of fees");
        assertEq(vone.getFees(address(usdc)), 1e18 - expectedAssetsOut, "fee recipient should have some USDC");
        assertEq(usdc.balanceOf(address(vone)), 1e18 - expectedAssetsOut, "vone should have fees USDC");
        assertEq(vone.totalSupply(), 0, "vone should have 0 USDC");
    }

    function testMintRedeemFee() public {
        _setFees(usdc, 0.25e4, 0.25e4);
        usdc.mint(user1, 1.333333333333333333e18);

        vm.startPrank(user1);

        uint256 expectedMintFee = 0.333333333333333333e18;
        uint256 expectedRedeemFee = 0.25e18;
        (uint256 assetsIn, uint256 feeMint) = vone.mint(address(usdc), 1e18, user1);
        assertEq(assetsIn, 1e18 + expectedMintFee, "assetsIn ");

        assertEq(feeMint, expectedMintFee, "mintFee should be equal to percentage");

        (uint256 assetsOut, uint256 feeRedeem) = vone.redeem(address(usdc), 1e18, user1, user1);
        vm.stopPrank();

        uint256 expectedAssetsOut = 1e18 - expectedRedeemFee;
        assertEq(assetsOut, expectedAssetsOut, "assetsOut should be reduced by both fees");

        assertEq(feeRedeem, expectedRedeemFee, "redeemFee should be equal to percentage");
        assertEq(usdc.balanceOf(user1), assetsOut, "usdc balance should be equal to assetsOut");
        assertEq(vone.exchangeRate(), 1e18, "one price should be 1 regardless of fees");
        assertEq(vone.getFees(address(usdc)), feeRedeem + expectedMintFee, "fee recipient should have some USDC");
        assertEq(usdc.balanceOf(address(vone)), feeRedeem + expectedMintFee, "vone should have 0 USDC");
        assertEq(vone.totalSupply(), 0, "vone should have 0 USDC");
    }

    function testDepositMintPreviewFee() public {
        _setFees(usdc, 0.25e4, 0.25e4);

        uint256 oneOut = 1e18;
        (uint256 assetsIn, uint256 mintFee) = vone.previewMint(address(usdc), oneOut);

        (uint256 sharesOut, uint256 depositFee) = vone.previewDeposit(address(usdc), assetsIn);
        assertEq(sharesOut, oneOut, "oneOut should be -1 to sharesOut");
        assertEq(depositFee, mintFee, "depositFee should be same as mintFee");
        assertEq(assetsIn, sharesOut + depositFee, "depositFee should be same as mintFee");
    }

    function testDepositRedeemFee() public {
        _setFees(usdc, 0.25e4, 0.25e4);
        usdc.mint(user1, 1.333333333333333333e18);

        vm.startPrank(user1);

        uint256 expectedDepositFee = 0.333333333333333333e18;
        uint256 expectedRedeemFee = 0.25e18;

        uint256 depositAmount = 1e18 + expectedDepositFee;

        (uint256 sharesOut, uint256 feeDeposit) = vone.deposit(address(usdc), depositAmount, user1);
        assertEq(sharesOut, 1 ether, "sharesOut should be 1 ether");
        assertEq(feeDeposit, expectedDepositFee, "feeDeposit should equal expected");
        (uint256 assetsOut, uint256 feeRedeem) = vone.redeem(address(usdc), sharesOut, user1, user1);

        vm.stopPrank();
        assertEq(feeRedeem, expectedRedeemFee, "redeem fee not correct");
        uint256 expectedAssetsOut = depositAmount - feeDeposit - feeRedeem;
        assertEq(assetsOut, expectedAssetsOut, "assetsOut should be reduced by both fees");

        assertEq(usdc.balanceOf(user1), assetsOut, "usdc balance should be equal to assetsOut");
        assertEq(vone.exchangeRate(), 1e18, "one price should be 1 regardless of fees");
        assertEq(vone.getFees(address(usdc)), feeDeposit + feeRedeem, "fee recipient should have some USDC");
        assertEq(usdc.balanceOf(address(vone)), feeDeposit + feeRedeem, "vone should have 0 USDC");
        assertEq(vone.totalSupply(), 0, "vone should have 0 USDC");
    }

    function testWithdrawMultiToken() public {
        _deposit(user1, usdc, 1e18);
        _deposit(user1, usdt, 1e6);
        _deposit(user1, dai, 1e18);

        assertEq(_withdraw(user1, usdc, 1e18), 1e18);
        assertEq(_withdraw(user1, usdt, 1e6), 1e18);
        assertEq(_withdraw(user1, dai, 1e18), 1e18);

        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(usdt.balanceOf(user1), 1e6);
        assertEq(dai.balanceOf(user1), 1e18);
        assertEq(vone.balanceOf(user1), 0);
    }

    function testDepositAfterPriceDownSameToken() public {
        _deposit(user1, usdc, 1e18);
        usdcOracle.setPrice(0.5e8);
        _deposit(user2, usdc, 1e18);

        assertEq(vone.balanceOf(user1), 1e18);
        assertEq(vone.balanceOf(user2), 1e18);
    }

    function testMintAfterPriceDownSameToken() public {
        _mint(user1, usdc, 1e18);
        usdcOracle.setPrice(0.5e8);
        _mint(user2, usdc, 1e18);

        assertEq(vone.balanceOf(user1), 1e18);
        assertEq(vone.balanceOf(user2), 1e18);
    }

    function testDepositAfterPriceDownDifferentToken() public {
        _deposit(user1, usdc, 1e18);
        usdcOracle.setPrice(0.5e8);
        _deposit(user2, usdt, 1e6);

        assertEq(vone.balanceOf(user1), 1e18);
        assertEq(vone.balanceOf(user2), 2e18);
    }

    function testMintAfterPriceDownDifferentToken() public {
        _mint(user1, usdc, 1e18);
        usdcOracle.setPrice(0.5e8);

        _mint(user2, usdt, 1e18);

        assertEq(vone.balanceOf(user1), 1e18);
        assertEq(vone.balanceOf(user2), 1e18);

        assertEq(usdt.balanceOf(user2), 0);
        assertEq(usdt.balanceOf(address(vone)), 0.5e6);
    }

    function testRedeemAfterPriceDownSameToken() public {
        _deposit(user1, usdc, 1e18);
        usdcOracle.setPrice(0.5e8);
        _deposit(user2, usdc, 1e18);

        _redeem(user1, usdc, 1e18);
        _maxRedeem(user2, usdc);

        assertEq(vone.balanceOf(user1), 0);
        assertEq(vone.balanceOf(user2), 0);
        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(usdc.balanceOf(user2), 1e18);
    }

    function testRedeemAfterPriceDownDifferentToken() public {
        _deposit(user1, usdc, 1e18);
        usdcOracle.setPrice(0.5e8);
        _deposit(user2, usdt, 1e6);
        _maxRedeem(user1, usdc);
        _maxRedeem(user2, usdt);
        assertEq(vone.balanceOf(user1), 0);
        assertEq(vone.balanceOf(user2), 0);
        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(usdt.balanceOf(user2), 1e6);
    }

    function testWithdrawAfterPriceDownDifferentToken() public {
        _deposit(user1, usdc, 1e18);
        usdcOracle.setPrice(0.5e8);
        _deposit(user2, usdt, 1e6);
        _withdraw(user1, usdc, 1e18);
        _withdraw(user2, usdt, 1e6);
        assertEq(vone.balanceOf(user1), 0);
        assertEq(vone.balanceOf(user2), 0);
        assertEq(usdc.balanceOf(user1), 1e18);
        assertEq(usdt.balanceOf(user2), 1e6);
    }

    function testMaxDeposit() public {
        _deposit(user1, usdc, 1e18);
        _deposit(user1, usdt, 1e6);
        _deposit(user1, dai, 1e18);

        assertEq(vone.maxDeposit(address(usdc)), type(uint248).max - 1e18);
        assertEq(vone.maxDeposit(address(usdt)), type(uint248).max - 1e6);
        assertEq(vone.maxDeposit(address(dai)), type(uint248).max - 1e18);
    }

    function testMaxMint() public {
        usdc.mint(user1, 1e18);
        usdt.mint(user1, 2e6);
        dai.mint(user1, 1e18);
        _deposit(user1, usdc, 1e18);
        _deposit(user1, usdt, 1e6);
        _deposit(user1, dai, 1e18);

        assertEq(vone.maxMint(address(usdc), user1), 1e18);
        assertEq(vone.maxMint(address(usdt), user1), 2e18);
        assertEq(vone.maxMint(address(dai), user1), 1e18);
    }

    function testCantDepositOverMaxDeposit() public {
        vm.startPrank(user0);
        uint248 maxDeposits = 1 ether;
        vone.setAssetLimits(address(usdc), maxDeposits, false);
        uint256 depositAmount = maxDeposits + 1;
        usdc.mint(user1, depositAmount);
        vm.stopPrank();

        vm.startPrank(user1);

        vm.expectRevert();
        vone.deposit(address(usdc), depositAmount, user1);

        vm.expectRevert();
        vone.mint(address(usdc), depositAmount, user1);
        vm.stopPrank();
    }
}
