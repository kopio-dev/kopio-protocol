// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ShortAssert} from "kopio/vm/ShortAssert.t.sol";
import {Utils, Log} from "kopio/vm/VmLibs.s.sol";
import {Deploy} from "scripts/deploy/Deploy.s.sol";
import {Kopio} from "asset/Kopio.sol";
import {MockOracle, ERC20Mock} from "mocks/Mocks.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {SwapArgs} from "common/Args.sol";

import "scripts/deploy/JSON.s.sol" as JSON;
import {Multi} from "interfaces/IKopioMulticall.sol";
import {Tested} from "kopio/vm/Tested.t.sol";

// solhint-disable state-visibility, max-states-count, var-name-mixedcase, no-global-import, const-name-snakecase, no-empty-blocks, no-console

contract MulticallTest is Tested, Deploy, Multi {
    using ShortAssert for *;
    using Log for *;
    using Utils for *;
    uint256 constant ETH_PRICE = 2000;

    Kopio kETH;
    Kopio kJPY;
    address kETHAddr;
    address kJPYAddr;
    MockOracle ethFeed;
    ERC20Mock usdc;
    ERC20Mock usdt;

    function setUp() public {
        Deploy.deployTest(0);

        // for price updates
        vm.deal(address(protocol), 1 ether);

        usdc = ERC20Mock(Deployed.addr("USDC"));
        usdt = ERC20Mock(Deployed.addr("USDT"));
        kETHAddr = Deployed.addr("kETH");
        kJPYAddr = Deployed.addr("kJPY");
        ethFeed = MockOracle(Deployed.addr("ETH.feed"));
        kETH = Kopio(payable(kETHAddr));
        kJPY = Kopio(payable(kJPYAddr));

        // enableLogger();
        prank(getAddr(0));
        usdc.approve(address(protocol), type(uint256).max);
        kETH.approve(address(protocol), type(uint256).max);
        _setETHPrice(ETH_PRICE);
        // 1000 ONE -> 0.48 ETH
        protocol.swapSCDP(SwapArgs(getAddr(0), address(one), kETHAddr, 1000e18, 0, pyth.update));
        vault.setAssetFees(address(usdt), 10e2, 10e2);

        usdc.mint(getAddr(100), 10_000e6);
    }

    function testMulticallDepositBorrow() public {
        address user = getAddr(100);
        prank(user);
        usdc.approve(address(multicall), type(uint256).max);

        Op[] memory ops = new Op[](2);

        ops[0] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: address(usdc), amountIn: 10_000e6, modeIn: ModeIn.Pull, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });
        ops[1] = Op({
            action: Action.ICDPBorrow,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: kJPYAddr, amountOut: 10000e18, modeOut: ModeOut.Return, minOut: 0, path: ""})
        });

        Result[] memory results = multicall.execute(ops, pyth.update);
        usdc.balanceOf(user).eq(0, "usdc-balance");
        kJPY.balanceOf(user).eq(10000e18, "jpy-borrow-balance");
        results[0].amountIn.eq(10_000e6, "usdc-deposit-amount");
        results[0].tokenIn.eq(address(usdc), "usdc-deposit-addr");
        results[1].tokenOut.eq(kJPYAddr, "jpy-borrow-addr");
        results[1].amountOut.eq(10000e18, "jpy-borrow-amount");
    }

    function testNativeDeposit() public {
        address user = getAddr(100);
        uint256 amount = 5 ether;
        vm.deal(user, amount * 2);
        prank(user);

        Op[] memory ops = new Op[](1);

        ops[0] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: address(weth), amountIn: 0, modeIn: ModeIn.Native, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });

        Result[] memory results = multicall.execute{value: 5 ether}(ops, pyth.update);
        results[0].amountIn.eq(5 ether, "native-deposit-amount");
        results[0].tokenIn.eq(address(weth), "native-deposit-addr");
        uint256 depositsAfter = protocol.getAccountCollateralAmount(user, address(weth));
        address(multicall).balance.eq(0 ether, "native-contract-balance-after");

        user.balance.eq(5 ether, "native-user-balance-after");
        depositsAfter.eq(5 ether, "native-deposit-amount-after");
    }

    function testNativeDepositRevert() public {
        address user = getAddr(100);
        uint256 amount = 5 ether;
        vm.deal(user, amount * 2);
        prank(user);
        Op[] memory ops = new Op[](1);

        ops[0] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: address(usdt), amountIn: 0, modeIn: ModeIn.Native, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });

        vm.expectRevert();
        multicall.execute{value: 5 ether}(ops, pyth.update);
    }

    function testNativeDepositWithdraw() public {
        address user = getAddr(100);
        uint256 amount = 5 ether;
        vm.deal(user, amount * 2);
        prank(user);
        Op[] memory ops = new Op[](2);

        ops[0] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: address(weth), amountIn: 0, modeIn: ModeIn.Native, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });
        ops[1] = Op({
            action: Action.ICDPWithdraw,
            data: Data({
                tokenIn: address(0),
                amountIn: 0,
                modeIn: ModeIn.None,
                tokenOut: address(weth),
                amountOut: uint96(amount),
                modeOut: ModeOut.ReturnNative,
                minOut: 0,
                path: ""
            })
        });

        Result[] memory results = multicall.execute{value: amount}(ops, pyth.update);
        results[0].amountIn.eq(amount, "native-deposit-amount");
        results[0].tokenIn.eq(address(weth), "native-deposit-addr");
        results[1].amountOut.eq(amount, "native-deposit-amount");
        results[1].tokenOut.eq(address(weth), "native-deposit-addr");
        uint256 depositsAfter = protocol.getAccountCollateralAmount(user, address(weth));
        address(multicall).balance.eq(0 ether, "native-contract-balance-after");

        user.balance.eq(10 ether, "native-user-balance-after");
        depositsAfter.eq(0 ether, "native-deposit-amount-after");
    }

    function testMulticallDepositBorrowRepay() public {
        address user = getAddr(100);
        prank(user);
        usdc.approve(address(multicall), type(uint256).max);

        Op[] memory ops = new Op[](3);

        ops[0] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: address(usdc), amountIn: 10_000e6, modeIn: ModeIn.Pull, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });
        ops[1] = Op({
            action: Action.ICDPBorrow,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: kJPYAddr, amountOut: 10000e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        ops[2] = Op({
            action: Action.ICDPRepay,
            data: Data({tokenIn: kJPYAddr, amountIn: 10000e18, modeIn: ModeIn.Balance, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });

        Result[] memory results = multicall.execute(ops, pyth.update);
        usdc.balanceOf(user).eq(0, "usdc-balance");
        kJPY.balanceOf(user).eq(0, "jpy-borrow-balance");
        results[0].amountIn.eq(10_000e6, "usdc-deposit-amount");
        results[0].tokenIn.eq(address(usdc), "usdc-deposit-addr");
        results[1].tokenOut.eq(kJPYAddr, "jpy-borrow-addr");
        results[1].amountOut.eq(10000e18, "jpy-borrow-amount");
        results[2].tokenIn.eq(kJPYAddr, "jpy-repay-addr");
        results[2].amountIn.eq(10000e18, "jpy-repay-amount");
    }

    function testMulticallVaultDepositSCDPDeposit() public {
        address user = getAddr(100);
        prank(user);
        usdc.approve(address(multicall), type(uint256).max);

        Op[] memory ops = new Op[](2);

        ops[0] = Op({
            action: Action.VaultDeposit,
            data: Data({tokenIn: address(usdc), amountIn: 10_000e6, modeIn: ModeIn.Pull, tokenOut: address(one), amountOut: 0, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        ops[1] = Op({
            action: Action.SCDPDeposit,
            data: Data({tokenIn: address(one), amountIn: 0, modeIn: ModeIn.Balance, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });

        Result[] memory results = multicall.execute(ops, pyth.update);
        usdc.balanceOf(user).eq(0, "usdc-balance");
        protocol.getAccountDepositSCDP(user, address(one)).eq(9998e18, "one-deposit-amount");
        one.balanceOf(user).eq(0, "jpy-borrow-balance");

        results[0].tokenIn.eq(address(usdc), "results-usdc-deposit-addr");
        results[0].amountIn.eq(10_000e6, "results-usdc-deposit-amount");
        results[1].tokenIn.eq(address(one), "results-one-deposit-addr");
        results[1].amountIn.eq(9998e18, "results-one-deposit-amount");
    }

    function testMulticallVaultWithdrawSCDPWithdraw() public {
        vm.skip(true);

        address user = getAddr(100);
        prank(user);
        usdc.approve(address(multicall), type(uint256).max);

        Op[] memory opsDeposit = new Op[](2);
        opsDeposit[0] = Op({
            action: Action.VaultDeposit,
            data: Data({tokenIn: address(usdc), amountIn: 10_000e6, modeIn: ModeIn.Pull, tokenOut: address(one), amountOut: 0, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        opsDeposit[1] = Op({
            action: Action.SCDPDeposit,
            data: Data({tokenIn: address(one), amountIn: 0, modeIn: ModeIn.Balance, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });

        multicall.execute(opsDeposit, pyth.update);

        Op[] memory opsWithdraw = new Op[](2);
        opsWithdraw[0] = Op({
            action: Action.SCDPWithdraw,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: address(one), amountOut: 9998e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        opsWithdraw[1] = Op({
            action: Action.VaultRedeem,
            data: Data({tokenIn: address(one), amountIn: 0, modeIn: ModeIn.Balance, tokenOut: address(usdc), amountOut: 0, modeOut: ModeOut.Return, minOut: 0, path: ""})
        });

        Result[] memory results = multicall.execute(opsWithdraw, pyth.update);

        usdc.balanceOf(user).eq(9996000400, "usdc-balance");
        protocol.getAccountDepositSCDP(user, address(one)).eq(0, "one-deposit-amount");
        one.balanceOf(user).eq(0, "jpy-borrow-balance");

        results[0].tokenIn.eq(address(0), "results-tokenin-addr");
        results[0].amountIn.eq(0, "results-tokenin-amount");
        results[0].tokenOut.eq(address(one), "results-one-deposit-addr");
        results[0].amountOut.eq(9998e18, "results-one-deposit-amount");
        results[1].tokenIn.eq(address(one), "results-one-vault-withdraw-addr");
        results[1].amountIn.eq(9998e18, "result-one-vault-withdraw-amount");
        results[1].tokenOut.eq(address(usdc), "results-usdc-vault-withdraw-addr");
        results[1].amountOut.eq(9996000400, "results-usdc-vault-withdraw-amount");
    }

    function testMulticallShort() public {
        vm.skip(true);

        address user = getAddr(100);
        prank(user);
        usdc.approve(address(multicall), type(uint256).max);
        usdc.approve(address(protocol), type(uint256).max);

        protocol.depositCollateral(user, address(usdc), 10_000e6);

        Op[] memory opsShort = new Op[](2);
        opsShort[0] = Op({
            action: Action.ICDPBorrow,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: kJPYAddr, amountOut: 10_000e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        opsShort[1] = Op({
            action: Action.SCDPTrade,
            data: Data({tokenIn: kJPYAddr, amountIn: 10_000e18, modeIn: ModeIn.Balance, tokenOut: address(one), amountOut: 0, modeOut: ModeOut.Return, minOut: 0, path: ""})
        });
        Result[] memory results = multicall.execute(opsShort, pyth.update);

        kJPY.balanceOf(address(multicall)).eq(0, "jpy-balance-multicall-after");
        one.balanceOf(address(multicall)).eq(0, "one-balance-multicall-after");
        usdc.balanceOf(user).eq(0, "usdc-balance-after");
        protocol.getAccountCollateralAmount(user, address(usdc)).eq(9998660000, "usdc-deposit-amount");
        one.balanceOf(user).eq(66.7655e18, "one-balance-after");
        protocol.getAccountDebtAmount(user, kJPYAddr).eq(10_000e18, "jpy-borrow-balance-after");

        results[0].tokenIn.eq(address(0), "results-0-tokenin-addr");
        results[0].amountIn.eq(0, "results-0-tokenin-amount");
        results[0].tokenOut.eq(kJPYAddr, "results-jpy-borrow-addr");
        results[0].amountOut.eq(10_000e18, "results-jpy-borrow-amount");
        results[1].tokenIn.eq(kJPYAddr, "results-jpy-trade-in-addr");
        results[1].amountIn.eq(10_000e18, "result-jpy-trade-in-amount");
        results[1].tokenOut.eq(address(one), "results-one-trade-out-addr");
        results[1].amountOut.eq(66.7655e18, "results-usdc-vault-withdraw-amount");
    }

    function testMulticallShortClose() public {
        vm.skip(true);

        address user = getAddr(100);
        prank(user);
        kJPY.balanceOf(user).eq(0, "jpy-balance-before");
        usdc.approve(address(multicall), type(uint256).max);
        usdc.approve(address(protocol), type(uint256).max);
        one.approve(address(multicall), type(uint256).max);

        protocol.depositCollateral(user, address(usdc), 10_000e6);
        Op[] memory opsShort = new Op[](2);
        opsShort[0] = Op({
            action: Action.ICDPBorrow,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: kJPYAddr, amountOut: 10_000e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        opsShort[1] = Op({
            action: Action.SCDPTrade,
            data: Data({tokenIn: kJPYAddr, amountIn: 10_000e18, modeIn: ModeIn.Balance, tokenOut: address(one), amountOut: 0, modeOut: ModeOut.Return, minOut: 0, path: ""})
        });
        multicall.execute(opsShort, pyth.update);

        Op[] memory opsShortClose = new Op[](2);

        opsShortClose[0] = Op({
            action: Action.SCDPTrade,
            data: Data({tokenIn: address(one), amountIn: 66.7655e18, modeIn: ModeIn.Pull, tokenOut: kJPYAddr, amountOut: 9930.1225e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        opsShortClose[1] = Op({
            action: Action.ICDPRepay,
            data: Data({tokenIn: kJPYAddr, amountIn: 9930.1225e18, modeIn: ModeIn.Balance, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });
        Result[] memory results = multicall.execute(opsShortClose, pyth.update);

        usdc.balanceOf(user).eq(0, "usdc-balance");
        protocol.getAccountCollateralAmount(user, address(usdc)).eq(9997520000, "usdc-deposit-amount");
        one.balanceOf(user).eq(0, "one-balance-after");
        kJPY.balanceOf(address(multicall)).eq(0, "jpy-balance-multicall-after");

        // min debt value
        protocol.getAccountDebtAmount(user, kJPYAddr).eq(1492537313432835820896, "jpy-borrow-balance-after");
        kJPY.balanceOf(user).eq(1422659813432835820896, "jpy-balance-after");

        results[0].tokenIn.eq(address(one), "results-one-trade-in-addr");
        results[0].amountIn.eq(66.7655e18, "results-one-trade-in-amount");
        results[0].tokenOut.eq(kJPYAddr, "results-jpy-trade-out-addr");
        results[0].amountOut.eq(9930.1225e18, "results-jpy-trade-out-amount");
        results[1].tokenIn.eq(kJPYAddr, "results-jpy-repay-addr");
        results[1].amountIn.eq(8507462686567164179104, "result-jpy-repay-amount");
        results[1].tokenOut.eq(address(0), "results-repay-addr");
        results[1].amountOut.eq(0, "results-usdc-vault-withdraw-amount");
    }

    function testMulticallComplex() public {
        Op[] memory ops = new Op[](9);
        ops[0] = Op({
            action: Action.ICDPBorrow,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: kJPYAddr, amountOut: 10000e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        ops[1] = Op({
            action: Action.ICDPBorrow,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: kJPYAddr, amountOut: 10000e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        ops[2] = Op({
            action: Action.ICDPBorrow,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: kJPYAddr, amountOut: 10000e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        ops[3] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: kJPYAddr, amountIn: 10000e18, modeIn: ModeIn.UseOpIn, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });
        ops[4] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: kJPYAddr, amountIn: 10000e18, modeIn: ModeIn.UseOpIn, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });
        ops[5] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: kJPYAddr, amountIn: 10000e18, modeIn: ModeIn.UseOpIn, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });
        ops[6] = Op({
            action: Action.ICDPDeposit,
            data: Data({tokenIn: kJPYAddr, amountIn: 10000e18, modeIn: ModeIn.Pull, tokenOut: address(0), amountOut: 0, modeOut: ModeOut.None, minOut: 0, path: ""})
        });
        ops[7] = Op({
            action: Action.ICDPBorrow,
            data: Data({tokenIn: address(0), amountIn: 0, modeIn: ModeIn.None, tokenOut: kJPYAddr, amountOut: 10000e18, modeOut: ModeOut.Leave, minOut: 0, path: ""})
        });
        ops[8] = Op({
            action: Action.SCDPTrade,
            data: Data({tokenIn: kJPYAddr, modeIn: ModeIn.Balance, amountIn: 10000e18, tokenOut: kETHAddr, modeOut: ModeOut.Return, amountOut: 0, minOut: 0, path: ""})
        });

        prank(getAddr(0));
        kJPY.approve(address(multicall), type(uint256).max);
        Result[] memory results = multicall.execute(ops, pyth.update);
        for (uint256 i; i < results.length; i++) {
            results[i].tokenIn.clg("tokenIn");
            results[i].amountIn.clg("amountIn");
            results[i].tokenOut.clg("tokenOut");
            results[i].amountOut.clg("amountOut");
        }
    }

    /* -------------------------------- Util -------------------------------- */

    function _setETHPrice(uint256 _newPrice) internal {
        ethFeed.setPrice(_newPrice * 1e8);
        JSON.TickerConfig[] memory tickers = JSON.getAssetConfig("test", "test-base").tickers;
        for (uint256 i = 0; i < tickers.length; i++) {
            if (tickers[i].ticker.equals("ETH")) {
                tickers[i].mockPrice = _newPrice * 1e8;
            }
        }
        updatePythLocal(tickers);
    }
}
