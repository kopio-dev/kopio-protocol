// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

// solhint-disable no-console, state-visibility, var-name-mixedcase, avoid-low-level-calls, max-states-count

import {ShortAssert} from "kopio/vm/ShortAssert.t.sol";
import {Log, Utils} from "kopio/vm/VmLibs.s.sol";
import {Tested} from "kopio/vm/Tested.t.sol";
import {Asset} from "common/Types.sol";
import {Deploy} from "scripts/deploy/Deploy.s.sol";
import {ERC20Mock, MockOracle} from "mocks/Mocks.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {IKopio} from "interfaces/IKopio.sol";
import {TickerConfig, Config} from "scripts/deploy/JSON.s.sol";
import {Enums} from "common/Constants.sol";
import {SCDPLiquidationArgs, SCDPRepayArgs, SCDPWithdrawArgs, SwapArgs} from "common/Args.sol";
import {id, err} from "common/Errors.sol";

contract SCDPTest is err, Tested, Deploy {
    using ShortAssert for *;
    using Log for *;
    using Utils for *;
    using Deployed for *;

    ERC20Mock usdc;
    IKopio kETH;
    IKopio kJPY;
    IKopio kTSLA;
    MockOracle ethFeed;
    Asset kETHConfig;
    Asset oneConfig;
    uint256 fee_ONE_kETH;
    uint256 fee_kETH_ONE;

    address admin;
    address deployer;
    address feeRecipient;
    address liquidator;
    address council;

    address kETHAddr;
    address oneAddr;
    TickerConfig[] tickerCfg;

    function setUp() public mnemonic("MNEMONIC_KOPIO") users(getAddr(11), getAddr(22), getAddr(33)) {
        Config memory json = Deploy.deployTest("MNEMONIC_KOPIO", "test-clean", 0);

        for (uint256 i; i < json.assets.tickers.length; i++) {
            tickerCfg.push(json.assets.tickers[i]);
        }
        ethFeed = MockOracle(protocol.getOracleOfTicker("ETH", Enums.OracleType.Chainlink).feed);

        // for price updates
        vm.deal(address(protocol), 1 ether);

        deployer = getAddr(0);
        admin = json.params.common.admin;
        feeRecipient = json.params.common.treasury;
        liquidator = getAddr(777);

        kETHAddr = ("kETH").cached();
        oneAddr = address(one);
        usdc = ERC20Mock(("USDC").cached());
        kETH = IKopio(kETHAddr);
        kJPY = IKopio(("kJPY").cached());
        kTSLA = IKopio(("kTSLA").cached());
        kETHConfig = ("kETH").cachedAsset();
        oneConfig = ("ONE").cachedAsset();
        fee_ONE_kETH = oneConfig.swapInFee + kETHConfig.swapOutFee;
        fee_kETH_ONE = kETHConfig.swapInFee + oneConfig.swapOutFee;

        _approvals(getAddr(0));
        _approvals(user0);
        _approvals(user1);
        _approvals(user2);
        _approvals(liquidator);

        prank(0);
        usdc.mint(user0, 1000e6);
        (council = protocol.getRoleMember(keccak256("kopio.role.safety"), 0)).notEq(address(0), "council");
        one.transfer(user0, 2000e18);
    }

    modifier withDeposits() {
        _poolDeposit(deployer, address(usdc), 10000e6);
        _poolDeposit(deployer, oneAddr, 10000e18);
        _;
    }

    function testSCDPSetup() public {
        protocol.getEffectiveSDIDebt().eq(0, "debt should be 0");
        protocol.totalSDI().eq(0, "total supply should be 0");
        protocol.getAssetIndexesSCDP(address(usdc)).currFeeIndex.eq(1e27);
        protocol.getAssetIndexesSCDP(address(usdc)).currFeeIndex.eq(1e27);
        protocol.getAssetIndexesSCDP(oneAddr).currLiqIndex.eq(1e27);
        protocol.getAssetIndexesSCDP(oneAddr).currLiqIndex.eq(1e27);
        oneConfig.isCoverAsset.eq(true);
    }

    function testSCDPDeposit() public {
        _poolDeposit(user0, address(usdc), 1000e6);
        usdc.balanceOf(user0).eq(0, "usdc balance should be 0");
        usdc.balanceOf(address(protocol)).eq(1000e6, "usdc-bal-protocol");

        protocol.totalSDI().eq(0, "total supply should be 0");
        protocol.getTotalCollateralValueSCDP(true).eq(1000e8, "collateral value should be 1000");
    }

    function testDepositModified() public pranked(user0) {
        _poolDeposit(deployer, oneAddr, 10000e18);

        _swap(user0, oneAddr, 1000e18, address(kETH));

        _setETHPrice(18000e8);
        _liquidate(address(kETH), 0.1e18, oneAddr);

        uint256 depositsBefore = protocol.getAccountDepositSCDP(deployer, oneAddr);
        _poolDeposit(deployer, oneAddr, 1000e18);
        protocol.getAccountDepositSCDP(deployer, oneAddr).eq(depositsBefore + 1000e18, "depositsAfter");

        _liquidate(address(kETH), 0.1e18, oneAddr);

        uint256 depositsAfter2 = protocol.getAccountDepositSCDP(deployer, oneAddr);
        _poolDeposit(deployer, oneAddr, 1000e18);
        protocol.getAccountDepositSCDP(deployer, oneAddr).eq(depositsAfter2 + 1000e18, "depositsAfter2");

        _setETHPrice(2000e8);
        _poolWithdraw(deployer, oneAddr, 1000e18);
        protocol.getAccountDepositSCDP(deployer, oneAddr).eq(depositsAfter2, "withdrawAfter");

        _poolDeposit(deployer, oneAddr, 1000e18);
        protocol.getAccountDepositSCDP(deployer, oneAddr).eq(depositsAfter2 + 1000e18, "depositsAfter3");

        _setETHPrice(25000e8);
        _liquidate(address(kETH), 0.1e18, oneAddr);

        uint256 depositsAfter3 = protocol.getAccountDepositSCDP(deployer, oneAddr);
        _setETHPrice(2000e8);
        _poolWithdraw(deployer, oneAddr, 1000e18);
        protocol.getAccountDepositSCDP(deployer, oneAddr).eq(depositsAfter3 - 1000e18, "withdrawAfter2");

        _poolDeposit(deployer, oneAddr, 1000e18);
        protocol.getAccountDepositSCDP(deployer, oneAddr).eq(depositsAfter3, "depositsAfter4");
        _poolDeposit(user0, oneAddr, 500e18);
        protocol.getAccountDepositSCDP(user0, oneAddr).eq(500e18, "depositsAfter5");
        one.balanceOf(user0).eq(500e18, "one balance should be 500");

        _poolWithdraw(user0, oneAddr, 500e18);
        protocol.getAccountDepositSCDP(user0, oneAddr).eq(0, "depositsAfter6");
        one.balanceOf(user0).eq(1000e18, "one balance should be 1000");

        _poolDeposit(user0, oneAddr, 500e18);
        protocol.getAccountDepositSCDP(user0, oneAddr).eq(500e18, "depositsAfter7");

        _setETHPrice(25000e8);
        _liquidate(address(kETH), 0.05e18, oneAddr);

        uint256 depositAfter4 = protocol.getAccountDepositSCDP(user0, oneAddr);
        _poolDeposit(user0, oneAddr, 100e18);
        protocol.getAccountDepositSCDP(user0, oneAddr).eq(depositAfter4 + 100e18, "depositsAfter8");

        _setETHPrice(2000e8);
        _poolWithdraw(user0, oneAddr, depositAfter4 + 100e18);
        protocol.getAccountDepositSCDP(user0, oneAddr).eq(0, "depositsAfter9");
    }

    function testSCDPWithdraw() public {
        _poolDeposit(user0, address(usdc), 1000e6);
        _poolWithdraw(user0, address(usdc), 1000e6);
        protocol.getTotalCollateralValueSCDP(true).eq(0, "collateral value should be 0");
        usdc.balanceOf(user0).eq(1000e6, "usdc balance should be 1000");
        usdc.balanceOf(address(protocol)).eq(0, "usdc balance should be 0");
    }

    function testSCDPSwap() public withDeposits pranked(user0) {
        _poolDeposit(user0, oneAddr, 1000e18);

        protocol.getSwapDepositsSCDP(oneAddr).eq(0, "swap deposits should be 0");
        uint256 oneBalBefore = one.balanceOf(address(protocol));
        (uint256 amountOut, uint256 feesDistributed, uint256 feesToProtocol) = protocol.previewSwapSCDP(oneAddr, address(kETH), 1000e18);
        _swap(user0, oneAddr, 1000e18, address(kETH));

        protocol.getDebtSCDP(address(kETH)).eq(amountOut, "debt should be amountOut");
        uint256 swapDeposits = (1000e18) - (1000e18).pmul(fee_ONE_kETH);
        protocol.getSwapDepositsSCDP(oneAddr).eq(swapDeposits, "swap deposits");
        kETH.balanceOf(user0).eq(amountOut, "amountOut");

        uint256 totalFees = feesDistributed + feesToProtocol;
        totalFees.gt(0, "totalFees should be > 0");

        uint256 protocolFeePct = oneConfig.protocolFeeShareSCDP + kETHConfig.protocolFeeShareSCDP;
        feesToProtocol.eq(totalFees.pmul(protocolFeePct), "feesToProtocol");
        feesDistributed.eq(totalFees.pmul(1e4 - protocolFeePct), "feesDistributed");

        one.balanceOf(feeRecipient).eq(feesToProtocol, "one feeRecipient");

        feesDistributed.gt(0, "feesDistributed should be > 0");
        (one.balanceOf(address(protocol)) - swapDeposits - oneBalBefore).eq(feesDistributed, "one feesDistributed");
    }

    function testSCDPSwapFees() public {
        prank(deployer);
        one.transfer(user0, 4000e18);
        one.transfer(user1, 20000e18);

        _poolDeposit(deployer, oneAddr, 5000e18);
        (, uint256 feesDistributed, ) = protocol.previewSwapSCDP(oneAddr, address(kETH), 1000e18);

        _swap(user0, oneAddr, 1000e18, address(kETH));

        uint256 fees = protocol.getAccountFeesSCDP(deployer, oneAddr);
        fees.eq(feesDistributed, "feesDistributed-1");

        _poolDeposit(deployer, oneAddr, 5000e18);
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(0, "feesDistributed");

        _swap(user0, oneAddr, 1000e18, address(kETH));
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed, "feesDistributed2");

        _swap(user0, oneAddr, 1000e18, address(kETH));
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed * 2, "feesDistributed3");

        uint256 fees3 = feesDistributed * 3;
        _swap(user0, oneAddr, 1000e18, address(kETH));
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(fees3, "feesDistributed4");

        _poolWithdraw(deployer, oneAddr, 1000e18);
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(0, "feesDistributed5");

        _poolDeposit(user1, oneAddr, 9000e18);
        _swap(user0, oneAddr, 1000e18, address(kETH));

        uint256 halfFees = feesDistributed / 2;
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(halfFees, "feesDistributed6");
        protocol.getAccountFeesSCDP(user1, oneAddr).eq(halfFees, "feesDistributed7");

        _swap(user0, oneAddr, 1000e18, address(kETH));

        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed, "feesDistributed8");
        protocol.getAccountFeesSCDP(user1, oneAddr).eq(feesDistributed, "feesDistributed9");
    }

    function testSCDPSwapFeesLiq() public {
        prank(deployer);
        one.transfer(user0, 5000e18);
        one.transfer(user1, 20000e18);

        _poolDeposit(deployer, oneAddr, 5000e18);
        (, uint256 feesDistributed, ) = protocol.previewSwapSCDP(oneAddr, address(kETH), 1000e18);

        _swap(user0, oneAddr, 1000e18, address(kETH));
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed, "feesDistributed-1");

        _poolDeposit(deployer, oneAddr, 5000e18);
        _setETHPrice(18000e8);
        _liquidate(address(kETH), 0.1e18, oneAddr);

        uint256 fees = protocol.getAccountFeesSCDP(deployer, oneAddr);
        fees.eq(0, "feesDistributed");

        _setETHPrice(2000e8);
        _swap(user0, oneAddr, 1000e18, address(kETH));
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed, "feesDistributed2");

        _poolDeposit(deployer, oneAddr, 10000e18);
        _swap(user0, oneAddr, 1000e18, address(kETH));
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed, "feesDistributed3");

        _swap(user0, oneAddr, 1000e18, address(kETH));
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed * 2, "feesDistributed4");

        uint256 fees3 = feesDistributed * 3;
        _swap(user0, oneAddr, 1000e18, address(kETH));
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(fees3, "feesDistributed5");

        _setETHPrice(18000e8);
        _liquidate(address(kETH), 0.1e18, oneAddr);

        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(fees3, "feesDistributed5");

        _setETHPrice(2000e8);
        _poolWithdraw(deployer, oneAddr, 1000e18);
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(0, "feesDistributed5");

        _poolDeposit(deployer, oneAddr, 20000e18 - protocol.getAccountDepositSCDP(deployer, oneAddr));
        _poolDeposit(user1, oneAddr, 20000e18);

        _swap(user0, oneAddr, 1000e18, address(kETH));
        uint256 halfFees = feesDistributed / 2;
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(halfFees, "feesDistributed6");
        protocol.getAccountFeesSCDP(user1, oneAddr).eq(halfFees, "feesDistributed7");

        _swap(user0, oneAddr, 1000e18, address(kETH));

        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed, "feesDistributed8");
        protocol.getAccountFeesSCDP(user1, oneAddr).eq(feesDistributed, "feesDistributed9");
    }

    function testClaimFeeGas() public {
        prank(deployer);
        _poolDeposit(deployer, oneAddr, 50000e18);
        _swapAndLiquidate(75, 1000e18, 0.01e18);

        uint256 fees = protocol.getAccountFeesSCDP(deployer, oneAddr);
        uint256 oneBalBefore = one.balanceOf(deployer);
        uint256 checkpoint = gasleft();
        protocol.claimFeesSCDP(deployer, oneAddr, deployer);
        uint256 used = checkpoint - gasleft();
        used.gt(50000, "gas-used-gt"); // warm
        used.lt(150000, "gas-used-lt");

        (one.balanceOf(deployer) - oneBalBefore).eq(fees, "received-fees");
    }

    function testClaimFeeGasNoSwaps() public {
        prank(deployer);
        _poolDeposit(deployer, oneAddr, 50000e18);
        (, uint256 feesDistributed, ) = protocol.previewSwapSCDP(oneAddr, address(kETH), 1000e18);

        protocol.swapSCDP(SwapArgs(getAddr(0), oneAddr, kETHAddr, 1000e18, 0, pyth.update));
        _liquidate(75, 1000e18, 0.01e18);

        uint256 oneBalBefore = one.balanceOf(deployer);
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(feesDistributed, "feesDistributed");
        uint256 checkpoint = gasleft();
        protocol.claimFeesSCDP(deployer, oneAddr, deployer);
        uint256 used = checkpoint - gasleft();
        used.gt(50000, "gas-used-gt"); // warm
        used.lt(150000, "gas-used-lt");
        (one.balanceOf(deployer) - oneBalBefore).eq(feesDistributed, "received-fees");
    }

    function testEmergencyWithdraw() public {
        prank(deployer);

        _poolDeposit(deployer, oneAddr, 50000e18);
        _swapAndLiquidate(75, 1000e18, 0.01e18);

        uint256 fees = protocol.getAccountFeesSCDP(deployer, oneAddr);
        fees.gt(0, "fees");
        uint256 oneBalBefore = one.balanceOf(deployer);
        protocol.emergencyWithdrawSCDP(SCDPWithdrawArgs(deployer, oneAddr, 1000e18, deployer), pyth.update);

        (one.balanceOf(deployer) - oneBalBefore).eq(1000e18, "received-withdraw");
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(0, "fees-after");
    }

    function testSCDPGas() public withDeposits pranked(user0) {
        bool success;
        uint256 amount = 1000e18;

        bytes memory depositData = abi.encodeWithSelector(protocol.depositSCDP.selector, user0, oneAddr, amount);

        uint256 gasDeposit = gasleft();
        (success, ) = address(protocol).call(depositData);
        (gasDeposit - gasleft()).clg("gasPoolDeposit");
        require(success, "!success pool deposit");

        bytes memory withdrawData = abi.encodeWithSelector(protocol.withdrawSCDP.selector, SCDPWithdrawArgs(user0, oneAddr, amount, user0), pyth.update);
        uint256 gasWithdraw = gasleft();
        (success, ) = address(protocol).call(withdrawData);
        (gasWithdraw - gasleft()).clg("gasPoolWithdraw");

        require(success, "!success pool withdraw");

        (success, ) = address(protocol).call(depositData);

        bytes memory swapData = abi.encodeWithSelector(protocol.swapSCDP.selector, SwapArgs(user0, oneAddr, address(kETH), amount, 0, pyth.update));
        uint256 gasSwap = gasleft();
        (success, ) = address(protocol).call(swapData);
        (gasSwap - gasleft()).clg("gasPoolSwap");

        require(success, "!success pool swap 1");

        bytes memory swapData2 = abi.encodeWithSelector(protocol.swapSCDP.selector, SwapArgs(user0, address(kETH), oneAddr, kETH.balanceOf(user0), 0, pyth.update));

        uint256 gasSwap2 = gasleft();
        (success, ) = address(protocol).call(swapData2);
        (gasSwap2 - gasleft()).clg("gasPoolSwap2");

        require(success, "!success pool swap 2");

        bytes memory swapData3 = abi.encodeWithSelector(protocol.swapSCDP.selector, SwapArgs(user0, oneAddr, address(kETH), one.balanceOf(user0), 0, pyth.update));
        uint256 gasSwap3 = gasleft();
        (success, ) = address(protocol).call(swapData3);
        (gasSwap3 - gasleft()).clg("gasPoolSwap3");
    }

    function testSCDPDeposit_Paused() public {
        // Pause SCDPDeposit for USDC
        _toggleActionPaused(address(usdc), Enums.Action.SCDPDeposit, true);

        prank(user0);
        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(address(usdc)), Enums.Action.SCDPDeposit));
        protocol.depositSCDP(user0, address(usdc), 1000e6);

        // Unpause SCDPDeposit for USDC
        _toggleActionPaused(address(usdc), Enums.Action.SCDPDeposit, false);

        _poolDeposit(user0, address(usdc), 1000e6);
        usdc.balanceOf(user0).eq(0, "usdc balance should be 0");
        usdc.balanceOf(address(protocol)).eq(1000e6, "usdc-bal-protocol");
    }

    function testSCDPWithdraw_Paused() public {
        _poolDeposit(user0, address(usdc), 1000e6);

        // Pause SCDPWithdraw for USDC
        _toggleActionPaused(address(usdc), Enums.Action.SCDPWithdraw, true);

        prank(user0);
        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(address(usdc)), Enums.Action.SCDPWithdraw));
        protocol.withdrawSCDP(SCDPWithdrawArgs(user0, address(usdc), 1000e6, user0), pyth.update);

        // Unpause SCDPWithdraw for USDC
        _toggleActionPaused(address(usdc), Enums.Action.SCDPWithdraw, false);

        _poolWithdraw(user0, address(usdc), 1000e6);
        protocol.getTotalCollateralValueSCDP(true).eq(0, "collateral value should be 0");
        usdc.balanceOf(user0).eq(1000e6, "usdc balance should be 1000");
        usdc.balanceOf(address(protocol)).eq(0, "usdc balance should be 0");
    }

    function testSCDPEmergencyWithdraw_Paused() public {
        prank(deployer);

        _poolDeposit(deployer, oneAddr, 50000e18);
        _swapAndLiquidate(75, 1000e18, 0.01e18);

        uint256 fees = protocol.getAccountFeesSCDP(deployer, oneAddr);
        fees.gt(0, "fees");
        uint256 oneBalBefore = one.balanceOf(deployer);
        _toggleActionPaused(oneAddr, Enums.Action.SCDPWithdraw, true);
        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(oneAddr), Enums.Action.SCDPWithdraw));
        protocol.emergencyWithdrawSCDP(SCDPWithdrawArgs(deployer, oneAddr, 1000e18, deployer), pyth.update);

        _toggleActionPaused(oneAddr, Enums.Action.SCDPWithdraw, false);
        protocol.emergencyWithdrawSCDP(SCDPWithdrawArgs(deployer, oneAddr, 1000e18, deployer), pyth.update);
        (one.balanceOf(deployer) - oneBalBefore).eq(1000e18, "received-withdraw");
        protocol.getAccountFeesSCDP(deployer, oneAddr).eq(0, "fees-after");
    }

    function test_claimFees_Paused() public {
        prank(deployer);
        _poolDeposit(deployer, oneAddr, 50000e18);
        _swapAndLiquidate(75, 1000e18, 0.01e18);

        uint256 fees = protocol.getAccountFeesSCDP(deployer, oneAddr);
        uint256 oneBalBefore = one.balanceOf(deployer);

        _toggleActionPaused(oneAddr, Enums.Action.SCDPFeeClaim, true);
        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(oneAddr), Enums.Action.SCDPFeeClaim));
        protocol.claimFeesSCDP(deployer, oneAddr, deployer);

        _toggleActionPaused(oneAddr, Enums.Action.SCDPFeeClaim, false);
        protocol.claimFeesSCDP(deployer, oneAddr, deployer);

        (one.balanceOf(deployer) - oneBalBefore).eq(fees, "received-fees");
    }

    function test_liquidateSCPD_Paused() public {
        _poolDeposit(deployer, oneAddr, 10000e18);
        _swap(user0, oneAddr, 1000e18, address(kETH));

        _setETHPrice(18000e8);
        _toggleActionPaused(address(kETH), Enums.Action.SCDPLiquidation, true);
        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(address(kETH)), Enums.Action.SCDPLiquidation));
        _liquidate(address(kETH), 0.1e18, oneAddr);

        _toggleActionPaused(address(kETH), Enums.Action.SCDPLiquidation, false);
        _liquidate(address(kETH), 0.1e18, oneAddr);
    }

    function test_repaySCPD_Paused() public {
        _poolDeposit(deployer, oneAddr, 10000e18);
        _swap(user0, oneAddr, 1000e18, address(kETH));

        _toggleActionPaused(address(kETH), Enums.Action.SCDPRepay, true);

        assertGt(kETH.balanceOf(user0), 0);

        SCDPRepayArgs memory repay = SCDPRepayArgs(address(kETH), kETH.balanceOf(user0), oneAddr, pyth.update);
        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(address(kETH)), Enums.Action.SCDPRepay));
        protocol.repaySCDP(repay);

        _toggleActionPaused(address(kETH), Enums.Action.SCDPRepay, false);

        repay = SCDPRepayArgs(address(kETH), kETH.balanceOf(user0), oneAddr, pyth.update);
        prank(user0);
        protocol.repaySCDP(repay);
    }

    function test_swapSCDP_Paused() public {
        _poolDeposit(deployer, oneAddr, 10000e18);
        _toggleActionPaused(oneAddr, Enums.Action.SCDPSwap, true);

        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(oneAddr), Enums.Action.SCDPSwap));
        _swap(user0, oneAddr, 1000e18, address(kETH));

        _toggleActionPaused(oneAddr, Enums.Action.SCDPSwap, false);
        _toggleActionPaused(address(kETH), Enums.Action.SCDPSwap, true);

        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(address(kETH)), Enums.Action.SCDPSwap));
        _swap(user0, oneAddr, 1000e18, address(kETH));

        _toggleActionPaused(address(kETH), Enums.Action.SCDPSwap, false);

        assertEq(kETH.balanceOf(user0), 0);
        _swap(user0, oneAddr, 1000e18, address(kETH));
        assertGt(kETH.balanceOf(user0), 0);
        _swap(user0, address(kETH), kETH.balanceOf(user0), oneAddr);
        assertEq(kETH.balanceOf(user0), 0);
    }

    function test_coverSCDP_Paused() public {
        _toggleActionPaused(address(kETH), Enums.Action.SCDPCover, true);

        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(address(kETH)), Enums.Action.SCDPCover));
        protocol.coverSCDP(address(kETH), 1000e18, pyth.update);
    }

    function test_coverWithIncentiveSCDP_Paused() public {
        _toggleActionPaused(address(kETH), Enums.Action.SCDPCover, true);

        vm.expectRevert(abi.encodeWithSelector(ASSET_PAUSED_FOR_THIS_ACTION.selector, id(address(kETH)), Enums.Action.SCDPCover));
        protocol.coverWithIncentiveSCDP(oneAddr, 1000e18, address(kETH), pyth.update);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   helpers                                  */
    /* -------------------------------------------------------------------------- */

    function _liquidate(uint256 times, uint256, uint256 liquidateAmount) internal repranked(getAddr(0)) {
        for (uint256 i; i < times; i++) {
            _setETHPrice(uint256(90000e8));
            if (i > 40) {
                liquidateAmount = liquidateAmount.pmul(0.50e4);
            }
            _liquidate(kETHAddr, liquidateAmount.pmul(1e4 - (100 * i)), oneAddr);
            _setETHPrice(uint256(2000e8));
        }
    }

    function _swapAndLiquidate(uint256 times, uint256 swapAmount, uint256 liquidateAmount) internal repranked(getAddr(0)) {
        for (uint256 i; i < times; i++) {
            _setETHPrice(uint256(2000e8));
            (uint256 amountOut, , ) = protocol.previewSwapSCDP(oneAddr, address(kETH), swapAmount);
            protocol.swapSCDP(SwapArgs(getAddr(0), oneAddr, kETHAddr, swapAmount, 0, pyth.update));
            _setETHPrice(uint256(90000e8));
            if (i > 40) {
                liquidateAmount = liquidateAmount.pmul(0.50e4);
            }
            _liquidate(kETHAddr, liquidateAmount.pmul(1e4 - (100 * i)), oneAddr);
            _setETHPrice(uint256(2000e8));
            protocol.swapSCDP(SwapArgs(getAddr(0), kETHAddr, oneAddr, amountOut, 0, pyth.update));
        }
    }

    function _poolDeposit(address user, address asset, uint256 amount) internal repranked(user) {
        prank(admin);
        protocol.setGlobalIncome(asset);
        prank(user);
        protocol.depositSCDP(user, asset, amount);
        prank(admin);
        protocol.setGlobalIncome(oneAddr);
    }

    function _poolWithdraw(address user, address asset, uint256 amount) internal repranked(user) {
        protocol.withdrawSCDP(SCDPWithdrawArgs(user, asset, amount, user), pyth.update);
    }

    function _swap(address user, address assetIn, uint256 amount, address assetOut) internal repranked(user) {
        protocol.swapSCDP(SwapArgs(user, assetIn, assetOut, amount, 0, pyth.update));
    }

    function _liquidate(
        address _repayAsset,
        uint256 _repayAmount,
        address _seizeAsset
    ) internal repranked(liquidator) returns (uint256 crAfter, uint256 debtValAfter, uint256 debtAmountAfter) {
        protocol.liquidateSCDP(SCDPLiquidationArgs(_repayAsset, _repayAmount, _seizeAsset), pyth.update);
        return (protocol.getGlobalCollateralRatio(), protocol.getDebtValueSCDP(_repayAsset, true), protocol.getDebtSCDP(_repayAsset));
    }

    function _approvals(address user) internal pranked(user) {
        usdc.approve(address(protocol), type(uint256).max);
        kETH.approve(address(protocol), type(uint256).max);
        one.approve(address(protocol), type(uint256).max);
        kJPY.approve(address(protocol), type(uint256).max);
    }

    function _printInfo(string memory prefix) internal view {
        prefix = string.concat(prefix, " | ");
        string.concat(prefix, "*****************").clg();
        uint256 sdiPrice = protocol.getSDIPrice();
        uint256 sdiTotalSupply = protocol.totalSDI();
        uint256 totalCover = protocol.getSDICoverAmount();
        uint256 collateralUSD = protocol.getTotalCollateralValueSCDP(false);
        uint256 debtUSD = protocol.getTotalDebtValueSCDP(false);

        uint256 effectiveDebt = protocol.getEffectiveSDIDebt();
        uint256 effectiveDebtValue = protocol.getEffectiveSDIDebtUSD();

        sdiPrice.dlg(string.concat(prefix, "SDI Price"));
        sdiTotalSupply.dlg(string.concat(prefix, "SDI totalSupply"));
        protocol.getTotalSDIDebt().dlg(string.concat(prefix, "SCDP SDI Debt Amount"));
        totalCover.dlg(string.concat(prefix, "SCDP SDI Cover Amount"));
        effectiveDebt.dlg(string.concat(prefix, "SCDP Effective SDI Debt Amount"));

        collateralUSD.dlg(string.concat(prefix, "SCDP Collateral USD"), 8);
        debtUSD.dlg(string.concat(prefix, "SCDP Kopio Debt USD"), 8);
        effectiveDebtValue.dlg(string.concat(prefix, "SCDP SDI Debt USD"), 8);
        totalCover.wmul(sdiPrice).dlg(string.concat(prefix, "SCDP SDI Cover USD"));

        protocol.getGlobalCollateralRatio().plg(string.concat(prefix, "SCDP CR %"));
    }

    function _setETHPrice(uint256 price) internal repranked(admin) {
        ethFeed.setPrice(price);
        for (uint256 i = 0; i < tickerCfg.length; i++) {
            if (tickerCfg[i].ticker.equals("ETH")) {
                tickerCfg[i].mockPrice = price;
            }
        }
        updatePythLocal(tickerCfg);
    }

    function _toggleActionPaused(address asset, Enums.Action action, bool paused) internal repranked(council) {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        protocol.toggleAssetsPaused(assets, action, false, 0);
        assertTrue(protocol.assetActionPaused(action, asset) == paused, "paused");
    }
}
