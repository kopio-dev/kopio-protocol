// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {CommonInitializer, PythConfig, TickerOracles} from "common/Types.sol";

interface ICommonConfigFacet {
    function initializeCommon(CommonInitializer calldata args) external;

    /**
     * @notice Sets the fee recipient.
     * @param recipient The new fee recipient.
     */
    function setFeeRecipient(address recipient) external;

    /**
     * @notice Sets the pyth endpoint address
     * @param ep Pyth endpoint address
     * @param relayer New relayer address, if 0 then `ep` is used.
     */
    function setPythEPs(address ep, address relayer) external;

    /**
     * @notice Sets the kopioCLV3 address
     * @param addr kopioCLV3 address
     */
    function setKCLV3(address addr) external;

    /**
     * @notice Sets the decimal precision of external oracle
     * @param dec Amount of decimals
     */
    function setOracleDecimals(uint8 dec) external;

    /**
     * @notice Sets the decimal precision of external oracle
     * @param newDeviation Amount of decimals
     */
    function setOracleDeviation(uint16 newDeviation) external;

    /**
     * @notice Sets L2 sequencer uptime feed address
     * @param newFeed sequencer uptime feed address
     */
    function setSequencerUptimeFeed(address newFeed) external;

    /**
     * @notice Sets sequencer grace period time
     * @param newGracePeriod grace period time
     */
    function setSequencerGracePeriod(uint32 newGracePeriod) external;

    /**
     * @notice Sets oracle configuration for a ticker.
     * @param ticker bytes32, eg. "ETH"
     * @param cfg Ticker configuration for primary and secondary oracles.
     */
    function setFeedsForTicker(bytes32 ticker, TickerOracles memory cfg) external;

    function setPythFeeds(bytes32[] calldata tickers, PythConfig[] calldata pythCfg) external;

    function setVaultFeed(bytes32 ticker, address vault) external;

    function setPythFeed(bytes32 ticker, PythConfig calldata) external;

    function setChainLinkFeed(bytes32 ticker, address feed, uint256 st, bool closable) external;

    function setChainLinkDerivedFeed(bytes32 ticker, address feed, uint256 st, bool closable) external;

    function setAPI3Feed(bytes32 ticker, address feed, uint256 st, bool closable) external;

    function setMarketStatusProvider(address newProvider) external;
}
