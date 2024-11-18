// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// solhint-disable no-unused-import
import {Deployed} from "../deploy/libs/Deployed.s.sol";
import {IData} from "periphery/IData.sol";
import {DataV3} from "periphery/DataV3.sol";

import "kopio/vm/Connected.s.sol";
import "kopio/vm/Deployer.s.sol";
import "scripts/utils/AssetAdder.s.sol";
import "scripts/utils/payloads/Payloads.sol";
import "common/Constants.sol";
import "common/Types.sol";

library Configs {
    struct Config {
        string rpc;
        string mnemonic;
        string pythTickers;
        string outDir;
    }

    string constant RPC_FORK = "RPC_FORK_KOPIO";
    string constant RPC_PROD = "RPC_ARBITRUM_ALCHEMY";
    string constant PYTH_TICKERS = "BTC,ETH,USDC,ARB,SOL,GBP,EUR,JPY,XAU,XAG,DOGE,BNB";
    string constant DEFAULT_MNEMONIC = "MNEMONIC_KOPIO";

    function Default(string memory id) internal pure returns (Config memory) {
        return Config(RPC_PROD, DEFAULT_MNEMONIC, PYTH_TICKERS, string.concat(id, "/"));
    }
    function Fork(string memory id) internal pure returns (Config memory) {
        return Config(RPC_FORK, DEFAULT_MNEMONIC, PYTH_TICKERS, string.concat(id, "/"));
    }
}

abstract contract Task is Connected, Deployer, AssetAdder {
    function useDefaultConfig(string memory id) internal {
        _setup(Configs.Default(id));
    }

    function useForkConfig(string memory id) internal {
        _setup(Configs.Fork(id));
    }

    function _setup(Configs.Config memory cfg) private {
        connect(cfg.mnemonic, cfg.rpc);
        setOutputDir(cfg.outDir);

        pyth.tickers = cfg.pythTickers;
        Deployed.factory(factoryAddr);
    }
}
