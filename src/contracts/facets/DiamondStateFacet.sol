// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDiamondStateFacet} from "interfaces/IDiamondStateFacet.sol";
import {DSModifiers} from "diamond/DSModifiers.sol";
import {DSCore} from "diamond/Logic.sol";
import {ds, DiamondState} from "diamond/State.sol";

contract DiamondStateFacet is IDiamondStateFacet, DSModifiers {
    using DSCore for DiamondState;

    /// @inheritdoc IDiamondStateFacet
    function transferOwnership(address _newOwner) external override {
        ds().initiateOwnershipTransfer(_newOwner);
    }

    /// @inheritdoc IDiamondStateFacet
    function acceptOwnership() external override {
        ds().finalizeOwnershipTransfer();
    }

    /// @inheritdoc IDiamondStateFacet
    function owner() external view override returns (address owner_) {
        return ds().contractOwner;
    }

    /// @inheritdoc IDiamondStateFacet
    function pendingOwner() external view override returns (address pendingOwner_) {
        return ds().pendingOwner;
    }

    function initialized() external view returns (bool) {
        return ds().initialized;
    }

    /// @inheritdoc IDiamondStateFacet
    function domainSeparator() external view returns (bytes32) {
        return ds().diamondDomainSeparator;
    }

    /// @inheritdoc IDiamondStateFacet
    function getStorageVersion() external view returns (uint256) {
        return ds().storageVersion;
    }
}
