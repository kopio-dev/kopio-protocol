// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IERC20} from "kopio/token/IERC20.sol";
import {Revert} from "kopio/utils/Funcs.sol";

contract SDICoverRecipient {
    address public owner;
    address public pendingOwner;
    error NotOwner();
    error NotPendingOwner();
    error NotContract(address);

    constructor(address _owner) {
        owner = _owner;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function functionCall(address to, bytes calldata data) external payable onlyOwner {
        (bool success, bytes memory result) = to.call{value: msg.value}(data);
        if (!success) Revert(result);
    }

    function withdraw(address token, address recipient, uint256 amount) external onlyOwner {
        if (recipient.code.length == 0) revert NotContract(recipient);
        if (address(token) == address(0)) payable(recipient).transfer(amount);
        else IERC20(token).transfer(recipient, amount);
    }

    function changeOwner(address newPendingOwner) external onlyOwner {
        pendingOwner = newPendingOwner;
    }

    function acceptOwnership(address newOwner) external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        owner = newOwner;
        pendingOwner = address(0);
    }
}
