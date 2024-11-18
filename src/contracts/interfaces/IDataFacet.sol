// solhint-disable no-empty-blocks
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
import {PythView} from "kopio/vendor/Pyth.sol";
import {TData} from "periphery/data/DataTypes.sol";
import {Asset} from "common/Types.sol";

interface IDataAccountFacet is TData {
    function aDataAccount(PythView calldata prices, address account) external view returns (Account memory);

    function iDataAccounts(PythView calldata prices, address[] memory accounts) external view returns (IAccount[] memory);

    function sDataAccount(PythView calldata prices, address account) external view returns (SAccount memory);

    function sDataAccounts(
        PythView calldata prices,
        address[] memory accounts,
        address[] memory assets
    ) external view returns (SAccount[] memory);
}

interface IDataCommonFacet is TData {
    function aDataProtocol(PythView calldata prices) external view returns (Protocol memory);
    function aDataAssetConfigs(uint8) external view returns (address[] memory, Asset[] memory);

    function sDataAssets(PythView calldata prices, address[] memory assets) external view returns (TPosAll[] memory);
    /**
     * @notice Addresses of assets, according to specified number:
     *
     * Default: All
     *
     * 1: ICDP Collaterals
     * 2: ICDP Kopios (debt)
     * 3: SCDP Depositable
     * 4: SCDP Collaterals
     * 5: SCDP Kopios (debt)
     * @return address[] List of asset addresses
     */
    function aDataAssetAddrs(uint8) external view returns (address[] memory);
}

interface IDataFacets is IDataCommonFacet, IDataAccountFacet {}
