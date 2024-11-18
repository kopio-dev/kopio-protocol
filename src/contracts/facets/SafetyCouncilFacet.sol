// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {id, err} from "common/Errors.sol";
import {Role, Enums} from "common/Constants.sol";
import {SafetyState, Pause} from "common/Types.sol";
import {Modifiers} from "common/Modifiers.sol";
import {ISafetyCouncilFacet} from "interfaces/ISafetyCouncilFacet.sol";
import {cs} from "common/State.sol";

import {MEvent} from "icdp/Event.sol";

/* solhint-disable not-rely-on-time */

/**
 * @author the kopio project
 * @title SafetyCouncilFacet - protocol safety controls
 * @notice `Role.SAFETY_COUNCIL` must be a multisig.
 */
contract SafetyCouncilFacet is Modifiers, ISafetyCouncilFacet {
    /// @inheritdoc ISafetyCouncilFacet
    function toggleAssetsPaused(
        address[] calldata assets,
        Enums.Action action,
        bool timed,
        uint256 duration
    ) external override onlyRole(Role.SAFETY_COUNCIL) {
        /// @dev loop through `assets` - be it kopio or collateral
        for (uint256 i; i < assets.length; i++) {
            address assetAddr = assets[i];
            // Revert if asset is invalid
            if (!cs().assets[assetAddr].exists()) revert err.VOID_ASSET();

            // Get the safety state
            SafetyState memory safetyState = cs().safetyState[assetAddr][action];
            // Flip the previous value
            bool willPause = !safetyState.pause.enabled;

            if (willPause) {
                cs().safetyStateSet = true;
            }

            // Update the state for this asset
            cs().safetyState[assetAddr][action].pause = Pause(
                willPause,
                block.timestamp,
                timed ? block.timestamp + duration : 0
            );
            // Emit the actions taken
            emit MEvent.SafetyStateChange(action, id(assetAddr).symbol, assetAddr, willPause ? "paused" : "unpaused");
        }
    }

    /// @inheritdoc ISafetyCouncilFacet
    function setSafetyStateSet(bool val) external override onlyRole(Role.SAFETY_COUNCIL) {
        cs().safetyStateSet = val;
    }

    /// @inheritdoc ISafetyCouncilFacet
    function safetyStateSet() external view override returns (bool) {
        return cs().safetyStateSet;
    }

    /// @inheritdoc ISafetyCouncilFacet
    function safetyStateFor(address asset, Enums.Action action) external view override returns (SafetyState memory) {
        return cs().safetyState[asset][action];
    }

    /// @inheritdoc ISafetyCouncilFacet
    function assetActionPaused(Enums.Action action, address asset) external view returns (bool) {
        return cs().safetyState[asset][action].pause.enabled;
    }
}
