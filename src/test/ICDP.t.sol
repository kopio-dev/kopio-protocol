// solhint-disable state-visibility, max-states-count, var-name-mixedcase, no-global-import, const-name-snakecase, no-empty-blocks, no-console
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Tested} from "kopio/vm/Tested.t.sol";
import {ShortAssert} from "kopio/vm/ShortAssert.t.sol";
import {Strings} from "vendor/Strings.sol";
import {PercentageMath} from "vendor/PercentageMath.sol";
import {Asset} from "common/Types.sol";
import {Log} from "kopio/vm/VmLibs.s.sol";
import {Deploy} from "scripts/deploy/Deploy.s.sol";
import {ERC20Mock} from "mocks/Mocks.sol";
import {IKopio} from "interfaces/IKopio.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import "scripts/deploy/JSON.s.sol" as JSON;
import {BurnArgs, MintArgs, WithdrawArgs} from "common/Args.sol";

string constant CONFIG_ID = "test-clean";

// solhint-disable
contract ICDPTest is Tested, Deploy {
    using ShortAssert for *;
    using Log for *;
    using Strings for uint256;
    using PercentageMath for *;
    using Deployed for *;

    address admin;
    ERC20Mock usdc;
    IKopio kETH;
    IKopio kJPY;
    IKopio kTSLA;

    Asset usdcConfig;
    Asset kJPYConfig;
    Asset kETHConfig;

    function setUp() public mnemonic("MNEMONIC_KOPIO") users(address(111), address(222), address(333)) {
        JSON.Config memory json = Deploy.deployTest("MNEMONIC_KOPIO", CONFIG_ID, 0);

        // for price updates
        vm.deal(address(protocol), 1 ether);

        admin = json.params.common.admin;
        usdc = ERC20Mock(("USDC").cached());
        kETH = IKopio(("kETH").cached());
        kJPY = IKopio(("kJPY").cached());
        kTSLA = IKopio(("kTSLA").cached());
        usdcConfig = protocol.getAsset(address(usdc));
        kETHConfig = protocol.getAsset(address(kETH));
        kJPYConfig = protocol.getAsset(address(kJPY));
    }

    function testInitializers() public {
        JSON.Config memory json = JSON.getConfig("test", CONFIG_ID);

        protocol.owner().eq(getAddr(0));
        protocol.getMCR().eq(json.params.icdp.minCollateralRatio, "icdp-mcr");
        protocol.getGlobalParameters().minCollateralRatio.eq(json.params.scdp.minCollateralRatio, "scdp-mcr");
        protocol.getGlobalParameters().liquidationThreshold.eq(json.params.scdp.liquidationThreshold, "scdp-liquidation-threshold");
        usdcConfig.isGlobalCollateral.eq(true, "usdc-isGlobalCollateral");
        usdcConfig.isGlobalDepositable.eq(true, "usdc-isGlobalDepositable");

        usdcConfig.decimals.eq(usdc.decimals(), "usdc-decimals");
        usdcConfig.depositLimitSCDP.eq(100000000e18, "usdc-deposit-limit");
        protocol.getAssetIndexesSCDP(address(usdc)).currFeeIndex.eq(1e27, "usdc-fee-index");
        protocol.getAssetIndexesSCDP(address(usdc)).currLiqIndex.eq(1e27, "usdc-liq-index");

        kETHConfig.isKopio.eq(true, "keth-is-icdp-mintable");
        kETHConfig.isSwapMintable.eq(true, "keth-is-swap-mintable");
        kETHConfig.liqIncentiveSCDP.eq(103.5e2, "keth-liquidation-incentive");
        kETHConfig.openFee.eq(0, "keth-open-fee");
        kETHConfig.closeFee.eq(50, "keth-close-fee");
        kETHConfig.mintLimit.eq(type(uint128).max, "keth-max-debt-icdp");
        kETHConfig.protocolFeeShareSCDP.eq(20e2, "keth-protocol-fee-share");
    }

    function testDeposit() public pranked(user0) {
        uint256 depositAmount = 100e6;

        usdc.mint(user0, depositAmount);
        usdc.approve(address(protocol), depositAmount);

        protocol.depositCollateral(user0, address(usdc), depositAmount);
        protocol.getAccountCollateralAmount(user0, address(usdc)).eq(depositAmount);

        protocol.getAccountTotalCollateralValue(user0).eq(100e8, "total-collateral-value");
    }

    function testMint() public pranked(user0) {
        uint256 depositAmount = 1000e6;
        uint256 mintAmount = 10000e18;

        usdc.mint(user0, depositAmount);
        usdc.approve(address(protocol), depositAmount);

        protocol.depositCollateral(user0, address(usdc), depositAmount);
        protocol.getAccountCollateralAmount(user0, address(usdc)).eq(depositAmount);

        protocol.mintKopio(MintArgs(user0, address(kJPY), mintAmount, user0), pyth.update);
        protocol.getAccountTotalCollateralValue(user0).eq(1000e8);
        protocol.getAccountTotalDebtValue(user0).eq(67.67e8);
    }

    function testBurn() public pranked(user0) {
        uint256 depositAmount = 1000e6;
        uint256 mintAmount = 10000e18;

        usdc.mint(user0, depositAmount);
        usdc.approve(address(protocol), depositAmount);

        protocol.depositCollateral(user0, address(usdc), depositAmount);
        protocol.getAccountCollateralAmount(user0, address(usdc)).eq(depositAmount);

        protocol.mintKopio(MintArgs(user0, address(kJPY), mintAmount, user0), pyth.update);

        uint256 feeValue = protocol.getValue(address(kJPY), mintAmount.percentMul(kJPYConfig.closeFee));

        protocol.burnKopio(BurnArgs(user0, address(kJPY), mintAmount, user0), pyth.update);

        protocol.getAccountTotalCollateralValue(user0).eq(1000e8 - feeValue);
        protocol.getAccountTotalDebtValue(user0).eq(0);
    }

    function testWithdraw() public pranked(user0) {
        uint256 depositAmount = 1000e6;
        uint256 mintAmount = 10000e18;

        usdc.mint(user0, depositAmount);
        usdc.approve(address(protocol), depositAmount);

        protocol.depositCollateral(user0, address(usdc), depositAmount);
        protocol.getAccountCollateralAmount(user0, address(usdc)).eq(depositAmount);

        protocol.mintKopio(MintArgs(user0, address(kJPY), mintAmount, user0), pyth.update);
        protocol.burnKopio(BurnArgs(user0, address(kJPY), mintAmount, user0), pyth.update);

        protocol.withdrawCollateral(WithdrawArgs(user0, address(usdc), type(uint256).max, user0), pyth.update);

        protocol.getAccountTotalCollateralValue(user0).eq(0);
        protocol.getAccountTotalDebtValue(user0).eq(0);
    }

    function testGas() public pranked(user0) {
        uint256 depositAmount = 1000e6;
        uint256 mintAmount = 10000e18;
        bool success;

        usdc.mint(user0, depositAmount);
        usdc.approve(address(protocol), depositAmount);

        uint256 gasDeposit = gasleft();
        protocol.depositCollateral(user0, address(usdc), depositAmount);
        Log.clg(gasDeposit - gasleft(), "gasDeposit");

        bytes memory mintData = abi.encodeWithSelector(protocol.mintKopio.selector, MintArgs(user0, address(kJPY), mintAmount, user0), pyth.update);
        uint256 gasMint = gasleft();
        (success, ) = address(protocol).call(mintData);
        Log.clg(gasMint - gasleft(), "gasMint");
        require(success, "!success");

        bytes memory burnData = abi.encodeWithSelector(protocol.burnKopio.selector, BurnArgs(user0, address(kJPY), mintAmount, user0), pyth.update);
        uint256 gasBurn = gasleft();
        (success, ) = address(protocol).call(burnData);
        Log.clg(gasBurn - gasleft(), "gasBurn");
        require(success, "!success");

        bytes memory withdrawData = abi.encodeWithSelector(protocol.withdrawCollateral.selector, WithdrawArgs(user0, address(usdc), 998e18, user0), pyth.update);
        uint256 gasWithdraw = gasleft();
        (success, ) = address(protocol).call(withdrawData);
        Log.clg(gasWithdraw - gasleft(), "gasWithdraw");
        require(success, "!success");
    }
}
