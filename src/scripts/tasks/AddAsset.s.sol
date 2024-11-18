// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "scripts/utils/Task.s.sol";
import {AssetPayload} from "scripts/utils/payloads/AssetPayload.sol";

contract AddAsset is Task {
    using Log for *;
    using Utils for *;
    using VmHelp for *;

    address payable internal newAssetAddr;

    string assetName = "BNB";
    string assetTicker = "BNB";
    string assetSymbol = string.concat("k", assetTicker);
    bytes32 marketStatusSource = bytes32("CRYPTO");

    function setUp() public virtual {
        useDefaultConfig("AddAsset");
        fetchPyth();
    }

    address[] exts = [addr.usdt];

    function checkAssets() public view {
        (address[] memory addrs, Asset[] memory cfgs) = kopioCore.aDataAssetConfigs(0);
        IData.Oracles[] memory oracles = new DataV3.Oracles[](addrs.length);
        for (uint256 i; i < addrs.length; i++) {
            (address taddr, Asset memory cfg) = (addrs[i], cfgs[i]);
            Oracle memory pyth = kopioCore.getOracleOfTicker(cfg.ticker, Enums.OracleType.Pyth);
            oracles[i] = IData.Oracles({addr: taddr, clFeed: kopioCore.getFeedForAddress(taddr, cfg.oracles[1]), pythId: pyth.pythId, invertPyth: pyth.invertPyth, ext: false});

            string memory info = string.concat(
                "\n************************************************************",
                "\n* Asset: ",
                IERC20(addrs[i]).symbol(),
                "\n************************************************************",
                "\n* (address)      -> ",
                taddr.txt(),
                "\n* (ticker)       -> ",
                cfg.ticker.str(),
                "\n* (decimals)     -> ",
                cfg.decimals.str(),
                "\n* (share)        -> ",
                cfg.share.txt(),
                "\n* (clFeed)       -> ",
                oracles[i].clFeed.txt(),
                "\n* (name)         -> ",
                IERC20(addrs[i]).name(),
                "\n* (pythId)       -> ",
                oracles[i].pythId.txt(),
                "\n* (getPrice)     -> ",
                kopioCore.getPriceUnsafe(taddr).answer.dstr(8),
                "\n* (getPushPrice) -> ",
                kopioCore.getPushPrice(taddr).answer.dstr(8),
                "\n************************************************************"
            );

            Log.clg(info);
        }

        IData.TAsset[] memory assets = iData.getGlobals(pyth.viewData, exts).assets;

        for (uint256 i; i < assets.length; i++) {
            IData.TAsset memory asset = assets[i];
            string memory info = string.concat(
                "\n************************************************************",
                "\n* (symbol)       -> ",
                asset.symbol,
                "\n* (name)         -> ",
                asset.name,
                "\n* (price)        -> ",
                asset.price.dstr(8),
                "\n************************************************************"
            );

            Log.clg(info);
        }
    }

    function createAssets() public broadcasted(sender) {
        createAddAsset();
        DataV3(addr.data).setOracles(new IData.Oracles[](0));
    }

    function createAddAsset() public {
        newAssetAddr = _createAddAsset();

        IERC20 token = IERC20(newAssetAddr);

        broadcastWith(addr.safe);
        updatePyth();
        syncTime();

        string memory info = string.concat(
            "\n************************************************************",
            "\n* Created ",
            token.symbol(),
            " succesfully.",
            "\n************************************************************",
            "\n* (address)      -> ",
            vm.toString(newAssetAddr),
            "\n* (name)         -> ",
            token.name(),
            "\n* (getPrice)     -> ",
            kopioCore.getPriceUnsafe(newAssetAddr).answer.dstr(8),
            "\n* (getPushPrice) -> ",
            (uint256(kopioCore.getPushPrice(newAssetAddr).answer)).dstr(8),
            "\n************************************************************"
        );
        Log.clg(info);
        Log.br();
    }

    function _createAddAsset() internal returns (address payable addr_) {
        address payloadAddr = deployPayload(type(AssetPayload).creationCode, abi.encode(addr_ = deployAsset(assetSymbol)), string.concat(assetSymbol, "-initializer"));
        IExtendedDiamondCutFacet(address(kopioCore)).executeInitializer(payloadAddr, abi.encodeCall(AssetPayload.executePayload, ()));
    }
}
