// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {Asset, AssetOracles, Oracle} from "common/Types.sol";
import {Enums} from "common/Constants.sol";
import {OraclePrice} from "common/Types.sol";

interface IAssetStateFacet {
    /**
     * @notice Get the state of a specific asset
     * @param addr Address of the asset.
     * @return Asset State of asset
     */
    function getAsset(address addr) external view returns (Asset memory);

    /**
     * @notice Get price for an asset
     * @param addr Asset address.
     * @return uint256 Current price for the asset.
     */
    function getPrice(address addr) external view returns (uint256);
    /**
     * @notice Get price without stale checks
     * @param addr Asset address.
     * @return uint256 Current price for the asset.
     */
    function getPriceUnsafe(address addr) external view returns (OraclePrice memory);

    /**
     * @notice Get push price for an asset from address.
     * @param addr Asset address.
     * @return OraclePrice Current raw price for the asset.
     */
    function getPushPrice(address addr) external view returns (OraclePrice memory);

    /**
     * @notice Get value for an asset amount using the current price.
     * @param addr Asset address.
     * @param amount The amount.
     * @return Current value for `amount` of `addr`.
     */
    function getValue(address addr, uint256 amount) external view returns (uint256);
    function getDepositValue(address, uint256) external view returns (uint256);
    function getDebtValue(address, uint256) external view returns (uint256);

    /**
     * @notice Gets corresponding feed address for the oracle type and asset address.
     * @param addr The asset address.
     * @param oracle The oracle type.
     * @return Feed address that the asset uses with the oracle type.
     */
    function getFeedForAddress(address addr, Enums.OracleType oracle) external view returns (address);

    /**
     * @notice Get the market status for an asset.
     * @param addr Asset address.
     * @return bool True if the market is open, false otherwise.
     */
    function getMarketStatus(address addr) external view returns (bool);

    /**
     * @notice Get the oracles for an asset.
     * @return AssetOracles Oracles for the asset.
     */
    function getAssetOracles(address) external view returns (AssetOracles memory);
    function getAssetOracleAt(address, uint8) external view returns (Enums.OracleType, Oracle memory);
}
