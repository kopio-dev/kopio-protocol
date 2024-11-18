// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

/* ========================================================================== */
/*                                   STRUCTS                                  */
/* ========================================================================== */
/**
 * @notice Internal for _liquidateAssets.
 * @param account The account being liquidated.
 * @param repayAmount amount being repaid.
 * @param seizeAmount amount being seized.
 * @param repayKopio kopio being repaid.
 * @param seizeAsset collateral asset to seize.
 */
struct LiquidateExecution {
    address account;
    uint256 repayAmount;
    uint256 seizeAmount;
    address kopio;
    address collateral;
}

struct ICDPAccount {
    uint256 totalDebtValue;
    uint256 totalCollateralValue;
    uint256 collateralRatio;
}
/**
 * @notice Initializer values for the ICDP.
 */
struct ICDPInitializer {
    uint32 liquidationThreshold;
    uint32 minCollateralRatio;
    uint256 minDebtValue;
}

/**
 * @notice Configurable parameters in the ICDP.
 */
struct ICDPParams {
    uint32 minCollateralRatio;
    uint32 liquidationThreshold;
    uint32 maxLiquidationRatio;
    uint256 minDebtValue;
}
