// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;
import {Revert} from "kopio/utils/Funcs.sol";
import {IBatchFacet} from "interfaces/IBatchFacet.sol";
import {err} from "common/Errors.sol";
import {Modifiers} from "common/Modifiers.sol";

// solhint-disable no-empty-blocks, reason-string

contract BatchFacet is IBatchFacet, Modifiers {
    /// @inheritdoc IBatchFacet
    function batchCall(bytes[] calldata calls, bytes[] calldata prices) external payable usePyth(prices) {
        for (uint256 i; i < calls.length; i++) {
            (bool success, bytes memory retData) = address(this).delegatecall(calls[i]);
            if (!success) Revert(retData);
        }
    }

    /// @inheritdoc IBatchFacet
    function batchStaticCall(
        bytes[] calldata staticCalls,
        bytes[] calldata prices
    ) external payable returns (uint256 timestamp, bytes[] memory results) {
        try this.batchCallToError(staticCalls, prices) {
            revert();
        } catch Error(string memory reason) {
            revert(reason);
        } catch Panic(uint256 code) {
            revert err.Panicked(code);
        } catch (bytes memory errorData) {
            if (msg.value != 0) payable(msg.sender).transfer(msg.value);
            return this.decodeErrorData(errorData);
        }
    }

    /// @inheritdoc IBatchFacet
    function batchCallToError(
        bytes[] calldata calls,
        bytes[] calldata prices
    ) external payable usePyth(prices) returns (uint256, bytes[] memory results) {
        results = new bytes[](calls.length);

        for (uint256 i; i < calls.length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(calls[i]);
            if (!success) Revert(returnData);

            results[i] = returnData;
        }

        revert err.BatchResult(block.timestamp, results);
    }

    /// @inheritdoc IBatchFacet
    function decodeErrorData(bytes calldata errData) external pure returns (uint256 timestamp, bytes[] memory results) {
        return abi.decode(errData[4:], (uint256, bytes[]));
    }
}
