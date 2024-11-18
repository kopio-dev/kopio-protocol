// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {SCDPAssetIndexes} from "scdp/Types.sol";

interface ISCDPStateFacet {
    /**
     * @notice Get the total principal deposits of `account`
     * @param account The account.
     * @param collateral The deposit asset
     */
    function getAccountDepositSCDP(address account, address collateral) external view returns (uint256);

    /**
     * @notice Get the fees of `depositAsset` for `account`
     * @param account The account.
     * @param collateral The deposit asset
     */
    function getAccountFeesSCDP(address account, address collateral) external view returns (uint256);

    /**
     * @notice Get the value of fees for `account`
     * @param account The account.
     */
    function getAccountTotalFeesValueSCDP(address account) external view returns (uint256);

    /**
     * @notice Get the (principal) deposit value for `account`
     * @param account The account.
     * @param collateral The deposit asset
     */
    function getAccountDepositValueSCDP(address account, address collateral) external view returns (uint256);

    function getAssetIndexesSCDP(address collateral) external view returns (SCDPAssetIndexes memory);

    /**
     * @notice Get the total collateral deposit value for `account`
     * @param account The account.
     */
    function getAccountTotalDepositsValueSCDP(address account) external view returns (uint256);

    /**
     * @notice Get the total collateral deposits for `collateral`
     */
    function getDepositsSCDP(address collateral) external view returns (uint256);

    /**
     * @notice Get the total collateral swap deposits for `collateral`
     */
    function getSwapDepositsSCDP(address collateral) external view returns (uint256);

    /**
     * @notice Get the total deposit value of `collateral`
     * @param collateral The collateral asset
     * @param noFactors ignore factors when calculating collateral and debt value.
     */
    function getCollateralValueSCDP(address collateral, bool noFactors) external view returns (uint256);

    /**
     * @notice Get the total collateral value, oracle precision
     * @param noFactors ignore factors when calculating collateral value.
     */
    function getTotalCollateralValueSCDP(bool noFactors) external view returns (uint256);

    /**
     * @notice Get all pool collateral assets
     */
    function getCollateralsSCDP() external view returns (address[] memory);

    /**
     * @notice Get available assets
     */
    function getKopiosSCDP() external view returns (address[] memory);

    /**
     * @notice Get the debt value of `kopio`
     * @param asset address of the asset
     */
    function getDebtSCDP(address asset) external view returns (uint256);

    /**
     * @notice Get the debt value of `kopio`
     * @param asset address of the asset
     * @param noFactors ignore factors when calculating collateral and debt value.
     */
    function getDebtValueSCDP(address asset, bool noFactors) external view returns (uint256);

    /**
     * @notice Get the total debt value of kopio in oracle precision
     * @param noFactors ignore factors when calculating debt value.
     */
    function getTotalDebtValueSCDP(bool noFactors) external view returns (uint256);

    /**
     * @notice Get enabled state of asset
     */
    function getGlobalDepositEnabled(address asset) external view returns (bool);

    /**
     * @notice Check if `assetIn` can be swapped to `assetOut`
     * @param assetIn asset to give
     * @param assetOut asset to receive
     */
    function getRouteEnabled(address assetIn, address assetOut) external view returns (bool);

    function getSwapEnabled(address addr) external view returns (bool);

    function getGlobalCollateralRatio() external view returns (uint256);
}
