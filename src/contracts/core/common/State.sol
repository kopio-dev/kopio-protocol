// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {EnumerableSet} from "@oz/utils/structs/EnumerableSet.sol";
import {LibModifiers} from "common/Modifiers.sol";
import {Enums} from "common/Constants.sol";
import {Asset, SafetyState, RoleData, Oracle} from "common/Types.sol";

using LibModifiers for CommonState global;

struct CommonState {
    mapping(address asset => Asset) assets;
    mapping(bytes32 ticker => mapping(Enums.OracleType provider => Oracle)) oracles;
    mapping(address asset => mapping(Enums.Action action => SafetyState)) safetyState;
    address feeRecipient;
    address pythEp;
    address sequencerUptimeFeed;
    uint32 sequencerGracePeriodTime;
    /// @notice The max deviation percentage between primary and secondary price.
    uint16 maxPriceDeviationPct;
    /// @notice Offchain oracle decimals
    uint8 oracleDecimals;
    /// @notice Flag tells if there is a need to perform safety checks on user actions
    bool safetyStateSet;
    uint256 entered;
    mapping(bytes32 role => RoleData data) _roles;
    mapping(bytes32 role => EnumerableSet.AddressSet member) _roleMembers;
    address marketStatusProvider;
    address kopioCLV3;
    address pythRelayer;
}

// keccak256(abi.encode(uint256(keccak256("kopio.slot.common")) - 1)) & ~bytes32(uint256(0xff));
bytes32 constant COMMON_SLOT = 0xfc1d014d58da005150440e1217b5f770417f3480965a1e2032e843d013624600;

function cs() pure returns (CommonState storage state) {
    bytes32 position = bytes32(COMMON_SLOT);
    assembly {
        state.slot := position
    }
}
