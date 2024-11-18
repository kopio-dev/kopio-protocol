// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {id, err} from "common/Errors.sol";
import {Enums} from "common/Constants.sol";

/**
 * @title Library for operations on arrays
 */
library Arrays {
    using Arrays for address[];
    using Arrays for bytes32[];
    using Arrays for string[];

    struct FindResult {
        uint256 index;
        bool exists;
    }

    function empty(address[2] memory list) internal pure returns (bool) {
        return list[0] == address(0) && list[1] == address(0);
    }

    function empty(Enums.OracleType[2] memory _oracles) internal pure returns (bool) {
        return _oracles[0] == Enums.OracleType.Empty && _oracles[1] == Enums.OracleType.Empty;
    }

    function findIndex(address[] memory items, address val) internal pure returns (int256 idx) {
        for (uint256 i; i < items.length; ) {
            if (items[i] == val) {
                return int256(i);
            }
            unchecked {
                ++i;
            }
        }

        return -1;
    }

    function find(address[] storage items, address val) internal pure returns (FindResult memory result) {
        address[] memory elements = items;
        for (uint256 i; i < elements.length; ) {
            if (elements[i] == val) {
                return FindResult(i, true);
            }
            unchecked {
                ++i;
            }
        }
    }

    function find(bytes32[] storage items, bytes32 val) internal pure returns (FindResult memory result) {
        bytes32[] memory elements = items;
        for (uint256 i; i < elements.length; ) {
            if (elements[i] == val) {
                return FindResult(i, true);
            }
            unchecked {
                ++i;
            }
        }
    }

    function find(string[] storage items, string memory val) internal pure returns (FindResult memory result) {
        string[] memory elements = items;
        for (uint256 i; i < elements.length; ) {
            if (keccak256(abi.encodePacked(elements[i])) == keccak256(abi.encodePacked(val))) {
                return FindResult(i, true);
            }
            unchecked {
                ++i;
            }
        }
    }

    function pushUnique(address[] storage items, address val) internal {
        if (!items.find(val).exists) {
            items.push(val);
        }
    }

    function pushUnique(bytes32[] storage items, bytes32 val) internal {
        if (!items.find(val).exists) {
            items.push(val);
        }
    }

    function pushUnique(string[] storage items, string memory val) internal {
        if (!items.find(val).exists) {
            items.push(val);
        }
    }

    function removeExisting(address[] storage list, address val) internal {
        FindResult memory result = list.find(val);
        if (result.exists) {
            list.removeAddress(val, result.index);
        }
    }

    /**
     * @dev Removes an element by copying the last element to the element to remove's place and removing
     * the last element.
     * @param list The address array containing the item to be removed.
     * @param addr The element to be removed.
     * @param idx The index of the element to be removed.
     */
    function removeAddress(address[] storage list, address addr, uint256 idx) internal {
        if (list[idx] != addr) revert err.ELEMENT_DOES_NOT_MATCH_PROVIDED_INDEX(id(addr), idx, list);

        uint256 lastIndex = list.length - 1;
        // If the index to remove is not the last one, overwrite the element at the index
        // with the last element.
        if (idx != lastIndex) list[idx] = list[lastIndex];
        // Remove the last element.
        list.pop();
    }
    function removeAddress(address[] storage list, address val) internal {
        removeAddress(list, val, list.find(val).index);
    }
}
