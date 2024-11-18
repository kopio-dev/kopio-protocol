// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {PythView} from "kopio/vendor/Pyth.sol";
import {IDataAccountFacet} from "interfaces/IDataFacet.sol";
import {DataLogic} from "periphery/data/DataLogic.sol";

contract DataAccountFacet is IDataAccountFacet {
    /// @inheritdoc IDataAccountFacet
    function aDataAccount(PythView calldata prices, address acc) external view returns (Account memory) {
        return DataLogic.getAccount(prices, acc);
    }

    /// @inheritdoc IDataAccountFacet
    function iDataAccounts(PythView calldata prices, address[] memory accs) external view returns (IAccount[] memory result) {
        result = new IAccount[](accs.length);

        for (uint256 i; i < accs.length; ) {
            result[i] = DataLogic.getIAccount(prices, accs[i]);
            unchecked {
                i++;
            }
        }
    }

    /// @inheritdoc IDataAccountFacet
    function sDataAccount(PythView calldata prices, address acc) external view returns (SAccount memory) {
        return DataLogic.getSAccount(prices, acc, DataLogic.getSDepositAssets());
    }

    /// @inheritdoc IDataAccountFacet
    function sDataAccounts(
        PythView calldata prices,
        address[] memory accs,
        address[] memory assets
    ) external view returns (SAccount[] memory result) {
        result = new SAccount[](accs.length);

        for (uint256 i; i < accs.length; ) {
            result[i] = DataLogic.getSAccount(prices, accs[i], assets);

            unchecked {
                i++;
            }
        }
    }
}
