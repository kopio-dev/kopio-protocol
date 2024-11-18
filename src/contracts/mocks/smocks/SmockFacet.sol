// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISmockFacet} from "./ISmockFacet.sol";
import {DSModifiers} from "diamond/DSModifiers.sol";
import {SmockStorage, err} from "./SmockStorage.sol";
import {Modifiers} from "common/Modifiers.sol";

bytes32 constant TEST_OPERATOR_ROLE = keccak256("kopio.test.operator");

/**
 * @dev Use for Smock fakes / mocks.
 */
contract SmockFacet is DSModifiers, Modifiers, ISmockFacet {
    uint256 public constant MESSAGE_THROTTLE = 2;

    function operator() external view returns (address) {
        return SmockStorage.state().operator;
    }

    function activate() external override onlyRole(TEST_OPERATOR_ROLE) onlyDisabled {
        SmockStorage.activate();
    }

    function disable() external override onlyRole(TEST_OPERATOR_ROLE) onlyActive {
        SmockStorage.disable();
    }

    function smockInitialized() external view returns (bool) {
        return SmockStorage.state().initialized;
    }

    function setMessage(string memory message) external override onlyActive {
        require(block.number >= SmockStorage.state().lastMessageBlock + MESSAGE_THROTTLE, "Cant set message yet");

        SmockStorage.state().message = message;
        SmockStorage.state().callers[msg.sender] = true;

        emit SmockStorage.Call(msg.sender);
        emit NewMessage(msg.sender, message);
    }

    modifier onlyActive() {
        if (!SmockStorage.state().isActive) revert("NOT_ACTIVE");
        _;
    }

    modifier onlyDisabled() {
        if (SmockStorage.state().isActive) revert("NOT_DISABLED");
        _;
    }
}
