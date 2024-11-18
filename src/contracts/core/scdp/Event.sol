// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface SEvent {
    event SCDPDeposit(
        address indexed depositor,
        address indexed collateral,
        uint256 amount,
        uint256 feeIndex,
        uint256 timestamp
    );
    event SCDPWithdraw(
        address indexed account,
        address indexed receiver,
        address indexed collateral,
        address withdrawer,
        uint256 amount,
        uint256 feeIndex,
        uint256 timestamp
    );
    event SCDPFeeReceipt(
        address indexed account,
        address indexed collateral,
        uint256 accDeposits,
        uint256 assetFeeIndex,
        uint256 accFeeIndex,
        uint256 assetLiqIndex,
        uint256 accLiqIndex,
        uint256 blockNumber,
        uint256 timestamp
    );
    event SCDPFeeClaim(
        address indexed claimer,
        address indexed receiver,
        address indexed collateral,
        uint256 feeAmount,
        uint256 newIndex,
        uint256 prevIndex,
        uint256 timestamp
    );
    event SCDPRepay(
        address indexed repayer,
        address indexed repayKopio,
        uint256 repayAmount,
        address indexed receiveKopio,
        uint256 receiveAmount,
        uint256 timestamp
    );

    event SCDPLiquidationOccured(
        address indexed liquidator,
        address indexed repayKopio,
        uint256 repayAmount,
        address indexed seizeCollateral,
        uint256 seizeAmount,
        uint256 prevLiqIndex,
        uint256 newLiqIndex,
        uint256 timestamp
    );
    event SCDPCoverOccured(
        address indexed coverer,
        address indexed asset,
        uint256 amount,
        address indexed seizeCollateral,
        uint256 seizeAmount,
        uint256 prevLiqIndex,
        uint256 newLiqIndex,
        uint256 timestamp
    );

    // Emitted when a swap pair is disabled / enabled.
    event PairSet(address indexed assetIn, address indexed assetOut, bool enabled);
    // Emitted when a asset fee is updated.
    event FeeSet(address indexed asset, uint256 openFee, uint256 closeFee, uint256 protocolFee);

    // Emitted on global configuration updates.
    event CollateralGlobalUpdate(address indexed collateral, uint256 newThreshold);

    // Emitted on global configuration updates.
    event KopioGlobalUpdate(address indexed kopio, uint256 feeIn, uint256 feeOut, uint256 protocolFee, uint256 debtLimit);

    event Swap(
        address indexed who,
        address indexed assetIn,
        address indexed assetOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 timestamp
    );

    event SwapFee(
        address indexed feeAsset,
        address indexed assetIn,
        uint256 feeAmount,
        uint256 protocolFeeAmount,
        uint256 timestamp
    );

    event Income(address asset, uint256 amount);

    /**
     * @notice Emitted when liquidation incentive multiplier is updated for a kopio.
     * @param symbol token symbol
     * @param asset address of the kopio
     * @param from previous multiplier
     * @param to the new multiplier
     */
    event GlobalLiqIncentiveUpdated(string indexed symbol, address indexed asset, uint256 from, uint256 to);

    /**
     * @notice Emitted when the MCR of SCDP is updated.
     * @param from previous ratio
     * @param to new ratio
     */
    event GlobalMCRUpdated(uint256 from, uint256 to);

    /**
     * @notice Emitted when the liquidation threshold is updated
     * @param from previous threshold
     * @param to new threshold
     * @param mlr new max liquidation ratio
     */
    event GlobalLTUpdated(uint256 from, uint256 to, uint256 mlr);

    /**
     * @notice Emitted when the max liquidation ratio is updated
     * @param from previous ratio
     * @param to new ratio
     */
    event GlobalMLRUpdated(uint256 from, uint256 to);
}
