// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Utils, Log} from "kopio/vm/VmLibs.s.sol";
import "scripts/deploy/JSON.s.sol" as JSON;
import {LibDeploy} from "scripts/deploy/libs/LibDeploy.s.sol";
import {LibJSON} from "scripts/deploy/libs/LibJSON.s.sol";
import {TickerOracles, Asset, Oracle} from "common/Types.sol";
import {IAggregatorV3} from "kopio/vendor/IAggregatorV3.sol";
import {KopioCore} from "interfaces/KopioCore.sol";
import {addr} from "kopio/info/ArbDeployAddr.sol";
import {IPyth} from "kopio/vendor/Pyth.sol";

// solhint-disable no-empty-blocks, reason-string, state-visibility

contract AssetAdder {
    using Log for *;
    using Utils for *;
    using LibDeploy for *;
    using LibJSON for *;

    TickerOracles NO_NEW_FEEDS;
    uint256 currentForkId;
    KopioCore kopioCore = KopioCore(addr.protocol);

    function deployAsset(string memory _symbol) public returns (address payable) {
        JSON.Config memory json = JSON.getConfig("arbitrum", "arbitrum");
        (, LibDeploy.DeployResult memory deployInfo) = createKopio(json, _symbol);
        return payable(deployInfo.addr);
    }

    function createKopio(JSON.Config memory json, string memory symbol) public jsonOut(symbol) returns (Asset memory config, LibDeploy.DeployResult memory deployInfo) {
        JSON.KopioParams memory params = JSON.getKopio(json, symbol);
        deployInfo = json.deployKopio(params.json, addr.protocol);
        config = params.json.config.toAsset(symbol);
        TickerOracles memory feedConfig = getTickerOracles(json, params.json.config, params.ticker);
        validateOracles(config.ticker, feedConfig);
        config = kopioCore.addAsset(deployInfo.addr, config, feedConfig);
    }

    function addExtAsset(JSON.Config memory json, string memory symbol) public returns (Asset memory config) {
        JSON.ExtAssetParams memory params = JSON.getExtAsset(json, symbol);
        config = params.json.config.toAsset(symbol);

        address assetAddr = params.json.addr;
        TickerOracles memory feedConfig = getTickerOracles(json, params.json.config, params.ticker);
        validateOracles(config.ticker, feedConfig);

        config = kopioCore.addAsset(assetAddr, config, feedConfig);
    }

    function getTickerOracles(JSON.Config memory json, JSON.AssetJSON memory asset, JSON.TickerConfig memory ticker) public view returns (TickerOracles memory result) {
        bytes32 bytesTicker = bytes32(bytes(asset.ticker));
        Oracle memory primary = kopioCore.getOracleOfTicker(bytesTicker, asset.oracles[0]);
        Oracle memory secondary = kopioCore.getOracleOfTicker(bytesTicker, asset.oracles[1]);
        if (primary.pythId != bytes32(0) && secondary.feed != address(0)) {
            // no new config needs to be set, everything exists
            return result;
        }

        return json.getTickerOracles(ticker.ticker, asset.oracles);
    }

    function validateExtAsset(address assetAddr, Asset memory config) internal view {
        require(config.share == address(0), "Share address is not zero");
        require(config.dFactor == 0, "dFactor is not zero");
        require(!config.isKopio, "cannot be kopio");
        require(!config.isSwapMintable, "cannot be swap mintable");
        require(kopioCore.validateAssetConfig(assetAddr, config), "Invalid extAsset config");
    }

    function validateNewKopio(string memory symbol, LibDeploy.DeployResult memory deployInfo, Asset memory config) internal view {
        require(deployInfo.symbol.equals(symbol), "Symbol mismatch");
        require(deployInfo.addr != address(0), "Deployed address is zero");
        require(deployInfo.shareAddr != address(0), "Share address is zero");
        require(config.share == deployInfo.shareAddr, "Share address mismatch");
        require(kopioCore.validateAssetConfig(deployInfo.addr, config), "Invalid kopio config");
    }

    function validateOracles(bytes32 ticker, TickerOracles memory feedCfg) internal view returns (uint256 primaryPrice, uint256 secondaryPrice) {
        if (feedCfg.pythId == bytes32(0)) {
            require(feedCfg.feeds[0] == address(0), "Primary feed is not zero");
            require(feedCfg.feeds[1] == address(0), "Secondary feed is not zero");

            primaryPrice = kopioCore.getPythPrice(ticker);
            secondaryPrice = kopioCore.getChainlinkPrice(ticker);
        } else {
            require(feedCfg.feeds[0] == address(0), "Primary feed is not zero");
            primaryPrice = uint256(uint64(IPyth(kopioCore.getPythEndpoint()).getPriceUnsafe(feedCfg.pythId).price));
            secondaryPrice = uint256(IAggregatorV3(feedCfg.feeds[1]).latestAnswer());
        }

        require(primaryPrice != 0, "Primary price is zero");
        require(secondaryPrice != 0, "Secondary price is zero");
    }

    modifier jsonOut(string memory id) {
        LibDeploy.initOutputJSON(id);
        _;
        LibDeploy.writeOutputJSON();
    }
}
