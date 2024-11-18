// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC165} from "kopio/vendor/IERC165.sol";
import {IDiamondLoupeFacet} from "interfaces/IDiamondLoupeFacet.sol";
import {IDiamondStateFacet} from "interfaces/IDiamondStateFacet.sol";
import {IDiamondCutFacet, IExtendedDiamondCutFacet} from "interfaces/IDiamondCutFacet.sol";

import {Meta} from "libs/Meta.sol";
import {Auth} from "common/Auth.sol";
import {Role, Constants} from "common/Constants.sol";

import {ds, DiamondState} from "diamond/State.sol";
import {DTypes, FacetCut, FacetCutAction, Initializer} from "diamond/Types.sol";

library DSCore {
    using DSCore for DiamondState;

    /**
     * @notice Setup the DiamondState, add initial facets and execute all initializers.
     * @param _initialFacets Facets to add to the diamond.
     * @param _initializers Initializer contracts to execute.
     * @param _contractOwner Address to set as the contract owner.
     */
    function create(FacetCut[] memory _initialFacets, Initializer[] memory _initializers, address _contractOwner) internal {
        DiamondState storage self = ds();
        if (ds().initialized) revert DTypes.DIAMOND_ALREADY_INITIALIZED(0, self.storageVersion);
        self.diamondDomainSeparator = Meta.domainSeparator("Kopio Protocol", "V1");
        self.contractOwner = _contractOwner;

        self.supportedInterfaces[type(IDiamondLoupeFacet).interfaceId] = true;
        self.supportedInterfaces[type(IERC165).interfaceId] = true;
        self.supportedInterfaces[type(IDiamondCutFacet).interfaceId] = true;
        self.supportedInterfaces[type(IDiamondStateFacet).interfaceId] = true;
        self.supportedInterfaces[type(IExtendedDiamondCutFacet).interfaceId] = true;

        emit DTypes.OwnershipTransferred(address(0), _contractOwner);

        Auth._grantRole(Role.DEFAULT_ADMIN, _contractOwner);
        Auth._grantRole(Role.ADMIN, _contractOwner);

        // only cut facets in
        cut(_initialFacets, address(0), "");

        // initializers if there are any
        for (uint256 i; i < _initializers.length; i++) {
            exec(_initializers[i].initContract, _initializers[i].initData);
        }

        self.initialized = true;
    }

    /**
     * @notice Execute some logic on a contract through delegatecall.
     * @param init Contract to delegatecall.
     * @param data Data to pass into the delegatecall.
     */
    function exec(address init, bytes memory data) internal {
        if (init == address(0) && data.length > 0) {
            revert DTypes.DIAMOND_INIT_DATA_PROVIDED_BUT_INIT_ADDRESS_WAS_ZERO(data);
        }

        if (init != address(0)) {
            if (data.length == 0) {
                revert DTypes.DIAMOND_INIT_ADDRESS_PROVIDED_BUT_INIT_DATA_WAS_EMPTY(init);
            }
            Meta.enforceHasContractCode(init);

            ds().initializing = Constants.INITIALIZING;
            // solhint-disable-next-line avoid-low-level-calls
            (bool success, bytes memory err) = init.delegatecall(data);
            ds().initializing = Constants.NOT_INITIALIZING;

            if (!success) {
                if (err.length == 0) revert DTypes.DIAMOND_INIT_FAILED(init, data);
                assembly {
                    revert(add(32, err), mload(err))
                }
            }
            emit DTypes.InitializerExecuted(
                ++ds().storageVersion,
                msg.sender,
                ds().contractOwner,
                init,
                data,
                ds().facetAddresses.length,
                block.number,
                block.timestamp
            );
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                            Diamond Functionality                           */
    /* -------------------------------------------------------------------------- */

    function cut(FacetCut[] memory cuts, address init, bytes memory data) internal {
        DiamondState storage self = ds();

        for (uint256 idx; idx < cuts.length; idx++) {
            FacetCutAction action = cuts[idx].action;
            if (action == FacetCutAction.Add) {
                self.addFunctions(cuts[idx].facetAddress, cuts[idx].functionSelectors);
            } else if (action == FacetCutAction.Replace) {
                self.replaceFunctions(cuts[idx].facetAddress, cuts[idx].functionSelectors);
            } else if (action == FacetCutAction.Remove) {
                self.removeFunctions(cuts[idx].facetAddress, cuts[idx].functionSelectors);
            } else {
                revert DTypes.DIAMOND_CUT_ACTION_WAS_NOT_ADD_REPLACE_REMOVE();
            }
        }

        emit DTypes.DiamondCut(cuts, init, data);
        exec(init, data);
    }

    function addFunctions(DiamondState storage self, address facet, bytes4[] memory funcs) internal {
        if (funcs.length == 0) revert DTypes.DIAMOND_NO_FACET_SELECTORS(facet);
        if (facet == address(0)) {
            revert DTypes.DIAMOND_FACET_ADDRESS_CANNOT_BE_ZERO_WHEN_ADDING_FUNCTIONS(funcs);
        }

        uint96 selectorPosition = uint96(self.facetFunctionSelectors[facet].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            self.addFacet(facet);
        }
        for (uint256 selectorIndex; selectorIndex < funcs.length; selectorIndex++) {
            bytes4 selector = funcs[selectorIndex];
            address oldFacetAddress = self.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacetAddress != address(0)) {
                revert DTypes.DIAMOND_FUNCTION_ALREADY_EXISTS(facet, oldFacetAddress, selector);
            }
            self.addFunction(selector, selectorPosition, facet);
            selectorPosition++;
        }
    }

    function replaceFunctions(DiamondState storage self, address facet, bytes4[] memory funcs) internal {
        if (funcs.length == 0) revert DTypes.DIAMOND_NO_FACET_SELECTORS(facet);
        if (facet == address(0)) revert DTypes.DIAMOND_FACET_ADDRESS_CANNOT_BE_ZERO_WHEN_REPLACING_FUNCTIONS(funcs);

        uint96 selectorPosition = uint96(self.facetFunctionSelectors[facet].functionSelectors.length);
        // add new facet address if it does not exist
        if (selectorPosition == 0) {
            self.addFacet(facet);
        }
        for (uint256 selectorIndex; selectorIndex < funcs.length; selectorIndex++) {
            bytes4 selector = funcs[selectorIndex];
            address oldFacet = self.selectorToFacetAndPosition[selector].facetAddress;
            if (oldFacet == facet) revert DTypes.DIAMOND_REPLACE_FUNCTION_NEW_FACET_IS_SAME_AS_OLD(facet, selector);
            self.removeFunction(oldFacet, selector);
            self.addFunction(selector, selectorPosition, facet);
            selectorPosition++;
        }
    }

    function removeFunctions(DiamondState storage self, address facet, bytes4[] memory funcs) internal {
        if (funcs.length == 0) revert DTypes.DIAMOND_NO_FACET_SELECTORS(facet);
        // if function does not exist then do nothing and return
        if (facet != address(0)) {
            revert DTypes.DIAMOND_FACET_ADDRESS_MUST_BE_ZERO_WHEN_REMOVING_FUNCTIONS(facet, funcs);
        }
        for (uint256 idx; idx < funcs.length; idx++) {
            bytes4 selector = funcs[idx];
            address oldFacetAddress = self.selectorToFacetAndPosition[selector].facetAddress;
            self.removeFunction(oldFacetAddress, selector);
        }
    }

    function addFacet(DiamondState storage self, address facet) internal {
        Meta.enforceHasContractCode(facet);
        self.facetFunctionSelectors[facet].facetAddressPosition = self.facetAddresses.length;
        self.facetAddresses.push(facet);
    }

    function addFunction(DiamondState storage self, bytes4 selector, uint96 selectorIdx, address facet) internal {
        self.selectorToFacetAndPosition[selector].functionSelectorPosition = selectorIdx;
        self.facetFunctionSelectors[facet].functionSelectors.push(selector);
        self.selectorToFacetAndPosition[selector].facetAddress = facet;
    }

    function removeFunction(DiamondState storage self, address facet, bytes4 selector) internal {
        if (facet == address(0)) {
            revert DTypes.DIAMOND_FACET_ADDRESS_CANNOT_BE_ZERO_WHEN_REMOVING_ONE_FUNCTION(selector);
        }
        // replace selector with last selector, then delete last selector
        uint256 selectorIdx = self.selectorToFacetAndPosition[selector].functionSelectorPosition;
        uint256 lastSelectorIdx = self.facetFunctionSelectors[facet].functionSelectors.length - 1;
        // if not the same then replace selector with lastSelector
        if (selectorIdx != lastSelectorIdx) {
            bytes4 lastSelector = self.facetFunctionSelectors[facet].functionSelectors[lastSelectorIdx];
            self.facetFunctionSelectors[facet].functionSelectors[selectorIdx] = lastSelector;
            self.selectorToFacetAndPosition[lastSelector].functionSelectorPosition = uint96(selectorIdx);
        }
        // delete the last selector
        self.facetFunctionSelectors[facet].functionSelectors.pop();
        delete self.selectorToFacetAndPosition[selector];

        // if no more functionSelectors for facet address then delete the facet address
        if (lastSelectorIdx == 0) {
            // replace facet address with last facet address and delete last facet address
            uint256 lastFacetAddressPosition = self.facetAddresses.length - 1;
            uint256 facetAddressPosition = self.facetFunctionSelectors[facet].facetAddressPosition;
            if (facetAddressPosition != lastFacetAddressPosition) {
                address lastFacetAddress = self.facetAddresses[lastFacetAddressPosition];
                self.facetAddresses[facetAddressPosition] = lastFacetAddress;
                self.facetFunctionSelectors[lastFacetAddress].facetAddressPosition = facetAddressPosition;
            }
            self.facetAddresses.pop();
            delete self.facetFunctionSelectors[facet].facetAddressPosition;
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Ownership                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Initiate ownership transfer to a new address
     * @param _newOwner address that is set as the pending new owner
     * @notice caller must be the current contract owner
     */
    function initiateOwnershipTransfer(DiamondState storage self, address _newOwner) internal {
        if (Meta.msgSender() != self.contractOwner) revert DTypes.NOT_DIAMOND_OWNER(Meta.msgSender(), self.contractOwner);
        if (_newOwner == address(0)) revert DTypes.NEW_OWNER_CANNOT_BE_ZERO_ADDRESS();

        self.pendingOwner = _newOwner;

        emit DTypes.PendingOwnershipTransfer(self.contractOwner, _newOwner);
    }

    /**
     * @dev Transfer the ownership to the new pending owner
     * @notice caller must be the pending owner
     */
    function finalizeOwnershipTransfer(DiamondState storage self) internal {
        address sender = Meta.msgSender();
        if (sender != self.pendingOwner) revert DTypes.NOT_PENDING_DIAMOND_OWNER(sender, self.pendingOwner);

        self.contractOwner = self.pendingOwner;
        self.pendingOwner = address(0);

        emit DTypes.OwnershipTransferred(self.contractOwner, sender);
    }
}
