// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {ds} from "diamond/State.sol";
import {id, err} from "common/Errors.sol";
import {Auth} from "common/Auth.sol";
import {Role, Constants, Enums} from "common/Constants.sol";
import {Asset} from "common/Types.sol";
import {handlePythUpdate} from "common/funcs/Utils.sol";
import {cs, CommonState} from "common/State.sol";
import {WadRay} from "vendor/WadRay.sol";
import {scdp} from "scdp/State.sol";

library LibModifiers {
    /// @dev Simple check for the enabled flag
    /// @param addr The address of the asset.
    /// @param action The action to this is called from.
    /// @return asset The asset struct.
    function onlyUnpaused(
        CommonState storage self,
        address addr,
        Enums.Action action
    ) internal view returns (Asset storage asset) {
        if (self.safetyStateSet && self.safetyState[addr][action].pause.enabled) {
            revert err.ASSET_PAUSED_FOR_THIS_ACTION(id(addr), uint8(action));
        }
        return self.assets[addr];
    }

    function onlyExistingAsset(CommonState storage self, address addr) internal view returns (Asset storage asset) {
        asset = self.assets[addr];
        if (!asset.exists()) {
            revert err.INVALID_ASSET(addr);
        }
    }

    /**
     * @notice Reverts if address is not a collateral asset.
     * @param addr The address of the asset.
     * @return cfg The asset struct.
     */
    function onlyCollateral(CommonState storage self, address addr) internal view returns (Asset storage cfg) {
        cfg = self.assets[addr];
        if (!cfg.isCollateral) {
            revert err.NOT_COLLATERAL(id(addr));
        }
    }

    function onlyCollateral(
        CommonState storage self,
        address addr,
        Enums.Action action
    ) internal view returns (Asset storage cfg) {
        cfg = onlyUnpaused(self, addr, action);
        if (!cfg.isCollateral) {
            revert err.NOT_COLLATERAL(id(addr));
        }
    }

    /**
     * @notice Ensure asset returned is mintable.
     * @param addr The address of the asset.
     * @return cfg The asset struct.
     */
    function onlyKopio(CommonState storage self, address addr) internal view returns (Asset storage cfg) {
        cfg = self.assets[addr];
        if (!cfg.isKopio) {
            revert err.NOT_MINTABLE(id(addr));
        }
    }

    function onlyKopio(CommonState storage self, address addr, Enums.Action action) internal view returns (Asset storage cfg) {
        cfg = onlyUnpaused(self, addr, action);
        if (!cfg.isKopio) {
            revert err.NOT_MINTABLE(id(addr));
        }
    }

    /**
     * @notice Reverts if address is not depositable to SCDP.
     * @param addr The address of the asset.
     * @return cfg The asset struct.
     */
    function onlyGlobalDepositable(CommonState storage self, address addr) internal view returns (Asset storage cfg) {
        cfg = self.assets[addr];
        if (!cfg.isGlobalDepositable) {
            revert err.NOT_DEPOSITABLE(id(addr));
        }
    }

    /**
     * @notice Reverts if asset is not the feeAsset and does not have any shared fees accumulated.
     * @notice Assets that pass are guaranteed to never have zero liquidity index.
     * @param addr address of the asset.
     * @return cfg the config struct.
     */
    function onlyCumulated(CommonState storage self, address addr) internal view returns (Asset storage cfg) {
        cfg = self.assets[addr];
        if (!cfg.isGlobalDepositable || (addr != scdp().feeAsset && scdp().assetIndexes[addr].currFeeIndex <= WadRay.RAY)) {
            revert err.NOT_CUMULATED(id(addr));
        }
    }

    function onlyCumulated(
        CommonState storage self,
        address addr,
        Enums.Action action
    ) internal view returns (Asset storage asset) {
        asset = onlyUnpaused(self, addr, action);
        if (!asset.isGlobalDepositable || (addr != scdp().feeAsset && scdp().assetIndexes[addr].currFeeIndex <= WadRay.RAY)) {
            revert err.NOT_CUMULATED(id(addr));
        }
    }

    /**
     * @notice Reverts if address is not swappable kopio.
     * @param addr address of the asset.
     * @return cfg the config struct.
     */
    function onlySwapMintable(CommonState storage self, address addr) internal view returns (Asset storage cfg) {
        cfg = self.assets[addr];
        if (!cfg.isSwapMintable) {
            revert err.NOT_SWAPPABLE(id(addr));
        }
    }

    function onlySwapMintable(
        CommonState storage self,
        address addr,
        Enums.Action action
    ) internal view returns (Asset storage cfg) {
        cfg = onlyUnpaused(self, addr, action);
        if (!cfg.isSwapMintable) {
            revert err.NOT_SWAPPABLE(id(addr));
        }
    }

    /**
     * @notice Reverts if address does not have any deposits.
     * @param addr address of the asset.
     * @return cfg asset config.
     * @dev main use is to check for deposits before removing it.
     */
    function onlyGlobalDeposited(CommonState storage self, address addr) internal view returns (Asset storage cfg) {
        cfg = self.assets[addr];
        if (scdp().assetIndexes[addr].currFeeIndex == 0) {
            revert err.NO_GLOBAL_DEPOSITS(id(addr));
        }
    }

    function onlyGlobalDeposited(
        CommonState storage self,
        address addr,
        Enums.Action action
    ) internal view returns (Asset storage cfg) {
        cfg = onlyUnpaused(self, addr, action);
        if (scdp().assetIndexes[addr].currFeeIndex == 0) {
            revert err.NO_GLOBAL_DEPOSITS(id(addr));
        }
    }

    function onlyCoverAsset(CommonState storage self, address addr) internal view returns (Asset storage cfg) {
        cfg = self.assets[addr];
        if (!cfg.isCoverAsset) {
            revert err.NOT_COVER_ASSET(id(addr));
        }
    }

    function onlyCoverAsset(
        CommonState storage self,
        address addr,
        Enums.Action action
    ) internal view returns (Asset storage cfg) {
        cfg = onlyUnpaused(self, addr, action);
        if (!cfg.isCoverAsset) {
            revert err.NOT_COVER_ASSET(id(addr));
        }
    }

    function onlyIncomeAsset(CommonState storage self, address addr) internal view returns (Asset storage cfg) {
        if (addr != scdp().feeAsset) revert err.NOT_SUPPORTED_YET();
        cfg = onlyGlobalDeposited(self, addr);
        if (!cfg.isGlobalDepositable) revert err.NOT_INCOME_ASSET(addr);
    }
}

contract Modifiers {
    /**
     * @dev Modifier that checks if the contract is initializing and if so, gives the caller the ADMIN role
     */
    modifier initializeAsAdmin() {
        if (ds().initializing != Constants.INITIALIZING) revert err.NOT_INITIALIZING();
        if (!Auth.hasRole(Role.ADMIN, msg.sender)) {
            Auth._grantRole(Role.ADMIN, msg.sender);
            _;
            Auth._revokeRole(Role.ADMIN, msg.sender);
        } else {
            _;
        }
    }
    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        Auth.checkRole(role);
        _;
    }

    /**
     * @notice Check for role if the condition is true.
     * @param _shouldCheckRole Should be checking the role.
     */
    modifier onlyRoleIf(bool _shouldCheckRole, bytes32 role) {
        if (_shouldCheckRole) {
            Auth.checkRole(role);
        }
        _;
    }

    modifier nonReentrant() {
        if (cs().entered == Constants.ENTERED) {
            revert err.CANNOT_RE_ENTER();
        }
        cs().entered = Constants.ENTERED;
        _;
        cs().entered = Constants.NOT_ENTERED;
    }

    modifier usePyth(bytes[] calldata prices) {
        handlePythUpdate(prices);
        _;
    }
}
