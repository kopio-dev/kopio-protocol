// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Meta} from "libs/Meta.sol";
import {DTypes} from "diamond/Types.sol";
import {Constants} from "common/Constants.sol";
import {ds} from "diamond/State.sol";

abstract contract DSModifiers {
    modifier initializer(uint256 version) {
        if (ds().initializing != Constants.INITIALIZING) revert DTypes.DIAMOND_NOT_INITIALIZING();
        if (version <= ds().storageVersion) revert DTypes.DIAMOND_ALREADY_INITIALIZED(version, ds().storageVersion);
        _;
    }
    modifier onlyDiamondOwner() {
        if (Meta.msgSender() != ds().contractOwner) {
            revert DTypes.NOT_DIAMOND_OWNER(Meta.msgSender(), ds().contractOwner);
        }
        _;
    }
}
