// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {SCDPAccountIndexes, SCDPAssetData, SCDPAssetIndexes, SCDPSeizeData} from "scdp/Types.sol";
import {SGlobal} from "scdp/funcs/Global.sol";
import {SDeposits} from "scdp/funcs/Deposits.sol";
import {SAccounts} from "scdp/funcs/Accounts.sol";
import {Swaps} from "scdp/funcs/Swap.sol";
import {SDebtIndex} from "scdp/funcs/SDI.sol";

using SGlobal for SCDPState global;
using SDeposits for SCDPState global;
using SAccounts for SCDPState global;
using Swaps for SCDPState global;
using SDebtIndex for SDIState global;

/**
 * @title Storage layout for the shared cdp state
 * @author the kopio project
 */
struct SCDPState {
    /// @notice Array of deposit assets which can be swapped
    address[] collaterals;
    /// @notice Array of kopio assets which can be swapped
    address[] kopios;
    mapping(address assetIn => mapping(address assetOut => bool)) isRoute;
    mapping(address asset => bool enabled) isEnabled;
    mapping(address asset => SCDPAssetData) assetData;
    mapping(address account => mapping(address collateral => uint256 amount)) deposits;
    mapping(address account => mapping(address collateral => uint256 amount)) depositsPrincipal;
    mapping(address collateral => SCDPAssetIndexes) assetIndexes;
    mapping(address account => mapping(address collateral => SCDPAccountIndexes)) accountIndexes;
    mapping(address account => mapping(uint256 liqIndex => SCDPSeizeData)) seizeEvents;
    /// @notice current income asset
    address feeAsset;
    /// @notice minimum ratio of collateral to debt.
    uint32 minCollateralRatio;
    /// @notice collateralization ratio at which positions may be liquidated.
    uint32 liquidationThreshold;
    /// @notice limits the liquidatable value of a position to a CR.
    uint32 maxLiquidationRatio;
}

struct SDIState {
    uint256 totalDebt;
    uint256 totalCover;
    address coverRecipient;
    /// @notice Threshold after cover can be performed.
    uint48 coverThreshold;
    /// @notice Incentive for covering debt
    uint48 coverIncentive;
    address[] coverAssets;
}

// keccak256(abi.encode(uint256(keccak256("kopio.slot.scdp")) - 1)) & ~bytes32(uint256(0xff));
bytes32 constant SCDP_SLOT = 0xd405b07e7e3f6f53febc8186644ff1e0824332653a01e9279bde7f3bfc6b7600;
// keccak256(abi.encode(uint256(keccak256("kopio.slot.sdi")) - 1)) & ~bytes32(uint256(0xff));
bytes32 constant SDI_SLOT = 0x815abab76eb0df79b12d9cc625bb13a185c396fdf9ccb04c9f8a7a4e9d419600;

function scdp() pure returns (SCDPState storage state) {
    bytes32 position = SCDP_SLOT;
    assembly {
        state.slot := position
    }
}

function sdi() pure returns (SDIState storage state) {
    bytes32 position = SDI_SLOT;
    assembly {
        state.slot := position
    }
}
