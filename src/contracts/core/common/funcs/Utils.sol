// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {PercentageMath} from "vendor/PercentageMath.sol";
import {WadRay} from "vendor/WadRay.sol";
import {IAggregatorV3} from "kopio/vendor/IAggregatorV3.sol";
import {IPyth} from "kopio/vendor/Pyth.sol";
import {cs} from "common/State.sol";

using PercentageMath for uint256;
using WadRay for uint256;

/**
 * @notice Checks if the L2 sequencer is up.
 * 1 means the sequencer is down, 0 means the sequencer is up.
 * @param _uptimeFeed The address of the uptime feed.
 * @param _gracePeriod The grace period in seconds.
 * @return bool returns true/false if the sequencer is up/not.
 */
function isSequencerUp(address _uptimeFeed, uint256 _gracePeriod) view returns (bool) {
    bool up = true;
    if (_uptimeFeed != address(0)) {
        (, int256 answer, uint256 startedAt, , ) = IAggregatorV3(_uptimeFeed).latestRoundData();

        up = answer == 0;
        if (!up) {
            return false;
        }
        // Make sure the grace period has passed after the
        // sequencer is back up.
        if (block.timestamp - startedAt < _gracePeriod) {
            return false;
        }
    }
    return up;
}

/**
 * If update data exists, updates the pyth prices. Does nothing when data is empty.
 * @param _updateData The update data.
 */
function handlePythUpdate(bytes[] calldata _updateData) {
    if (_updateData.length == 0) return;
    IPyth(cs().pythRelayer).updatePriceFeeds(_updateData);
}
