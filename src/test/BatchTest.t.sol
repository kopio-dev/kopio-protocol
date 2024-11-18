// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {Deploy} from "scripts/deploy/Deploy.s.sol";
import {Tested} from "kopio/vm/Tested.t.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {IICDPCollateralFacet} from "interfaces/IICDPCollateralFacet.sol";
import {IICDPAccountStateFacet} from "interfaces/IICDPAccountStateFacet.sol";
import {PLog} from "kopio/vm/PLog.s.sol";
import {ShortAssert} from "kopio/vm/ShortAssert.t.sol";
import {ERC20Mock} from "mocks/Mocks.sol";
import {IICDPMintFacet} from "interfaces/IICDPMintFacet.sol";
import {MintArgs} from "common/Args.sol";
import {KopioCore} from "interfaces/KopioCore.sol";

// solhint-disable state-visibility

contract BatchTest is Tested, Deploy {
    using Deployed for *;
    using PLog for *;
    using ShortAssert for *;

    ERC20Mock usdc;
    ERC20Mock dai;
    address kETH;
    address kJPY;

    address user;

    function setUp() public mnemonic("MNEMONIC_KOPIO") {
        Deploy.deployTest(0);
        address deployer = getAddr(0);

        user = getAddr(100);
        vm.deal(user, 1 ether);

        usdc = ERC20Mock(("USDC").cached());
        dai = ERC20Mock(("DAI").cached());

        kETH = ("kETH").cached();
        kJPY = ("kJPY").cached();

        prank(deployer);

        usdc.mint(user, 1000e6);
        dai.mint(user, 1000 ether);

        prank(user);
        usdc.approve(address(protocol), type(uint256).max);
        dai.approve(address(protocol), type(uint256).max);
    }

    function testBatchCall() public pranked(user) {
        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeCall(IICDPCollateralFacet.depositCollateral, (user, address(dai), 400 ether));
        calls[1] = abi.encodeCall(IICDPCollateralFacet.depositCollateral, (user, address(usdc), 100e6));
        calls[2] = abi.encodeCall(IICDPMintFacet.mintKopio, (MintArgs(user, kETH, 0.1 ether, user), new bytes[](0)));
        calls[3] = abi.encodeCall(IICDPMintFacet.mintKopio, (MintArgs(user, kJPY, 10000 ether, user), new bytes[](0)));

        protocol.batchCall{value: pyth.cost}(calls, pyth.update);

        dai.balanceOf(user).eq(600 ether, "user-dai-balance");
        usdc.balanceOf(user).eq(900e6, "user-usdc-balance");

        ERC20Mock(kETH).balanceOf(user).eq(0.1 ether, "user-kETH-balance");
        ERC20Mock(kJPY).balanceOf(user).eq(10000 ether, "user-kJPY-balance");
    }

    function testBatchStaticCall() public pranked(user) {
        protocol.depositCollateral(user, address(dai), 400 ether);
        protocol.depositCollateral(user, address(usdc), 100e6);
        protocol.mintKopio{value: pyth.cost}(MintArgs(user, kETH, 0.1 ether, user), pyth.update);
        protocol.mintKopio{value: pyth.cost}(MintArgs(user, kJPY, 10000 ether, user), pyth.update);

        bytes[] memory staticCalls = new bytes[](4);
        staticCalls[0] = abi.encodeCall(IICDPAccountStateFacet.getAccountCollateralAmount, (user, address(dai)));
        staticCalls[1] = abi.encodeCall(IICDPAccountStateFacet.getAccountCollateralAmount, (user, address(usdc)));
        staticCalls[2] = abi.encodeCall(IICDPAccountStateFacet.getAccountDebtAmount, (user, kETH));
        staticCalls[3] = abi.encodeCall(IICDPAccountStateFacet.getAccountDebtAmount, (user, kJPY));

        uint256 nativeBalBefore = user.balance;
        (uint256 time, bytes[] memory data) = protocol.batchStaticCall{value: pyth.cost}(staticCalls, pyth.update);

        abi.decode(data[0], (uint256)).eq(400 ether, "static-user-dai-collateral");
        abi.decode(data[1], (uint256)).eq(100e6, "static-user-usdc-collateral");
        abi.decode(data[2], (uint256)).eq(0.1 ether, "static-user-kETH-debt");
        abi.decode(data[3], (uint256)).eq(10000 ether, "static-user-kJPY-debt");

        time.eq(block.timestamp, "static-time");
        user.balance.eq(nativeBalBefore, "static-user-balance");
    }

    function testCantCallStaticCall() public pranked(user) {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(IICDPCollateralFacet.depositCollateral, (user, address(dai), 400 ether));

        vm.expectRevert();
        protocol.batchStaticCall{value: pyth.cost}(calls, pyth.update);
    }

    function testReentry() public pranked(user) {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(IICDPAccountStateFacet.getAccountCollateralAmount, (user, address(dai)));

        Reentrant reentrant = new Reentrant(protocol, calls, pyth.update);

        vm.deal(address(protocol), 1 ether);
        vm.deal(address(reentrant), 0.001 ether);

        vm.expectRevert();
        reentrant.reenter();
    }
}

contract Reentrant {
    KopioCore protocol;
    bytes[] prices;
    bytes[] calls;
    uint256 count;

    constructor(KopioCore _protocol, bytes[] memory _calls, bytes[] memory _prices) {
        protocol = _protocol;
        prices = _prices;
        calls = _calls;
    }

    function reenter() public {
        protocol.batchStaticCall{value: 0.001 ether}(calls, prices);
    }

    receive() external payable {
        if (count == 10) {
            return;
        }
        count++;
        reenter();
    }
}
