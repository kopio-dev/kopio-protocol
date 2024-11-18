// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Enums} from "common/Constants.sol";

interface MEvent {
    /**
     * @notice Emitted when a collateral is added.
     * @dev only emitted once per asset.
     * @param ticker underlying ticker.
     * @param symbol token symbol
     * @param collateral address of the asset
     * @param factor the collateral factor
     * @param share possible fixed share address
     * @param liqIncentive the liquidation incentive
     */
    event CollateralAdded(
        string indexed ticker,
        string indexed symbol,
        address indexed collateral,
        uint256 factor,
        address share,
        uint256 liqIncentive
    );

    /**
     * @notice Emitted when collateral is updated.
     * @param ticker underlying ticker.
     * @param symbol token symbol
     * @param collateral address of the collateral.
     * @param factor the collateral factor.
     * @param share possible fixed share address
     * @param liqIncentive the liquidation incentive
     */
    event CollateralUpdated(
        string indexed ticker,
        string indexed symbol,
        address indexed collateral,
        uint256 factor,
        address share,
        uint256 liqIncentive
    );

    /**
     * @notice Emitted when an account deposits collateral.
     * @param account The address of the account depositing collateral.
     * @param collateral The address of the collateral asset.
     * @param amount The amount of the collateral asset that was deposited.
     */
    event CollateralDeposited(address indexed account, address indexed collateral, uint256 amount);

    /**
     * @notice Emitted on collateral withdraws.
     * @param account account withdrawing collateral.
     * @param collateral the withdrawn collateral.
     * @param amount the amount withdrawn.
     */
    event CollateralWithdrawn(address indexed account, address indexed collateral, uint256 amount);
    event CollateralFlashWithdrawn(address indexed account, address indexed collateral, uint256 amount);

    /* -------------------------------------------------------------------------- */
    /*                                   Kopios                                   */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when a new kopio is added.
     * @dev emitted once per asset.
     * @param ticker underlying ticker.
     * @param symbol token symbol
     * @param kopio address of the asset.
     * @param share fixed share address
     * @param dFactor debt factor.
     * @param icdpLimit icdp supply cap.
     * @param closeFee close fee percentage.
     * @param openFee open fee percentage.
     */
    event KopioAdded(
        string indexed ticker,
        string indexed symbol,
        address indexed kopio,
        address share,
        uint256 dFactor,
        uint256 icdpLimit,
        uint256 closeFee,
        uint256 openFee
    );

    /**
     * @notice Emitted when a kopio is updated.
     * @param ticker underlying ticker.
     * @param symbol token symbol
     * @param kopio address of the asset.
     * @param share fixed share address
     * @param dFactor debt factor.
     * @param icdpLimit icdp supply cap.
     * @param closeFee The close fee percentage.
     * @param openFee The open fee percentage.
     */
    event KopioUpdated(
        string indexed ticker,
        string indexed symbol,
        address indexed kopio,
        address share,
        uint256 dFactor,
        uint256 icdpLimit,
        uint256 closeFee,
        uint256 openFee
    );

    /**
     * @notice Emitted when a kopio is minted.
     * @param account account minting the kopio.
     * @param kopio address of the kopio
     * @param amount amount minted.
     * @param receiver receiver of the minted kopio.
     */
    event KopioMinted(address indexed account, address indexed kopio, uint256 amount, address receiver);

    /**
     * @notice Emitted when asset is burned.
     * @param account account burning the assets
     * @param kopio address of the kopio
     * @param amount amount burned
     */
    event KopioBurned(address indexed account, address indexed kopio, uint256 amount);

    /**
     * @notice Emitted when collateral factor is updated.
     * @param symbol token symbol
     * @param collateral address of the collateral.
     * @param from previous factor.
     * @param to new factor.
     */
    event CFactorUpdated(string indexed symbol, address indexed collateral, uint256 from, uint256 to);
    /**
     * @notice Emitted when dFactor is updated.
     * @param symbol token symbol
     * @param kopio address of the asset.
     * @param from previous debt factor
     * @param to new debt factor
     */
    event DFactorUpdated(string indexed symbol, address indexed kopio, uint256 from, uint256 to);

    /**
     * @notice Emitted when account closes a full debt position.
     * @param account address of the account
     * @param kopio asset address
     * @param amount amount burned to close the position.
     */
    event DebtPositionClosed(address indexed account, address indexed kopio, uint256 amount);

    /**
     * @notice Emitted when an account pays the open/close fee.
     * @dev can be emitted multiple times for a single asset.
     * @param account address that paid the fee.
     * @param collateral collateral used to pay the fee.
     * @param feeType type of the fee.
     * @param amount amount paid
     * @param value value paid
     * @param valueRemaining remaining fee value after.
     */
    event FeePaid(
        address indexed account,
        address indexed collateral,
        uint256 indexed feeType,
        uint256 amount,
        uint256 value,
        uint256 valueRemaining
    );

    /**
     * @notice Emitted when a liquidation occurs.
     * @param account account liquidated.
     * @param liquidator account that liquidated it.
     * @param kopio asset repaid.
     * @param amount amount repaid.
     * @param seizedCollateral collateral the liquidator seized.
     * @param seizedAmount amount of collateral seized
     */
    event LiquidationOccurred(
        address indexed account,
        address indexed liquidator,
        address indexed kopio,
        uint256 amount,
        address seizedCollateral,
        uint256 seizedAmount
    );

    /* -------------------------------------------------------------------------- */
    /*                                Parameters                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Emitted when a safety state is triggered for an asset
     * @param action target action
     * @param symbol token symbol
     * @param asset address of the target asset
     * @param description description for this event
     */
    event SafetyStateChange(Enums.Action indexed action, string indexed symbol, address indexed asset, string description);

    /**
     * @notice Emitted when the fee recipient is updated.
     * @param from previous recipient
     * @param to new recipient
     */
    event FeeRecipientUpdated(address from, address to);

    /**
     * @notice Emitted the asset's liquidation incentive is updated.
     * @param symbol token symbol
     * @param collateral asset address
     * @param from previous incentive
     * @param to new incentive
     */
    event LiquidationIncentiveUpdated(string indexed symbol, address indexed collateral, uint256 from, uint256 to);

    /**
     * @notice Emitted when the MCR is updated.
     * @param from previous MCR.
     * @param to new MCR.
     */
    event MinCollateralRatioUpdated(uint256 from, uint256 to);

    /**
     * @notice Emitted when the minimum debt value is updated.
     * @param from previous value
     * @param to new value
     */
    event MinimumDebtValueUpdated(uint256 from, uint256 to);

    /**
     * @notice Emitted when the liquidation threshold is updated
     * @param from previous threshold
     * @param to new threshold
     * @param mlr new max liquidation ratio.
     */
    event LiquidationThresholdUpdated(uint256 from, uint256 to, uint256 mlr);
    /**
     * @notice Emitted when the max liquidation ratio is updated
     * @param from previous ratio
     * @param to new ratio
     */
    event MaxLiquidationRatioUpdated(uint256 from, uint256 to);
}
