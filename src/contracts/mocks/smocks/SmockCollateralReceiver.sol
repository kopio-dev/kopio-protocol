// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;
import {IERC20} from "kopio/token/IERC20.sol";

import {IICDPCollateralFacet} from "interfaces/IICDPCollateralFacet.sol";
import {IFlashWithdrawReceiver} from "interfaces/IFlashWithdrawReceiver.sol";
import {FlashWithdrawArgs} from "common/Args.sol";

// solhint-disable state-visibility

contract SmockCollateralReceiver is IFlashWithdrawReceiver {
    IICDPCollateralFacet public protocol;
    function(address, address, uint256, bytes memory) internal callbackLogic;

    address public account;
    address public collateralAsset;
    uint256 public amountRequested;
    uint256 public amountWithdrawn;
    Params public storeData;

    struct Params {
        uint256 val;
        uint256 val1;
        address addr;
    }

    constructor(address _protocol) {
        protocol = IICDPCollateralFacet(_protocol);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Callback                                  */
    /* -------------------------------------------------------------------------- */

    function onFlashWithdraw(
        address acc,
        address collateral,
        uint256 amount,
        bytes memory datas
    ) external returns (bytes memory) {
        callbackLogic(acc, collateral, amount, datas);
        return "";
    }

    function execute(
        address collateral,
        uint256 amt,
        function(address, address, uint256, bytes memory) internal logic,
        bytes[] memory prices
    ) internal {
        bytes memory data = abi.encode(amt, 0, address(0));
        execute(collateral, amt, data, logic, prices);
    }

    function execute(
        address collateral,
        uint256 amt,
        bytes memory data,
        function(address, address, uint256, bytes memory) internal logic,
        bytes[] memory prices
    ) internal {
        callbackLogic = logic;
        amountRequested = amt;
        protocol.flashWithdrawCollateral(FlashWithdrawArgs(msg.sender, collateral, amt, data), prices);
    }

    /* -------------------------------------------------------------------------- */
    /*                               Test functions                               */
    /* -------------------------------------------------------------------------- */

    // should send correct values to the callback
    function test(address collateral, uint256 amt, bytes[] memory prices) external {
        execute(collateral, amt, logicBase, prices);
    }

    function testWithdrawalAmount(address collateral, uint256 amt, bytes[] memory prices) external {
        execute(collateral, amt, logicTestWithdrawalAmount, prices);
    }

    // should be able to redeposit
    function testRedeposit(address collateral, uint256 amt, bytes[] memory prices) external {
        execute(collateral, amt, logicRedeposit, prices);
    }

    // should be able to redeposit
    function testInsufficientRedeposit(address collateral, uint256 amt, bytes[] memory prices) external {
        execute(collateral, amt, logicInsufficientRedeposit, prices);
    }

    function testDepositAlternate(address withdrawAsset, uint256 amount, address depositAsset, bytes[] memory prices) external {
        bytes memory data = abi.encode(amount, 0, depositAsset);
        execute(withdrawAsset, amount, data, logicDepositAlternate, prices);
    }

    /* -------------------------------------------------------------------------- */
    /*                             Callback Execution                             */
    /* -------------------------------------------------------------------------- */

    function logicDepositAlternate(address acc, address collateral, uint256 amount, bytes memory userData) internal {
        collateral;
        storeData = abi.decode(userData, (Params));
        amountWithdrawn = amount;
        IERC20(storeData.addr).transferFrom(acc, address(this), storeData.val);
        IERC20(storeData.addr).approve(address(protocol), storeData.val);
        // redeposit all
        protocol.depositCollateral(acc, storeData.addr, storeData.val);
    }

    function logicBase(address acc, address collateral, uint256 amount, bytes memory userData) internal {
        // just set data
        account = acc;
        collateralAsset = collateral;
        amountWithdrawn = amount;
        storeData = abi.decode(userData, (Params));
    }

    function logicTestWithdrawalAmount(address acc, address collateral, uint256 amount, bytes memory) internal {
        storeData;
        account = acc;
        require(IERC20(collateral).balanceOf(address(this)) == amount, "wrong amount received");
    }

    function logicRedeposit(address acc, address collateral, uint256 amount, bytes memory) internal {
        storeData;
        amountWithdrawn = amount;
        IERC20(collateral).approve(address(protocol), amount);
        // redeposit all
        protocol.depositCollateral(acc, collateral, amount);
    }

    function logicInsufficientRedeposit(address acc, address collateral, uint256 amount, bytes memory) internal {
        storeData;
        amountWithdrawn = amount;
        IERC20(collateral).approve(address(protocol), 1);
        // bare minimum redeposit
        protocol.depositCollateral(acc, collateral, 1);
    }
}
