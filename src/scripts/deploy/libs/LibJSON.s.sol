// solhint-disable state-visibility
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {Utils} from "kopio/vm/VmLibs.s.sol";
import {Asset, TickerOracles} from "common/Types.sol";
import {Enums} from "common/Constants.sol";
import {VaultAsset} from "vault/Types.sol";
import {LibDeploy} from "scripts/deploy/libs/LibDeploy.s.sol";
import "scripts/deploy/JSON.s.sol" as JSON;
import {CONST} from "scripts/deploy/CONST.s.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {IAggregatorV3} from "kopio/vendor/IAggregatorV3.sol";
import {PythView, Price} from "kopio/vendor/Pyth.sol";

library LibJSON {
    using Utils for *;
    using LibDeploy for string;
    using LibJSON for *;
    using Deployed for *;

    struct Metadata {
        string name;
        string symbol;
        string ksName;
        string ksSymbol;
        bytes32 salt;
        bytes32 shareSalt;
    }

    function getVaultAssets(JSON.Config memory json) internal view returns (VaultAsset[] memory) {
        uint256 vaultAssetCount;
        for (uint256 i; i < json.assets.extAssets.length; i++) {
            if (json.assets.extAssets[i].isVaultAsset) vaultAssetCount++;
        }
        VaultAsset[] memory result = new VaultAsset[](vaultAssetCount);

        uint256 current;
        for (uint256 i; i < json.assets.extAssets.length; i++) {
            if (json.assets.extAssets[i].isVaultAsset) {
                result[current].token = IERC20(json.assets.extAssets[i].symbol.cached());
                result[current].feed = json.getFeed(json.assets.extAssets[i].vault.feed);
                result[current].withdrawFee = json.assets.extAssets[i].vault.withdrawFee;
                result[current].depositFee = json.assets.extAssets[i].vault.depositFee;
                result[current].maxDeposits = json.assets.extAssets[i].vault.maxDeposits;
                result[current].staleTime = json.assets.extAssets[i].vault.staleTime;
                result[current].enabled = json.assets.extAssets[i].vault.enabled;

                current++;
            }
        }

        return result;
    }

    function getTicker(JSON.Config memory json, string memory _ticker) internal pure returns (JSON.TickerConfig memory) {
        for (uint256 i; i < json.assets.tickers.length; i++) {
            if (json.assets.tickers[i].ticker.equals(_ticker)) {
                return json.assets.tickers[i];
            }
        }

        revert(string.concat("!feed: ", _ticker));
    }

    function getTickerOracles(JSON.Config memory json, string memory _ticker, Enums.OracleType[] memory oracles) internal pure returns (TickerOracles memory) {
        JSON.TickerConfig memory ticker = json.getTicker(_ticker);
        (uint256 staleTime1, address feed1) = ticker.getFeed(oracles[0]);
        (uint256 staleTime2, address feed2) = ticker.getFeed(oracles[1]);
        return
            TickerOracles({
                oracleIds: [oracles[0], oracles[1]],
                feeds: [feed1, feed2],
                pythId: ticker.pythId,
                staleTimes: [staleTime1, staleTime2],
                invertPyth: ticker.invertPyth,
                isClosable: ticker.isClosable
            });
    }

    function getFeed(JSON.Config memory json, string[] memory cfg) internal pure returns (IAggregatorV3) {
        (, address feed) = json.getTicker(cfg[0]).getFeed(cfg[1]);
        return IAggregatorV3(feed);
    }

    function getFeed(JSON.TickerConfig memory ticker, string memory oracle) internal pure returns (uint256, address) {
        if (oracle.equals("chainlink")) {
            return (ticker.staleTimeChainlink, ticker.chainlink);
        }

        if (oracle.equals("chainlink-derived")) {
            return (ticker.staleTimeChainlink, ticker.chainlink);
        }

        if (oracle.equals("api3")) {
            return (ticker.staleTimeAPI3, ticker.api3);
        }

        if (oracle.equals("vault")) {
            return (0, ticker.vault);
        }

        if (oracle.equals("pyth")) {
            return (ticker.staleTimePyth, address(0));
        }
        return (0, address(0));
    }

    function getFeed(JSON.TickerConfig memory ticker, Enums.OracleType oracle) internal pure returns (uint256 st, address t) {
        if (oracle == Enums.OracleType.Chainlink) return (ticker.staleTimeChainlink, ticker.chainlink);
        if (oracle == Enums.OracleType.ChainlinkDerived) return (ticker.staleTimeChainlink, ticker.chainlink);
        if (oracle == Enums.OracleType.API3) return (ticker.staleTimeAPI3, ticker.api3);
        if (oracle == Enums.OracleType.Vault) return (0, ticker.vault);
        if (oracle == Enums.OracleType.Pyth) return (ticker.staleTimePyth, address(0));
    }

    function toAsset(JSON.AssetJSON memory assetJson, string memory symbol) internal view returns (Asset memory result) {
        result.ticker = bytes32(bytes(assetJson.ticker));
        if (assetJson.dFactor != 0) {
            if (symbol.equals("ONE")) result.share = ("ONE").cached();
            else result.share = string.concat(CONST.SHARE_SYMBOL_PREFIX, symbol).cached();
        }

        Enums.OracleType[2] memory oracles = [assetJson.oracles[0], assetJson.oracles[1]];
        result.oracles = oracles;
        result.factor = assetJson.factor;
        result.dFactor = assetJson.dFactor;
        result.openFee = assetJson.openFee;
        result.closeFee = assetJson.closeFee;
        result.liqIncentive = assetJson.liqIncentive;
        result.mintLimit = assetJson.mintLimit;
        result.mintLimitSCDP = assetJson.mintLimitSCDP;
        result.depositLimitSCDP = assetJson.depositLimitSCDP;
        result.swapInFee = assetJson.swapInFee;
        result.swapOutFee = assetJson.swapOutFee;
        result.protocolFeeShareSCDP = assetJson.protocolFeeShareSCDP;
        result.liqIncentiveSCDP = assetJson.liqIncentiveSCDP;
        result.decimals = assetJson.decimals;
        result.isCollateral = assetJson.isCollateral;
        result.isKopio = assetJson.isKopio;
        result.isGlobalDepositable = assetJson.isGlobalDepositable;
        result.isSwapMintable = assetJson.isSwapMintable;
        result.isGlobalCollateral = assetJson.isGlobalCollateral;
        result.isCoverAsset = assetJson.isCoverAsset;
    }

    function feedBytesId(string memory ticker) internal pure returns (bytes32) {
        return bytes32(bytes(feedStringId(ticker)));
    }

    function feedStringId(string memory ticker) internal pure returns (string memory) {
        return string.concat(ticker, ".feed");
    }

    function metadata(JSON.KopioConfig memory cfg) internal pure returns (Metadata memory) {
        (string memory name, string memory symbol) = getKopioMeta(cfg.name, cfg.symbol);
        (string memory ksName, string memory ksSymbol) = getShareMeta(cfg.name, cfg.symbol);
        (bytes32 salt, bytes32 shareSalt) = getSalts(symbol, ksSymbol);

        return Metadata(name, symbol, ksName, ksSymbol, salt, shareSalt);
    }

    function getKopioMeta(string memory kname, string memory ksymbol) internal pure returns (string memory name, string memory symbol) {
        name = string.concat(CONST.KOPIO_NAME_PREFIX, kname);
        symbol = ksymbol;
    }

    function getShareMeta(string memory kName, string memory kSymbol) internal pure returns (string memory name, string memory symbol) {
        name = string.concat(CONST.SHARE_NAME_PREFIX, kName);
        symbol = string.concat(CONST.SHARE_SYMBOL_PREFIX, kSymbol);
    }

    function getSalts(string memory kSymbol, string memory ksSymbol) internal pure returns (bytes32 salt, bytes32 shareSalt) {
        salt = bytes32(bytes.concat(bytes(kSymbol), bytes(ksSymbol), CONST.SALT_ID));
        shareSalt = bytes32(bytes.concat(bytes(ksSymbol), bytes(kSymbol), CONST.SALT_ID));
    }

    function mockTokenSalt(string memory symbol) internal pure returns (bytes32) {
        return bytes32(bytes(symbol));
    }

    function pairId(address assetA, address assetB) internal pure returns (bytes32) {
        if (assetA < assetB) {
            return keccak256(abi.encodePacked(assetA, assetB));
        }
        return keccak256(abi.encodePacked(assetB, assetA));
    }

    function getBalanceConfig(JSON.Balance[] memory balances, string memory symbol) internal pure returns (JSON.Balance memory) {
        for (uint256 i; i < balances.length; i++) {
            if (balances[i].symbol.equals(symbol)) {
                return balances[i];
            }
        }
        revert("Balance not found");
    }

    function getMockPrices(JSON.TickerConfig[] memory cfg) internal view returns (PythView memory result) {
        (bytes32[] memory ids, int64[] memory prices) = _getPrices(cfg);
        require(ids.length == prices.length, "PythScript: mock price length mismatch");
        result.ids = new bytes32[](ids.length);
        result.prices = new Price[](ids.length);
        for (uint256 i = 0; i < prices.length; i++) {
            result.ids[i] = ids[i];
            result.prices[i] = Price({price: prices[i], conf: 1, expo: -8, publishTime: block.timestamp});
        }
    }

    function _getPrices(JSON.TickerConfig[] memory cfg) private pure returns (bytes32[] memory ids, int64[] memory prices) {
        uint256 count;

        for (uint256 i; i < cfg.length; i++) {
            if (cfg[i].pythId != bytes32(0)) {
                count++;
            }
        }

        ids = new bytes32[](count);
        prices = new int64[](count);

        count = 0;
        for (uint256 i; i < cfg.length; i++) {
            JSON.TickerConfig memory ticker = cfg[i];
            if (ticker.pythId != bytes32(0)) {
                ids[count] = ticker.pythId;
                prices[count] = int64(uint64(ticker.mockPrice));
                count++;
            }
        }
    }
}
