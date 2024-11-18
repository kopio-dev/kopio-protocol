// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {FacetAddressAndPosition, FacetFunctionSelectors} from "diamond/Types.sol";

struct DiamondState {
    mapping(bytes4 selector => FacetAddressAndPosition) selectorToFacetAndPosition;
    mapping(address facet => FacetFunctionSelectors) facetFunctionSelectors;
    address[] facetAddresses;
    mapping(bytes4 => bool) supportedInterfaces;
    /// @notice address(this) replacement for FF
    address self;
    bool initialized;
    uint8 initializing;
    bytes32 diamondDomainSeparator;
    address contractOwner;
    address pendingOwner;
    uint96 storageVersion;
}

// keccak256(abi.encode(uint256(keccak256("kopio.slot.diamond")) - 1)) & ~bytes32(uint256(0xff));
bytes32 constant DIAMOND_SLOT = 0xc8ecce9aacc3428c4044cc49a9f54752635242cfef8d73e0144ec29b0ac16a00;

function ds() pure returns (DiamondState storage state) {
    bytes32 position = DIAMOND_SLOT;
    assembly {
        state.slot := position
    }
}
