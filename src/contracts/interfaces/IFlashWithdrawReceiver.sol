// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IFlashWithdrawReceiver {
    function onFlashWithdraw(address account, address asset, uint256 amount, bytes memory data) external returns (bytes memory);
}
