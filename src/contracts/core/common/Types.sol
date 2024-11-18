// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Assets} from "common/funcs/Assets.sol";
import {Enums} from "common/Constants.sol";
import {Prices} from "libs/Prices.sol";

using Assets for Asset global;
using Prices for OraclePrice global;

/* ========================================================================== */
/*                                   Structs                                  */
/* ========================================================================== */

/// @notice Oracle configuration mapped to a ticker.
struct Oracle {
    address feed;
    bytes32 pythId;
    uint256 staleTime;
    bool invertPyth;
    bool isClosable;
}

struct OraclePrice {
    uint256 answer;
    uint256 timestamp;
    uint256 staleTime;
    bool isStale;
    bool isZero;
    Enums.OracleType oracle;
    address feed;
    bytes32 pythId;
}

/// @notice Pyth-only configuration.
struct PythConfig {
    bytes32 pythId;
    uint256 staleTime;
    bool invertPyth;
    bool isClosable;
}

/**
 * @notice Feed configuration.
 * @param oracleIds two supported oracle types.
 * @param feeds the feeds - eg, pyth / redstone will be address(0).
 * @param staleTimes stale times for the feeds.
 * @param pythId pyth id.
 * @param invertPyth invert the pyth price.
 * @param isClosable is market for ticker closable.
 */
struct TickerOracles {
    Enums.OracleType[2] oracleIds;
    address[2] feeds;
    uint256[2] staleTimes;
    bytes32 pythId;
    bool invertPyth;
    bool isClosable;
}

/**
 * @title Asset configuration
 * @author the kopio project
 * @notice all assets in the protocol share this configuration.
 * @notice ticker is shared eg. kETH and WETH use "ETH"
 * @dev Percentages use 2 decimals: 1e4 (10000) == 100.00%. See {PercentageMath.sol}.
 * @dev Noting the percentage value of uint16 caps at 655.36%.
 */
struct Asset {
    /// @notice Underlying asset ticker (eg. "ETH")
    bytes32 ticker;
    /// @notice The share address, if any.
    address share;
    /// @notice Oracles for this asset.
    /// @notice 0 is the primary price source, 1 being the reference price for deviation checks.
    Enums.OracleType[2] oracles;
    /// @notice Decreases collateral valuation, Always <= 100% or 1e4.
    uint16 factor;
    /// @notice Increases debt valution, >= 100% or 1e4.
    uint16 dFactor;
    /// @notice Fee percent for opening a debt position, deducted from collaterals.
    uint16 openFee;
    /// @notice Fee percent for closing a debt position, deducted from collaterals.
    uint16 closeFee;
    /// @notice Liquidation incentive when seized as collateral.
    uint16 liqIncentive;
    /// @notice Supply cap of the ICDP.
    uint256 mintLimit;
    /// @notice Supply cap of the SCDP.
    uint256 mintLimitSCDP;
    /// @notice Limit for SCDP deposit amount
    uint256 depositLimitSCDP;
    /// @notice Fee percent for swaps that sell the asset.
    uint16 swapInFee;
    /// @notice Fee percent for swaps that buy the asset.
    uint16 swapOutFee;
    /// @notice Protocol share of swap fees. Cap 50% == a.feeShare + b.feeShare <= 100%.
    uint16 protocolFeeShareSCDP;
    /// @notice Liquidation incentive for kopio debt in the SCDP.
    /// @notice Discounts the seized collateral in SCDP liquidations.
    uint16 liqIncentiveSCDP;
    /// @notice Set once during setup - kopios have 18 decimals.
    uint8 decimals;
    /// @notice Asset can be deposited as ICDP collateral.
    bool isCollateral;
    /// @notice Asset can be minted from the ICDP.
    bool isKopio;
    /// @notice Asset can be explicitly deposited into the SCDP.
    bool isGlobalDepositable;
    /// @notice Asset can be minted for swap output in the SCDP.
    bool isSwapMintable;
    /// @notice Asset belongs to total collateral value calculation in the SCDP.
    /// @notice kopios default to true due to indirect deposits from swaps.
    bool isGlobalCollateral;
    /// @notice Asset can be used to cover SCDP debt.
    bool isCoverAsset;
}

/// @notice The access control role data.
struct RoleData {
    mapping(address => bool) members;
    bytes32 adminRole;
}

/// @notice Variables used for calculating the max liquidation value.
struct MaxLiqVars {
    Asset collateral;
    uint256 accountCollateralValue;
    uint256 minCollateralValue;
    uint256 seizeCollateralAccountValue;
    uint192 minDebtValue;
    uint32 gainFactor;
    uint32 maxLiquidationRatio;
    uint32 debtFactor;
}

struct MaxLiqInfo {
    address account;
    address seizeAssetAddr;
    address repayAssetAddr;
    uint256 repayValue;
    uint256 repayAmount;
    uint256 seizeAmount;
    uint256 seizeValue;
    uint256 repayAssetPrice;
    uint256 repayAssetIndex;
    uint256 seizeAssetPrice;
    uint256 seizeAssetIndex;
}

/// @notice Configuration for pausing `Action`
struct Pause {
    bool enabled;
    uint256 timestamp0;
    uint256 timestamp1;
}

/// @notice Safety configuration for assets
struct SafetyState {
    Pause pause;
}

/**
 * @notice Initialization arguments for common values
 */
struct CommonInitializer {
    address admin;
    address council;
    address treasury;
    uint16 maxPriceDeviationPct;
    uint8 oracleDecimals;
    uint32 sequencerGracePeriodTime;
    address sequencerUptimeFeed;
    address pythEp;
    address marketStatusProvider;
    address kopioCLV3;
}

struct AssetOracles {
    Enums.OracleType[2] ids;
    Oracle[2] cfgs;
}
