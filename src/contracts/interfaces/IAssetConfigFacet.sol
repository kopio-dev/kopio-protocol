// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {Asset, TickerOracles} from "common/Types.sol";
import {Enums} from "common/Constants.sol";

interface IAssetConfigFacet {
    /**
     * @notice Adds a new asset to the common state.
     * @notice Performs validations according to the `cfg` provided.
     * @dev Use validateAssetConfig / static call this for validation.
     * @param addr Asset address.
     * @param cfg Configuration struct to save for the asset.
     * @param feeds Configuration struct for the asset's oracles
     * @return Asset Result of addAsset.
     */
    function addAsset(address addr, Asset memory cfg, TickerOracles memory feeds) external returns (Asset memory);

    /**
     * @notice Update asset config.
     * @notice Performs validations according to the `cfg` set.
     * @dev Use validateAssetConfig / static call this for validation.
     * @param addr The asset address.
     * @param cfg Configuration struct to apply for the asset.
     */
    function updateAsset(address addr, Asset memory cfg) external returns (Asset memory);

    /**
     * @notice Updates the cFactor of an asset.
     * @param asset The collateral asset.
     * @param newFactor The new collateral factor.
     */
    function setCFactor(address asset, uint16 newFactor) external;

    /**
     * @notice Updates the dFactor of a kopio.
     * @param asset The kopio.
     * @param newDFactor The new dFactor.
     */
    function setDFactor(address asset, uint16 newDFactor) external;

    /**
     * @notice Validate supplied asset config. Reverts with information if invalid.
     * @param addr The asset address.
     * @param cfg Configuration for the asset.
     * @return bool True for convenience.
     */
    function validateAssetConfig(address addr, Asset memory cfg) external view returns (bool);

    /**
     * @notice Update oracle order for an asset.
     * @param addr The asset address.
     * @param types 2 OracleTypes. 0 = primary, 1 = reference.
     */
    function setOracleTypes(address addr, Enums.OracleType[2] memory types) external;
}
