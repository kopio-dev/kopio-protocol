// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Role} from "common/Constants.sol";
import {Modifiers} from "common/Modifiers.sol";

import {IDiamondCutFacet, IExtendedDiamondCutFacet} from "interfaces/IDiamondCutFacet.sol";
import {FacetCut, Initializer} from "diamond/Types.sol";
import {DSModifiers} from "diamond/DSModifiers.sol";
import {DSCore} from "diamond/Logic.sol";

/**
 * @title EIP2535-pattern upgrades.
 * @author Nick Mudge
 * @author the kopio project
 * @notice Reference implementation of diamondCut. Extended to allow executing initializers without cuts.
 */
contract DiamondCutFacet is IExtendedDiamondCutFacet, DSModifiers, Modifiers {
    /// @inheritdoc IDiamondCutFacet
    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external onlyRole(Role.DEFAULT_ADMIN) {
        DSCore.cut(cuts, init, data);
    }

    /// @inheritdoc IExtendedDiamondCutFacet
    function executeInitializer(address init, bytes calldata data) external onlyRole(Role.DEFAULT_ADMIN) {
        DSCore.exec(init, data);
    }

    /// @inheritdoc IExtendedDiamondCutFacet
    function executeInitializers(Initializer[] calldata inits) external onlyRole(Role.DEFAULT_ADMIN) {
        for (uint256 i; i < inits.length; ) {
            DSCore.exec(inits[i].initContract, inits[i].initData);
            unchecked {
                i++;
            }
        }
    }
}
