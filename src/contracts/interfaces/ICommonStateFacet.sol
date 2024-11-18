// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {Enums} from "common/Constants.sol";
import {Oracle, OraclePrice} from "common/Types.sol";

interface ICommonStateFacet {
    /// @notice The recipient of protocol fees.
    function getFeeRecipient() external view returns (address);

    /// @notice The pyth endpoint.
    function getPythEndpoint() external view returns (address);

    /// @notice Offchain oracle decimals
    function getOracleDecimals() external view returns (uint8);

    /// @notice max deviation between main oracle and fallback oracle
    function getOracleDeviationPct() external view returns (uint16);

    /// @notice Get the market status provider address.
    function getMarketStatusProvider() external view returns (address);

    /// @notice Get the KCLV3 address.
    function getKCLV3() external view returns (address);

    /// @notice Get the L2 sequencer uptime feed address.
    function getSequencerUptimeFeed() external view returns (address);

    /// @notice Get the L2 sequencer uptime feed grace period
    function getSequencerGracePeriod() external view returns (uint32);

    /**
     * @notice Get configured feed of the ticker
     * @param ticker Ticker in bytes32, eg. bytes32("ETH").
     * @param oracle The oracle type.
     * @return Oracle Configuration of the feed.
     */
    function getOracleOfTicker(bytes32 ticker, Enums.OracleType oracle) external view returns (Oracle memory);

    function getChainlinkPrice(bytes32) external view returns (uint256);

    function getChainlinkDerivedPrice(bytes32) external view returns (uint256);

    function getVaultPrice(bytes32) external view returns (uint256);

    function getAPI3Price(bytes32) external view returns (uint256);

    function getPythPrice(bytes32) external view returns (uint256);

    function getOraclePrice(bytes32, Enums.OracleType) external view returns (OraclePrice memory);
}
