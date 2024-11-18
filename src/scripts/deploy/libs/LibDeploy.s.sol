// solhint-disable var-name-mixedcase
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Vault} from "vault/Vault.sol";
import {KopioShare} from "asset/KopioShare.sol";
import {Deployment, Convert} from "kopio/utils/Deployment.sol";
import {Kopio} from "asset/Kopio.sol";
import {ONE} from "asset/ONE.sol";
import {KopioMulticall} from "periphery/KopioMulticall.sol";
import {Role} from "common/Constants.sol";
import {KopioCore} from "interfaces/KopioCore.sol";
import {VmHelp, Log, Utils, mvm} from "kopio/vm/VmLibs.s.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {CONST} from "scripts/deploy/CONST.s.sol";
import {LibJSON, JSON} from "scripts/deploy/libs/LibJSON.s.sol";

import {IProxyFactory} from "kopio/IProxyFactory.sol";
import {VaultConfiguration} from "vault/Types.sol";

library LibDeploy {
    using Convert for bytes[];
    using Log for *;
    using VmHelp for *;
    using Utils for *;
    using Deployed for *;
    using LibJSON for *;
    using LibDeploy for bytes;
    using LibDeploy for bytes32;

    function createONE(JSON.Config memory j, address protocol, address vault, bytes32 salt) internal saveOutput("ONE") returns (ONE result) {
        require(protocol != address(0), "ONE: !PROTOCOL");
        require(vault != address(0), "ONE: !Vault");
        string memory name = string.concat(CONST.ONE_PREFIX, j.assets.one.name);
        bytes memory init = abi.encodeCall(ONE.initialize, (name, j.assets.one.symbol, j.params.common.admin, protocol, vault));
        result = ONE(address(type(ONE).creationCode.p3(init, salt).proxy));
        j.assets.one.symbol.cache(address(result));
    }

    function createVault(JSON.Config memory j, address owner, bytes32 salt) internal saveOutput("Vault") returns (Vault) {
        string memory name = CONST.VAULT_NAME_PREFIX.cc(j.assets.one.name);
        string memory symbol = CONST.VAULT_SYMBOL_PREFIX.cc(j.assets.one.symbol);

        VaultConfiguration memory config = VaultConfiguration({
            governance: owner,
            pendingGovernance: address(0),
            feeRecipient: j.params.common.treasury,
            sequencerUptimeFeed: j.params.common.sequencerUptimeFeed,
            sequencerGracePeriodTime: 3600,
            oracleDecimals: j.params.common.oracleDecimals
        });

        return Vault(address(type(Vault).creationCode.p3(abi.encodeCall(Vault.initialize, (name, symbol, config, j.params.common.kopioCLV3)), salt).proxy));
    }

    function createMulticall(JSON.Config memory j, address protocol, address one, address pythEP, bytes32 salt) internal saveOutput("Multicall") returns (KopioMulticall) {
        bytes memory impl = type(KopioMulticall).creationCode.ctor(abi.encode(protocol, one));
        bytes memory init = abi.encodeCall(KopioMulticall.initialize, (j.params.periphery.v3Router, address(j.assets.wNative.token), pythEP, j.params.common.admin));
        LibDeploy.setJsonBytes("INIT_CODE_HASH", bytes.concat(keccak256(impl)));
        address multicall = address(impl.p3(init, salt).proxy);
        KopioCore(protocol).grantRole(Role.MANAGER, multicall);
        return KopioMulticall(payable(multicall));
    }

    function createKopios(JSON.Config memory j, address protocol) internal returns (JSON.Config memory) {
        for (uint256 i; i < j.assets.kopios.length; i++) {
            DeployResult memory deployed = deployKopio(j, j.assets.kopios[i], protocol);
            j.assets.kopios[i].config.share = deployed.shareAddr;
        }

        return j;
    }

    function deployKopio(JSON.Config memory j, JSON.KopioConfig memory cfg, address protocol) internal returns (DeployResult memory result) {
        JSONKey(cfg.symbol);
        LibJSON.Metadata memory meta = cfg.metadata();
        address underlying = !cfg.underlyingSymbol.zero() ? cfg.underlyingSymbol.cached() : address(0);
        bytes memory kopioInit = abi.encodeCall(
            Kopio.initialize,
            (meta.name, meta.symbol, j.params.common.admin, protocol, underlying, j.params.common.treasury, cfg.wrapFee, cfg.unwrapFee)
        );
        (address proxyAddr, address implAddr) = meta.salt.pp3();
        setJsonAddr("address", proxyAddr);
        setJsonBytes("init", proxyInit(implAddr, kopioInit));
        setJsonAddr("impl", implAddr);
        saveJSONKey();

        JSONKey(meta.ksSymbol);
        bytes memory shareImpl = type(KopioShare).creationCode.ctor(abi.encode(proxyAddr));
        bytes memory shareInit = abi.encodeCall(KopioShare.initialize, (meta.ksName, meta.ksSymbol, j.params.common.admin));

        bytes[] memory batch = new bytes[](2);
        batch[0] = abi.encodeCall(factory().create3ProxyAndLogic, (type(Kopio).creationCode, kopioInit, meta.salt));
        batch[1] = abi.encodeCall(factory().create3ProxyAndLogic, (shareImpl, shareInit, meta.shareSalt));
        Deployment[] memory proxies = factory().batch(batch).map(Convert.toDeployment);

        result.addr = address(proxies[0].proxy);
        result.shareAddr = address(proxies[1].proxy);
        result.shareSymbol = meta.ksSymbol;
        cfg.symbol.cache(result.addr);
        result.shareSymbol.cache(result.shareAddr);
        setJsonAddr("address", result.shareAddr);
        setJsonBytes("init", proxyInit(proxies[1].implementation, shareInit));
        setJsonAddr("implementation", proxies[1].implementation);
        saveJSONKey();
        result.j = cfg;
    }

    function proxyInit(address impl, bytes memory init) internal returns (bytes memory) {
        return abi.encode(impl, address(factory()), init);
    }

    function pd3(bytes32 salt) internal returns (address) {
        return factory().getCreate3Address(salt);
    }

    function pp3(bytes32 salt) internal returns (address, address) {
        return factory().previewCreate3ProxyAndLogic(salt);
    }

    function ctor(bytes memory bcode, bytes memory args) internal returns (bytes memory ccode) {
        setJsonBytes("ctor", args);
        return abi.encodePacked(bcode, args);
    }

    function d2(bytes memory ccode, bytes memory _init, bytes32 _salt) internal returns (Deployment memory result) {
        result = factory().deployCreate2(ccode, _init, _salt);
        setJsonAddr("address", result.implementation);
    }

    function d3(bytes memory ccode, bytes memory _init, bytes32 _salt) internal returns (Deployment memory result) {
        result = factory().deployCreate3(ccode, _init, _salt);
        setJsonAddr("address", result.implementation);
    }

    function p3(bytes memory ccode, bytes memory _init, bytes32 _salt) internal returns (Deployment memory result) {
        result = factory().create3ProxyAndLogic(ccode, _init, _salt);
        setJsonAddr("address", address(result.proxy));
        setJsonBytes("init", proxyInit(result.implementation, _init));
        setJsonAddr("impl", result.implementation);
    }

    function peekAddr3(JSON.KopioConfig memory asset) internal returns (address) {
        return asset.metadata().salt.pd3();
    }

    function previewTokenAddr(JSON.Config memory json, string memory symbol) internal returns (address) {
        for (uint256 i; i < json.assets.extAssets.length; i++) {
            if (json.assets.extAssets[i].symbol.equals(symbol)) {
                if (json.assets.extAssets[i].mocked) {
                    return json.assets.extAssets[i].symbol.mockTokenSalt().pd3();
                }
                return json.assets.extAssets[i].addr;
            }
        }

        for (uint256 i; i < json.assets.kopios.length; i++) {
            if (json.assets.kopios[i].symbol.equals(symbol)) {
                return peekAddr3(json.assets.kopios[i]);
            }
        }
        revert(("!assetAddr: ").cc(symbol));
    }

    bytes32 internal constant DEPLOY_STATE_SLOT = keccak256("deploy.state.slot");

    struct DeployResult {
        address addr;
        address shareAddr;
        string symbol;
        string shareSymbol;
        JSON.KopioConfig j;
    }

    struct DeployState {
        IProxyFactory factory;
        string id;
        string outputLocation;
        string currentKey;
        string currentJson;
        string outputJson;
        bool disableLog;
    }

    function initOutputJSON(string memory configId) internal {
        string memory outputDir = string.concat("./out/foundry/deploy/", mvm.toString(block.chainid), "/");
        if (!mvm.exists(outputDir)) mvm.createDir(outputDir, true);
        state().id = configId;
        state().outputLocation = outputDir;
        state().outputJson = configId;
    }

    function writeOutputJSON() internal {
        string memory runsDir = string.concat(state().outputLocation, "runs/");
        if (!mvm.exists(runsDir)) mvm.createDir(runsDir, true);
        mvm.writeFile(string.concat(runsDir, state().id, "-", mvm.toString(mvm.unixTime()), ".json"), state().outputJson);
        mvm.writeFile(string.concat(state().outputLocation, state().id, "-", "latest", ".json"), state().outputJson);
    }

    function state() internal pure returns (DeployState storage ds) {
        bytes32 slot = DEPLOY_STATE_SLOT;
        assembly {
            ds.slot := slot
        }
    }

    modifier saveOutput(string memory id) {
        JSONKey(id);
        _;
        saveJSONKey();
    }

    function JSONKey(string memory id) internal {
        state().currentKey = id;
        state().currentJson = "";
    }

    function setJsonAddr(string memory key, address val) internal {
        state().currentJson = mvm.serializeAddress(state().currentKey, key, val);
    }

    function setJsonBool(string memory key, bool val) internal {
        state().currentJson = mvm.serializeBool(state().currentKey, key, val);
    }

    function setJsonNumber(string memory key, uint256 val) internal {
        state().currentJson = mvm.serializeUint(state().currentKey, key, val);
    }

    function setJsonBytes(string memory key, bytes memory val) internal {
        state().currentJson = mvm.serializeBytes(state().currentKey, key, val);
    }

    function saveJSONKey() internal {
        state().outputJson = mvm.serializeString("out", state().currentKey, state().currentJson);
    }

    function disableLog() internal {
        state().disableLog = true;
    }

    function factory() internal returns (IProxyFactory factory_) {
        if (address(state().factory) == address(0)) {
            state().factory = Deployed.factory();
        }
        return state().factory;
    }

    function cacheExtTokens(JSON.Config memory input) internal {
        for (uint256 i; i < input.assets.extAssets.length; i++) {
            JSON.ExtAsset memory ext = input.assets.extAssets[i];
            ext.symbol.cache(ext.addr);
            if (ext.mocked) continue;
            JSONKey(ext.symbol);
            setJsonAddr("address", ext.addr);
            saveJSONKey();
        }

        if (input.assets.wNative.mocked) {
            input.assets.wNative.symbol.cache(address(input.assets.wNative.token));
            return;
        }
        JSONKey("wNative");
        setJsonAddr("address", address(input.assets.wNative.token));
        saveJSONKey();
    }
}
