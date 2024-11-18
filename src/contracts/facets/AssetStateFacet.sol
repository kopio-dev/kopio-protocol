// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import {Strings} from "vendor/Strings.sol";
import {AssetOracles, OraclePrice} from "common/Types.sol";
import {IAssetStateFacet} from "interfaces/IAssetStateFacet.sol";
import {Enums} from "common/Constants.sol";
import {err} from "common/Errors.sol";
import {Asset, Oracle} from "common/Types.sol";
import {cs} from "common/State.sol";
import {pushPrice, Price} from "periphery/Helpers.sol";

contract AssetStateFacet is IAssetStateFacet {
    using Strings for bytes32;

    modifier onlyExistingAsset(address addr) {
        if (!cs().assets[addr].exists()) revert err.INVALID_ASSET(addr);
        _;
    }

    /// @inheritdoc IAssetStateFacet
    function getAsset(address addr) external view returns (Asset memory) {
        return cs().assets[addr];
    }

    /// @inheritdoc IAssetStateFacet
    function getValue(address addr, uint256 amount) external view returns (uint256) {
        return cs().assets[addr].assetUSD(amount);
    }
    function getDepositValue(address addr, uint256 amount) external view returns (uint256) {
        return cs().assets[addr].toCollateralValue(amount, false);
    }

    function getDebtValue(address addr, uint256 amount) external view returns (uint256) {
        return cs().assets[addr].toDebtValue(amount, false);
    }

    /// @inheritdoc IAssetStateFacet
    function getFeedForAddress(address addr, Enums.OracleType oracle) external view returns (address) {
        return cs().oracles[cs().assets[addr].ticker][oracle].feed;
    }

    /// @inheritdoc IAssetStateFacet
    function getPrice(address addr) external view onlyExistingAsset(addr) returns (uint256) {
        return cs().assets[addr].price();
    }

    /// @inheritdoc IAssetStateFacet
    function getPriceUnsafe(address addr) external view onlyExistingAsset(addr) returns (OraclePrice memory) {
        (Enums.OracleType oracle, Oracle memory config) = cs().assets[addr].oracleAt(0);
        return Price.getUnsafe(oracle, config);
    }

    /// @inheritdoc IAssetStateFacet
    function getPushPrice(address addr) external view onlyExistingAsset(addr) returns (OraclePrice memory) {
        Asset storage asset = cs().assets[addr];
        return pushPrice(asset.oracles, asset.ticker);
    }

    /// @inheritdoc IAssetStateFacet
    function getMarketStatus(address addr) external view returns (bool) {
        return cs().assets[addr].isMarketOpen();
    }

    /// @inheritdoc IAssetStateFacet
    function getAssetOracles(address addr) external view returns (AssetOracles memory r) {
        (r.ids[0], r.cfgs[0]) = getAssetOracleAt(addr, 0);
        (r.ids[1], r.cfgs[1]) = getAssetOracleAt(addr, 1);
    }

    /// @inheritdoc IAssetStateFacet
    function getAssetOracleAt(address addr, uint8 idx) public view returns (Enums.OracleType, Oracle memory) {
        return cs().assets[addr].oracleAt(idx);
    }
}
