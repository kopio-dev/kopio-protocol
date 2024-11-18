// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {MAccounts} from "./funcs/Accounts.sol";
import {MCore} from "./funcs/Core.sol";

using MAccounts for ICDPState global;
using MCore for ICDPState global;

/**
 * @title Storage for the ICDP.
 * @author the kopio project
 */
struct ICDPState {
    mapping(address account => address[]) collateralsOf;
    mapping(address account => mapping(address collateral => uint256)) deposits;
    mapping(address account => mapping(address kopio => uint256)) debt;
    mapping(address account => address[]) mints;
    /* --------------------------------- Assets --------------------------------- */
    address[] kopios;
    address[] collaterals;
    address feeRecipient;
    /// @notice max liquidation ratio, this is the max collateral ratio liquidations can liquidate to.
    uint32 maxLiquidationRatio;
    /// @notice minimum ratio of collateral to debt that can be taken by direct action.
    uint32 minCollateralRatio;
    /// @notice collateralization ratio at which positions may be liquidated.
    uint32 liquidationThreshold;
    /// @notice minimum debt value of a single account.
    uint256 minDebtValue;
}

// keccak256(abi.encode(uint256(keccak256("kopio.slot.icdp")) - 1)) & ~bytes32(uint256(0xff));
bytes32 constant ICDP_SLOT = 0xa8f8248bd2623d2ac4f9086213698319675a053d994914e3b428d54e1b894d00;

function ms() pure returns (ICDPState storage state) {
    bytes32 position = ICDP_SLOT;
    assembly {
        state.slot := position
    }
}
