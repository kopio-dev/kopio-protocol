// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;
import {CommonInitializer} from "common/Types.sol";
import {SCDPInitializer} from "scdp/Types.sol";
import {ICDPInitializer} from "icdp/Types.sol";
import {IWETH9Arb} from "kopio/token/IWETH9.sol";
import {Enums} from "common/Constants.sol";
import {LibJSON} from "scripts/deploy/libs/LibJSON.s.sol";
import {VmHelp, Utils, mAddr, mvm} from "kopio/vm/VmLibs.s.sol";
import {CONST} from "scripts/deploy/CONST.s.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";

struct Files {
    string params;
    string assets;
    string users;
}

using VmHelp for string;
using Utils for string;

function getConfig(string memory network, string memory configId) returns (Config memory json) {
    string memory dir = CONST.CONFIG_DIR.cc(network, "/");

    return getConfigFrom(dir, configId);
}

function getSalts(string memory network, string memory configId) returns (Salts memory) {
    string memory location = string.concat(CONST.CONFIG_DIR.cc(network, "/"), "salts-", configId, ".json");
    if (!mvm.exists(location)) return Salts("KopioCore", "ProxyFactory", "ONE", "Multicall", "MarketStatus", "Vault");
    return abi.decode(mvm.parseJson(mvm.readFile(location)), (Salts));
}

function getConfigFrom(string memory dir, string memory configId) returns (Config memory json) {
    Files memory files;

    files.params = string.concat(dir, "params-", configId, ".json");
    if (!mvm.exists(files.params)) {
        revert(files.params.cc(": no configuration exists."));
    }

    json.params = abi.decode(mvm.parseJson(mvm.readFile(files.params)), (Params));
    json.assets = getAssetConfigFrom(dir, configId);

    files.users = string.concat(dir, "users-", configId, ".json");
    if (mvm.exists(files.users)) {
        json.users = abi.decode(mvm.parseJson(mvm.readFile(files.users)), (Users));
    }

    if (json.params.common.admin == address(0)) {
        json.params.common.admin = mAddr("MNEMONIC_KOPIO", 0);
    }

    Deployed.init(configId);
}

// stacks too deep so need to split assets into separate function
function getAssetConfig(string memory network, string memory configId) returns (Assets memory json) {
    return getAssetConfigFrom(string.concat(CONST.CONFIG_DIR, network, "/"), configId);
}

function getAssetConfigFrom(string memory dir, string memory configId) returns (Assets memory result) {
    string memory location = string.concat(dir, "assets-", configId, ".json");
    if (!mvm.exists(location)) {
        revert(location.cc(": no asset configuration exists."));
    }
    result = abi.decode(mvm.parseJson(mvm.readFile(location)), (Assets));
}

function getKopio(Config memory cfg, string memory symbol) pure returns (KopioParams memory result) {
    for (uint256 i; i < cfg.assets.kopios.length; i++) {
        if (cfg.assets.kopios[i].symbol.equals(symbol)) {
            result.json = cfg.assets.kopios[i];
            break;
        }
    }

    for (uint256 i; i < cfg.assets.extAssets.length; i++) {
        if (cfg.assets.extAssets[i].symbol.equals(result.json.underlyingSymbol)) {
            result.underlying = cfg.assets.extAssets[i];
            break;
        }
    }
    for (uint256 i; i < cfg.assets.tickers.length; i++) {
        if (cfg.assets.tickers[i].ticker.equals(result.json.config.ticker)) {
            result.ticker = cfg.assets.tickers[i];
            break;
        }
    }
}

function getExtAsset(Config memory cfg, string memory symbol) pure returns (ExtAssetParams memory result) {
    for (uint256 i; i < cfg.assets.extAssets.length; i++) {
        if (cfg.assets.extAssets[i].symbol.equals(symbol)) {
            result.json = cfg.assets.extAssets[i];
            break;
        }
    }
    for (uint256 i; i < cfg.assets.tickers.length; i++) {
        if (cfg.assets.tickers[i].ticker.equals(result.json.config.ticker)) {
            result.ticker = cfg.assets.tickers[i];
            break;
        }
    }
}

struct KopioParams {
    KopioConfig json;
    ExtAsset underlying;
    TickerConfig ticker;
}

