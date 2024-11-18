// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {PythView} from "kopio/vendor/Pyth.sol";
import {IDataCommonFacet} from "interfaces/IDataFacet.sol";
import {DataLogic} from "periphery/data/DataLogic.sol";
import {ms} from "icdp/State.sol";
import {scdp} from "scdp/State.sol";
import {Asset, cs} from "common/State.sol";

contract DataCommonFacet is IDataCommonFacet {
    function aDataAssetAddrs(uint8 list) public view returns (address[] memory) {
        if (list == 1) return ms().collaterals;
        if (list == 2) return ms().kopios;
        if (list == 3) return DataLogic.getSDepositAssets();
        if (list == 4) return scdp().collaterals;
        if (list == 5) return scdp().kopios;
        return DataLogic.getAllAssets();
    }

    function aDataAssetConfigs(uint8 list) external view returns (address[] memory addrs, Asset[] memory cfgs) {
        addrs = aDataAssetAddrs(list);
        cfgs = new Asset[](addrs.length);

        for (uint256 i; i < addrs.length; ) {
            cfgs[i] = cs().assets[addrs[i]];
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IDataCommonFacet
    function aDataProtocol(PythView calldata prices) external view returns (Protocol memory) {
        return DataLogic.getProtocol(prices);
    }

    /// @inheritdoc IDataCommonFacet
    function sDataAssets(PythView calldata prices, address[] memory assets) external view returns (TPosAll[] memory results) {
        // address[] memory collateralAssets = scdp().collaterals;
        results = new TPosAll[](assets.length);

        for (uint256 i; i < assets.length; ) {
            results[i] = DataLogic.getSAssetData(prices, assets[i]);
            unchecked {
                i++;
            }
        }
    }
}
