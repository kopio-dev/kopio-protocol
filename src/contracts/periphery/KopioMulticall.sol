// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {OwnableUpgradeable} from "@oz-upgradeable/access/OwnableUpgradeable.sol";
import {ISwapRouter} from "kopio/vendor/ISwapRouter.sol";
import {IPyth} from "kopio/vendor/Pyth.sol";
import {IWETH9Arb} from "kopio/token/IWETH9.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {IVaultExtender} from "interfaces/IVaultExtender.sol";
import {KopioCore} from "interfaces/KopioCore.sol";
import {IKopio} from "interfaces/IKopio.sol";
import {IKopioMulticall} from "interfaces/IKopioMulticall.sol";
import {BurnArgs, MintArgs, SCDPWithdrawArgs, SwapArgs, WithdrawArgs} from "common/Args.sol";
import {fromWad} from "common/funcs/Math.sol";

// solhint-disable avoid-low-level-calls, code-complexity

/**
 * @title kopio multicall
 * @author the kopio project
 * @notice executes supported operations one after another.
 */
contract KopioMulticall is IKopioMulticall, OwnableUpgradeable {
    KopioCore public immutable core;
    address public immutable one;
    IPyth public pythEp;
    ISwapRouter public v3Router;
    IWETH9Arb public wNative;

    mapping(address => mapping(bytes4 func => Target info)) public target;

    constructor(address _protocol, address _one) {
        core = KopioCore(_protocol);
        one = _one;
        _disableInitializers();
    }

    function reinitialize(address _pythEP) external reinitializer(2) {
        pythEp = IPyth(_pythEP);
    }

    function initialize(address _v3Router, address _wNative, address _pythEp, address _owner) external {
        if (owner() != address(0)) _checkOwner();
        else _transferOwnership(_owner);

        v3Router = ISwapRouter(_v3Router);
        wNative = IWETH9Arb(_wNative);
        pythEp = IPyth(_pythEp);
    }

    function executeRaw(bytes[] calldata calls) external payable returns (bytes[] memory results) {
        results = new bytes[](calls.length);

        for (uint256 i; i < calls.length; ) {
            (bool success, bytes memory retData) = _callRaw(calls[i]);
            if (!success) _handleRevert(retData);

            unchecked {
                results[i++] = retData;
            }
        }
    }

    function execute(Op[] calldata ops, bytes[] calldata prices) external payable returns (Result[] memory results) {
        if (prices.length != 0) pythEp.updatePriceFeeds(prices);

        unchecked {
            results = new Result[](ops.length);
            for (uint256 i; i < ops.length; i++) {
                Op memory op = ops[i];

                if (op.data.modeIn != ModeIn.None) {
                    op.data.amountIn = uint96(_handleTokensIn(op));
                    results[i].tokenIn = op.data.tokenIn;
                    results[i].amountIn = op.data.amountIn;
                } else {
                    if (op.data.tokenIn != address(0)) {
                        revert TOKENS_IN_MODE_WAS_NONE_BUT_ADDRESS_NOT_ZERO(op.action, op.data.tokenIn);
                    }
                }

                if (op.data.modeOut != ModeOut.None) {
                    results[i].tokenOut = op.data.tokenOut;
                    if (op.data.modeOut == ModeOut.Return) {
                        results[i].amountOut = IERC20(op.data.tokenOut).balanceOf(msg.sender);
                    } else if (op.data.modeOut == ModeOut.ReturnNative) {
                        results[i].amountOut = msg.sender.balance;
                    } else {
                        results[i].amountOut = IERC20(op.data.tokenOut).balanceOf(address(this));
                    }
                } else {
                    if (op.data.tokenOut != address(0)) {
                        revert TOKENS_OUT_MODE_WAS_NONE_BUT_ADDRESS_NOT_ZERO(op.action, op.data.tokenOut);
                    }
                }

                _handleOp(op);

                if (op.data.modeIn != ModeIn.None && op.data.modeIn != ModeIn.UseOpIn) {
                    uint256 balanceAfter = IERC20(op.data.tokenIn).balanceOf(address(this));
                    if (balanceAfter != 0 && balanceAfter <= results[i].amountIn) {
                        results[i].amountIn = results[i].amountIn - balanceAfter;
                    }
                }

                if (op.data.modeOut != ModeOut.None) {
                    uint256 balanceAfter = IERC20(op.data.tokenOut).balanceOf(address(this));
                    if (op.data.modeOut == ModeOut.Return) {
                        _handleTokensOut(op, balanceAfter);
                        results[i].amountOut = IERC20(op.data.tokenOut).balanceOf(msg.sender) - results[i].amountOut;
                    } else if (op.data.modeOut == ModeOut.ReturnNative) {
                        _handleTokensOut(op, balanceAfter);
                        results[i].amountOut = msg.sender.balance - results[i].amountOut;
                    } else {
                        results[i].amountOut = balanceAfter - results[i].amountOut;
                    }
                }

                if (i > 0 && results[i - 1].amountOut == 0) {
                    results[i - 1].amountOut = results[i].amountIn;
                }
            }

            _handleFinished(ops);

            emit MulticallExecuted(msg.sender, ops, results);
        }
    }

    function _handleTokensIn(Op memory op) internal returns (uint256 amountIn) {
        if (op.data.modeIn == ModeIn.Native) {
            if (msg.value == 0) revert ZERO_NATIVE_IN(op.action);
            if (op.data.tokenIn != address(wNative))
                revert INVALID_NATIVE_TOKEN_IN(op.action, op.data.tokenIn, wNative.symbol());

            wNative.deposit{value: msg.value}();
            return wNative.balanceOf(address(this));
        }

        IERC20 token = IERC20(op.data.tokenIn);

        // Pull tokens from sender
        if (op.data.modeIn == ModeIn.Pull) {
            if (op.data.amountIn == 0) revert ZERO_AMOUNT_IN(op.action, op.data.tokenIn, token.symbol());
            if (token.allowance(msg.sender, address(this)) < op.data.amountIn)
                revert NO_MULTI_ALLOWANCE(op.action, op.data.tokenIn, token.symbol());
            token.transferFrom(msg.sender, address(this), op.data.amountIn);
            return op.data.amountIn;
        }

        // Use contract balance for tokens in
        if (op.data.modeIn == ModeIn.Balance) {
            return token.balanceOf(address(this));
        }
        if (op.data.modeIn == ModeIn.BalanceNative) {
            return address(this).balance;
        }

        if (op.data.modeIn == ModeIn.BalanceUnwrapNative) {
            if (op.data.tokenIn != address(wNative)) {
                revert INVALID_NATIVE_TOKEN_IN(op.action, op.data.tokenIn, wNative.symbol());
            }
            wNative.withdraw(wNative.balanceOf(address(this)));
            return address(this).balance;
        }

        if (op.data.modeIn == ModeIn.BalanceWrapNative) {
            if (op.data.tokenIn != address(wNative)) {
                revert INVALID_NATIVE_TOKEN_IN(op.action, op.data.tokenIn, wNative.symbol());
            }
            wNative.deposit{value: address(this).balance}();
            return wNative.balanceOf(address(this));
        }

        // Use amountIn for tokens in, eg. ICDPRepay allows this.
        if (op.data.modeIn == ModeIn.UseOpIn) return op.data.amountIn;

        revert INVALID_ACTION(op.action);
    }

    function _handleTokensOut(Op memory op, uint256 balance) internal {
        if (op.data.modeOut == ModeOut.ReturnNative) {
            wNative.withdraw(balance);
            payable(msg.sender).transfer(address(this).balance);
            return;
        }

        if (balance != 0) {
            // Transfer tokens to sender
            IERC20 tokenOut = IERC20(op.data.tokenOut);
            tokenOut.transfer(msg.sender, balance);
        }
    }

    /// @notice Send all op tokens and native to sender
    function _handleFinished(Op[] memory ops) internal {
        for (uint256 i; i < ops.length; i++) {
            Op memory op = ops[i];

            // Transfer any tokenIns to sender
            if (op.data.tokenIn != address(0)) {
                IERC20 tokenIn = IERC20(op.data.tokenIn);
                uint256 bal = tokenIn.balanceOf(address(this));
                if (bal != 0) tokenIn.transfer(msg.sender, bal);
            }

            // Transfer any tokenOuts to sender
            if (op.data.tokenOut != address(0)) {
                IERC20 tokenOut = IERC20(op.data.tokenOut);
                uint256 bal = tokenOut.balanceOf(address(this));
                if (bal != 0) tokenOut.transfer(msg.sender, bal);
            }
        }

        // Transfer native to sender
        if (address(this).balance != 0) payable(msg.sender).transfer(address(this).balance);
    }

    function _approve(address _token, uint256 _amount, address spender) internal {
        if (_amount != 0) IERC20(_token).approve(spender, _amount);
    }

    function _handleOp(Op memory op) internal {
        (bool success, bytes memory err) = _call(op, new bytes[](0));
        if (!success) _handleRevert(err);
    }

    function _call(Op memory op, bytes[] memory prices) internal returns (bool success, bytes memory retData) {
        bool isReturn = op.data.modeOut == ModeOut.Return;
        address receiver = isReturn ? msg.sender : address(this);
        if (op.action == Action.ICDPDeposit) {
            _approve(op.data.tokenIn, op.data.amountIn, address(core));
            return address(core).call(abi.encodeCall(core.depositCollateral, (msg.sender, op.data.tokenIn, op.data.amountIn)));
        }

        if (op.action == Action.ICDPWithdraw) {
            return
                address(core).call(
                    abi.encodeCall(
                        core.withdrawCollateral,
                        (WithdrawArgs(msg.sender, op.data.tokenOut, op.data.amountOut, receiver), prices)
                    )
                );
        }

        if (op.action == Action.ICDPRepay) {
            return
                address(core).call(
                    abi.encodeCall(core.burnKopio, (BurnArgs(msg.sender, op.data.tokenIn, op.data.amountIn, receiver), prices))
                );
        }

        if (op.action == Action.ICDPBorrow) {
            return
                address(core).call(
                    abi.encodeCall(
                        core.mintKopio,
                        (MintArgs(msg.sender, op.data.tokenOut, op.data.amountOut, receiver), prices)
                    )
                );
        }

        if (op.action == Action.SCDPDeposit) {
            _approve(op.data.tokenIn, op.data.amountIn, address(core));
            return address(core).call(abi.encodeCall(core.depositSCDP, (msg.sender, op.data.tokenIn, op.data.amountIn)));
        }

        if (op.action == Action.SCDPTrade) {
            _approve(op.data.tokenIn, op.data.amountIn, address(core));
            return
                address(core).call(
                    abi.encodeCall(
                        core.swapSCDP,
                        (SwapArgs(receiver, op.data.tokenIn, op.data.tokenOut, op.data.amountIn, op.data.minOut, prices))
                    )
                );
        }

        if (op.action == Action.SCDPWithdraw) {
            return
                address(core).call(
                    abi.encodeCall(
                        core.withdrawSCDP,
                        (SCDPWithdrawArgs(msg.sender, op.data.tokenOut, op.data.amountOut, receiver), prices)
                    )
                );
        }

        if (op.action == Action.SCDPClaim) {
            return address(core).call(abi.encodeCall(core.claimFeesSCDP, (msg.sender, op.data.tokenOut, receiver)));
        }

        if (op.action == Action.Wrap) {
            _approve(op.data.tokenIn, op.data.amountIn, op.data.tokenOut);
            return op.data.tokenOut.call(abi.encodeCall(IKopio.wrap, (receiver, op.data.amountIn)));
        }

        if (op.action == Action.WrapNative) {
            if (!IKopio(op.data.tokenOut).wraps().native) {
                revert NATIVE_SYNTH_WRAP_NOT_ALLOWED(op.action, op.data.tokenOut, IERC20(op.data.tokenOut).symbol());
            }

            uint256 wBal = wNative.balanceOf(address(this));
            if (wBal != 0) wNative.withdraw(wBal);

            return address(op.data.tokenOut).call{value: address(this).balance}("");
        }

        if (op.action == Action.Unwrap) {
            IKopio asset = IKopio(op.data.tokenIn);
            IKopio.Wraps memory info = asset.wraps();
            return
                op.data.tokenIn.call(
                    abi.encodeCall(
                        IKopio.unwrap,
                        (receiver, fromWad(IERC20(op.data.tokenIn).balanceOf(address(this)), info.underlyingDec), false)
                    )
                );
        }

        if (op.action == Action.UnwrapNative) {
            return op.data.tokenIn.call(abi.encodeCall(IKopio.unwrap, (receiver, op.data.amountIn, true)));
        }

        if (op.action == Action.VaultDeposit) {
            _approve(op.data.tokenIn, op.data.amountIn, one);
            return one.call(abi.encodeCall(IVaultExtender.vaultDeposit, (op.data.tokenIn, op.data.amountIn, receiver)));
        }

        if (op.action == Action.VaultRedeem) {
            _approve(one, op.data.amountIn, one);
            return
                one.call(
                    abi.encodeCall(IVaultExtender.vaultRedeem, (op.data.tokenOut, op.data.amountIn, receiver, address(this)))
                );
        }

        if (op.action == Action.AMMExactInput) {
            IERC20(op.data.tokenIn).transfer(address(v3Router), op.data.amountIn);
            if (
                v3Router.exactInput(
                    ISwapRouter.ExactInputParams({path: op.data.path, recipient: receiver, amountIn: 0, minOut: op.data.minOut})
                ) == 0
            ) {
                revert ZERO_OR_INVALID_AMOUNT_IN(
                    op.action,
                    op.data.tokenOut,
                    IERC20(op.data.tokenOut).symbol(),
                    IERC20(op.data.tokenOut).balanceOf(address(this)),
                    op.data.minOut
                );
            }
            return (true, "");
        }

        revert INVALID_ACTION(op.action);
    }

    function _callRaw(bytes calldata _data) internal returns (bool, bytes memory) {
        Call memory call = getRawCall(_data);

        if (call.mode == CallMode.Call) return call.target.call{value: call.value}(call.data);
        if (call.mode == CallMode.Delegate) return call.target.delegatecall(call.data);
        if (call.mode == CallMode.Static) return call.target.staticcall(call.data);

        revert INVALID_RAW_CALL(call);
    }

    function setTargets(address[] calldata targets, bytes4[] calldata funcs, Target[] calldata infos) external onlyOwner {
        for (uint256 i; i < targets.length; i++) {
            target[targets[i]][funcs[i]] = infos[i];
        }
    }

    function getRawCall(bytes calldata _data) public view returns (Call memory call) {
        call.target = address(bytes20(_data[:20]));
        call.value = uint96(bytes12(_data[20:32]));

        bytes calldata callData = _data[32:];

        Target memory info = target[call.target][bytes4(_data[32:36])];
        call.mode = info.mode;

        if (info.sender < 4) {
            call.data = callData;
        } else {
            call.data = bytes.concat(callData[:info.sender], abi.encode(msg.sender), callData[info.sender + 32:]);
        }
    }

    function _handleRevert(bytes memory data) internal pure {
        assembly {
            revert(add(32, data), mload(data))
        }
    }

    receive() external payable {}
}
