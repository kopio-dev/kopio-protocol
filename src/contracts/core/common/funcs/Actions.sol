// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {Strings} from "vendor/Strings.sol";
import {sdi} from "scdp/State.sol";
import {IKopioIssuer} from "interfaces/IKopioIssuer.sol";
import {Asset} from "common/Types.sol";
import {id, err} from "common/Errors.sol";
import {cs} from "common/State.sol";

using Strings for bytes32;

/* -------------------------------------------------------------------------- */
/*                                   Actions                                  */
/* -------------------------------------------------------------------------- */

/// @notice Burn assets with share already known.
/// @param amount The amount being burned
/// @param from The account to burn assets from.
/// @param share The share token of asset being burned.
function burnAssets(uint256 amount, address from, address share) returns (uint256 burned) {
    burned = IKopioIssuer(share).destroy(amount, from);
    if (burned == 0) revert err.ZERO_BURN(id(share));
}

/// @notice Mint assets with share already known.
/// @param amount The asset amount being minted
/// @param to The account receiving minted assets.
/// @param share The share token of the minted asset.
function mintAssets(uint256 amount, address to, address share) returns (uint256 minted) {
    minted = IKopioIssuer(share).issue(amount, to);
    if (minted == 0) revert err.ZERO_MINT(id(share));
}

/// @notice Repay SCDP swap debt.
/// @param cfg the asset being repaid
/// @param amount the asset amount being burned
/// @param from the account to burn assets from
/// @return burned Normalized amount of burned assets.
function burnSCDP(Asset storage cfg, uint256 amount, address from) returns (uint256 burned) {
    burned = burnAssets(amount, from, cfg.share);

    uint256 sdiBurned = cfg.debtToSDI(amount, false);
    if (sdiBurned > sdi().totalDebt) {
        if ((sdiBurned - sdi().totalDebt) > 10 ** cs().oracleDecimals) {
            revert err.SDI_DEBT_REPAY_OVERFLOW(sdi().totalDebt, sdiBurned);
        }
        sdi().totalDebt = 0;
    } else {
        sdi().totalDebt -= sdiBurned;
    }
}

/// @notice Mint assets from SCDP swap.
/// @notice Reverts if market for asset is not open.
/// @param cfg the asset requested
/// @param amount the asset amount requested
/// @param to the account to mint the assets to
/// @return issued Normalized amount of minted assets.
function mintSCDP(Asset storage cfg, uint256 amount, address to) returns (uint256 issued) {
    if (!cfg.isMarketOpen()) revert err.MARKET_CLOSED(id(cfg.share), cfg.ticker.toString());
    issued = mintAssets(amount, to, cfg.share);
    unchecked {
        sdi().totalDebt += cfg.debtToSDI(amount, false);
    }
}
