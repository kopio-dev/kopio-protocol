// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {ICDPAccount} from "icdp/Types.sol";
import {Enums} from "common/Constants.sol";

interface IICDPAccountStateFacet {
    // ExpectedFeeRuntimeInfo is used for stack size optimization
    struct ExpectedFeeRuntimeInfo {
        address[] assets;
        uint256[] amounts;
        uint256 collateralTypeCount;
    }

    /**
     * @notice Calculates if an account's current collateral value is under its minimum collateral value
     * @param account The account to check.
     * @return bool whether the account is liquidatable.
     */
    function getAccountLiquidatable(address account) external view returns (bool);

    /**
     * @notice Get account position in the ICDP.
     * @param account account to get state for.
     * @return ICDPAccount Total debt value, total collateral value and collateral ratio.
     */
    function getAccountState(address account) external view returns (ICDPAccount memory);

    /**
     * @notice Gets an array of assets the account has minted.
     * @param account The account to get the minted assets for.
     * @return address[] Array of addresses the account has minted.
     */
    function getAccountMintedAssets(address account) external view returns (address[] memory);

    /**
     * @notice Gets the accounts minted index for an asset.
     * @param account the account
     * @param asset the minted asset
     * @return index index for the asset
     */
    function getAccountMintIndex(address account, address asset) external view returns (uint256);

    /**
     * @notice Gets the total debt value in USD for an account.
     * @notice Adjusted is multiplied by the dFactor.
     * @param account account to get the debt value for.
     * @return value unfactored value of debt.
     * @return valueAdjusted factored value of debt.
     */
    function getAccountTotalDebtValues(address account) external view returns (uint256 value, uint256 valueAdjusted);

    /**
     * @notice Gets the total debt value in USD for the account.
     * @param account account to use
     * @return uint256 total debt value of `account`.
     */
    function getAccountTotalDebtValue(address account) external view returns (uint256);

    /**
     * @notice Get `account` debt amount for `_asset`
     * @param account account to get the amount for
     * @param asset kopio address
     * @return uint256 debt amount for `asset`
     */
    function getAccountDebtAmount(address account, address asset) external view returns (uint256);
    function getAccountDebtValue(address, address) external view returns (uint256);

    /**
     * @notice Gets the unfactored and factored collateral value of `asset` for `account`.
     * @param account account to get
     * @param asset collateral to check.
     * @return value unfactored collateral value
     * @return valueAdjusted factored collateral value
     * @return price asset price
     */
    function getAccountCollateralValues(
        address account,
        address asset
    ) external view returns (uint256 value, uint256 valueAdjusted, uint256 price);

    /**
     * @notice Gets the factored collateral value of an account.
     * @param account Account to calculate the collateral value for.
     * @return valueAdjusted Collateral value of a particular account.
     */
    function getAccountTotalCollateralValue(address account) external view returns (uint256 valueAdjusted);

    /**
     * @notice Gets the unfactored and factored collateral value of `account`.
     * @param account account to get
     * @return value unfactored total collateral value
     * @return valueAdjusted factored total collateral value
     */
    function getAccountTotalCollateralValues(address account) external view returns (uint256 value, uint256 valueAdjusted);

    /**
     * @notice Get an account's minimum collateral value required
     * to back its debt at given collateralization ratio.
     * @notice Collateral value under minimum required are considered unhealthy,
     * @notice Collateral value under liquidation threshold will be liquidatable.
     * @param account account to get
     * @param ratio the collateralization ratio required
     * @return uint256 minimum collateral value for the account.
     */
    function getAccountMinCollateralAtRatio(address account, uint32 ratio) external view returns (uint256);

    /**
     * @notice Gets the collateral ratio of an account
     * @return ratio the collateral ratio
     */
    function getAccountCollateralRatio(address account) external view returns (uint256 ratio);

    /**
     * @notice Get a list of collateral ratios
     * @return ratios collateral ratios of `accounts`
     */
    function getAccountCollateralRatios(address[] memory accounts) external view returns (uint256[] memory);

    /**
     * @notice Gets the deposit index for the collateral and account.
     * @param account account to use
     * @param collateral the collateral asset
     * @return i Index of the minted collateral asset.
     */
    function getAccountDepositIndex(address account, address collateral) external view returns (uint256 i);

    /**
     * @notice Lists all deposited collaterals for account.
     * @param account account to use
     * @return address[] addresses of the collaterals
     */
    function getAccountCollateralAssets(address account) external view returns (address[] memory);

    /**
     * @notice Get `account` collateral deposit amount for `asset`
     * @param asset The asset address
     * @param account The account to query amount for
     * @return uint256 Amount of collateral deposited for `asset`
     */
    function getAccountCollateralAmount(address account, address asset) external view returns (uint256);
    function getAccountCollateralValue(address, address) external view returns (uint256);

    /**
     * @notice Calculates the expected fee to be taken from a user's deposited collateral assets,
     *         by imitating calcFee without modifying state.
     * @param account account paying the fees
     * @param kopio kopio being burned.
     * @param amount Amount of the asset being minted.
     * @param feeType Type of the fees (open or close).
     * @return assets array with the collaterals used
     * @return amounts array with the fee amounts paid
     */
    function previewFee(
        address account,
        address kopio,
        uint256 amount,
        Enums.ICDPFee feeType
    ) external view returns (address[] memory assets, uint256[] memory amounts);
}
