// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {cs} from "common/State.sol";

contract CLV3Initializer {
    address public immutable clv3Addr;
    address public constant pythRelayerAddr = 0xfeEFeEfeED0bd9Df8d23dC0242FEF943c574468f;

    constructor(address addr) {
        clv3Addr = addr;
    }

    function run() external {
        if (cs().kopioCLV3 != address(0)) revert("initialized");
        cs().kopioCLV3 = clv3Addr;
        cs().pythRelayer = pythRelayerAddr;
    }
}