struct ExtAssetParams {
    ExtAsset json;
    TickerConfig ticker;
}

struct Salts {
    bytes32 protocol;
    bytes32 factory;
    bytes32 one;
    bytes32 multicall;
    bytes32 marketstatus;
    bytes32 vault;
}

struct Config {
    Params params;
    Assets assets;
    Users users;
}

struct Params {
    string configId;
    address create2Deployer;
    address factory;
    CommonInitializer common;
    SCDPInitializer scdp;
    ICDPInitializer icdp;
    Periphery periphery;
    address pythRelayer;
}

struct Periphery {
    address v3Router;
    address quoterv2;
}

struct Assets {
    string configId;
    bool mockFeeds;
    WNative wNative;
    ExtAsset[] extAssets;
    KopioConfig[] kopios;
    ONEConfig one;
    TickerConfig[] tickers;
    TradeRouteConfig[] customTradeRoutes;
}

struct ONEConfig {
    string name;
    string symbol;
    AssetJSON config;
}

struct WNative {
    bool mocked;
    string name;
    string symbol;
    IWETH9Arb token;
}

struct ExtAsset {
    bool mocked;
    bool isVaultAsset;
    string name;
    string symbol;
    address addr;
    AssetJSON config;
    VaultAssetJSON vault;
}

struct TickerConfig {
    string ticker;
    uint256 mockPrice;
    uint8 priceDecimals;
    address chainlink;
    address api3;
    address vault;
    bytes32 pythId;
    uint256 staleTimePyth;
    uint256 staleTimeAPI3;
    uint256 staleTimeChainlink;
    uint256 staleTimeRedstone;
    bool useAdapter;
    bool invertPyth;
    bool isClosable;
}

struct Balance {
    uint256 user;
    string symbol;
    uint256 amount;
    address assetsFrom;
}

struct ICDPPosition {
    uint256 user;
    string depositSymbol;
    uint256 depositAmount;
    address assetsFrom;
    string mintSymbol;
    uint256 mintAmount;
}

struct SCDPPosition {
    uint256 user;
    uint256 oneDeposits;
    string vaultAssetSymbol;
    address assetsFrom;
}

struct TradeRouteConfig {
    string assetA;
    string assetB;
    bool enabled;
}

struct Account {
    uint32 idx;
    address addr;
}

struct NFTSetup {
    bool useMocks;
    address nftsFrom;
    uint256 userCount;
}

struct Users {
    string configId;
    string mnemonicEnv;
    Account[] accounts;
    Balance[] balances;
    SCDPPosition[] scdp;
    ICDPPosition[] icdp;
    NFTSetup nfts;
}

/// @notice forge cannot parse structs with fixed arrays so we use this intermediate struct
struct AssetJSON {
    string ticker;
    address share;
    Enums.OracleType[] oracles;
    uint16 factor;
    uint16 dFactor;
    uint16 openFee;
    uint16 closeFee;
    uint16 liqIncentive;
    uint256 mintLimit;
    uint256 mintLimitSCDP;
    uint256 depositLimitSCDP;
    uint16 swapInFee;
    uint16 swapOutFee;
    uint16 protocolFeeShareSCDP;
    uint16 liqIncentiveSCDP;
    uint8 decimals;
    bool isCollateral;
    bool isKopio;
    bool isGlobalDepositable;
    bool isSwapMintable;
    bool isGlobalCollateral;
    bool isCoverAsset;
}

struct VaultAssetJSON {
    string[] feed;
    uint24 staleTime;
    uint32 depositFee;
    uint32 withdrawFee;
    uint248 maxDeposits;
    bool enabled;
}

struct KopioConfig {
    string name;
    string symbol;
    string underlyingSymbol;
    uint48 wrapFee;
    uint40 unwrapFee;
    AssetJSON config;
}

function get(Users memory users, uint256 i) returns (address) {
    Account memory acc = users.accounts[i];
    if (acc.addr == address(0)) {
        return mAddr(users.mnemonicEnv, acc.idx);
    }
    return acc.addr;
}

uint256 constant ALL_USERS = 9999;

using {get} for Users global;

using {LibJSON.metadata} for KopioConfig global;
using {LibJSON.toAsset} for AssetJSON global;
