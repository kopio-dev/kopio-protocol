// solhint-disable code-complexity, state-visibility, max-states-count, var-name-mixedcase, no-global-import, const-name-snakecase, no-empty-blocks, no-console
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.26;

import {DeployBase} from "scripts/deploy/DeployBase.s.sol";
import {LibJSON} from "scripts/deploy/libs/LibJSON.s.sol";
import {LibMocks} from "scripts/deploy/libs/LibMocks.s.sol";
import {LibDeploy} from "scripts/deploy/libs/LibDeploy.s.sol";
import {LibDeployUtils} from "scripts/deploy/libs/LibDeployUtils.s.sol";
import {Utils, Log} from "kopio/vm/VmLibs.s.sol";
import {IPyth} from "kopio/vendor/Pyth.sol";
import {VaultAsset} from "vault/Types.sol";
import {SwapRouteSetter} from "scdp/Types.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import "scripts/deploy/JSON.s.sol" as JSON;
import {ERC20Mock} from "mocks/Mocks.sol";
import {Enums, Role} from "common/Constants.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {Asset, TickerOracles} from "common/Types.sol";
import {MintArgs} from "common/Args.sol";

struct CoreInfo {
    address diamond;
    bytes32 diamondHash;
    address factory;
    bytes32 factoryHash;
}

contract Deploy is DeployBase {
    using LibJSON for *;
    using LibMocks for *;
    using LibDeploy for *;
    using Deployed for *;
    using LibDeployUtils for *;
    using Log for *;
    using Utils for *;

    mapping(bytes32 => bool) private tickerExists;
    mapping(bytes32 => bool) private routeExists;
    SwapRouteSetter[] private routeCache;

    function deployCore(JSON.Config memory json, JSON.Salts memory salts, address deployer, address create2) internal returns (CoreInfo memory res) {
        (res.factory, res.factoryHash) = super.deployFactory(deployer, create2, salts.factory);
        (res.diamond, res.diamondHash) = super.deployDiamond(json, deployer, salts.protocol);
    }

    function exec(JSON.Config memory json, JSON.Salts memory salts, address deployer, bool noLog) private broadcasted(deployer) returns (JSON.Config memory) {
        if (json.params.factory == address(0)) {
            (json.params.factory, ) = super.deployFactory(deployer, json.params.create2Deployer, salts.factory);
        }
        // Create configured mocks, updates the received config with addresses.
        json = json.createMocks(deployer);
        pyth.get[block.chainid] = IPyth(json.params.common.pythEp);
        weth = json.assets.wNative.token;
        // Set tokens to cache as we know them at this point.
        json.cacheExtTokens();

        // Create base contracts
        (address diamond, ) = super.deployDiamond(json, deployer, salts.protocol);

        if (json.params.pythRelayer != address(0)) {
            protocol.setPythEPs(json.params.common.pythEp, json.params.pythRelayer);
        }

        vault = json.createVault(deployer, salts.vault);
        one = json.createONE(diamond, address(vault), salts.one);

        json = json.createKopios(diamond);

        /* ---------------------------- Externals ---------------------------*/
        _addExtAssets(json, diamond);
        /* ------------------------------ ONE ------------------------------ */
        _addONE(json);
        /* ------------------------------ assets -----------------------------*/
        _addKopios(json, diamond);
        /* -------------------------- Vault Assets -------------------------- */
        _addVaultAssets(json);
        /* -------------------------- Setup states -------------------------- */
        json.getAllTradeRoutes(routeCache, routeExists, address(one));
        protocol.setSwapRoutes(routeCache);
        delete routeCache;

        json.getCustomTradeRoutes(routeCache);
        for (uint256 i; i < routeCache.length; i++) {
            protocol.setSwapRoute(routeCache[i]);
        }
        delete routeCache;

        /* ---------------------------- Periphery --------------------------- */
        multicall = json.createMulticall(diamond, address(one), address(pyth.get[block.chainid]), salts.multicall);
        /* ------------------------------ Users ----------------------------- */
        if (json.users.accounts.length > 0) {
            setupUsers(json, noLog);
        }

        /* --------------------- Remove deployer access --------------------- */
        address admin = json.params.common.admin;
        if (admin != deployer) {
            protocol.transferOwnership(admin);
            vault.setGovernance(admin);
            Ownable(address(factory)).transferOwnership(admin);
            factory.setDeployer(admin, true);
            factory.setDeployer(deployer, true);
            protocol.grantRole(Role.DEFAULT_ADMIN, admin);
            protocol.grantRole(Role.ADMIN, admin);
            protocol.renounceRole(Role.ADMIN, deployer);
            protocol.renounceRole(Role.DEFAULT_ADMIN, deployer);
        }

        if (!noLog) {
            json.logOutput(protocol, address(one), address(vault));
            Log.br();
            Log.hr();
            Log.clg("Deployment finished!");
            Log.hr();
        }

        return json;
    }

    function _addONE(JSON.Config memory json) private {
        json
            .assets
            .one
            .symbol
            .cache(
                protocol.addAsset(
                    address(one),
                    json.assets.one.config.toAsset(json.assets.one.symbol),
                    TickerOracles([Enums.OracleType.Vault, Enums.OracleType.Empty], [address(vault), address(0)], [uint256(0), 0], bytes32(0), false, false)
                )
            )
            .logAsset(address(protocol), address(one));
        protocol.setGlobalIncome(address(one));
    }

    function _addVaultAssets(JSON.Config memory json) private {
        VaultAsset[] memory vaultAssets = json.getVaultAssets();
        for (uint256 i; i < vaultAssets.length; i++) {
            vault.addAsset(vaultAssets[i]).logOutput(address(vault));
        }
    }

    function _addExtAssets(JSON.Config memory json, address diamond) private {
        for (uint256 i; i < json.assets.extAssets.length; i++) {
            JSON.ExtAsset memory eAsset = json.assets.extAssets[i];
            Asset memory assetConfig = eAsset.config.toAsset(eAsset.symbol);
            TickerOracles memory tickerOracles;
            if (!tickerExists[assetConfig.ticker]) {
                tickerOracles = json.getTickerOracles(eAsset.config.ticker, eAsset.config.oracles);
                tickerExists[assetConfig.ticker] = true;
            }

            tickerExists[assetConfig.ticker] = true;
            eAsset.symbol.cache(protocol.addAsset(eAsset.addr, assetConfig, tickerOracles)).logAsset(diamond, eAsset.addr);
        }
    }

    function _addKopios(JSON.Config memory json, address diamond) private {
        for (uint256 i; i < json.assets.kopios.length; i++) {
            JSON.KopioConfig memory kopio = json.assets.kopios[i];

            Asset memory cfg = kopio.config.toAsset(kopio.symbol);
            TickerOracles memory feedConfig;
            if (!tickerExists[cfg.ticker]) {
                feedConfig = json.getTickerOracles(kopio.config.ticker, kopio.config.oracles);
                tickerExists[cfg.ticker] = true;
            }

            address addr = kopio.symbol.cached();
            kopio.symbol.cache(protocol.addAsset(addr, cfg, feedConfig)).logAsset(diamond, addr);
        }
    }

    /* ---------------------------------------------------------------------- */
    /*                               USER SETUPS                              */
    /* ---------------------------------------------------------------------- */

    function setupUsers(JSON.Config memory json, bool noLog) private restoreCallers {
        payable(address(protocol)).transfer(0.00001 ether);
        updatePythLocal(json.assets.tickers);
        setupBalances(json.users, json.assets);
        setupSCDP(json.users, json.assets);
        setupICDP(json.users, json.assets);

        if (!noLog) {
            for (uint256 i; i < json.users.accounts.length; i++) {
                json.logUserOutput(json.users.get(i), protocol, address(one));
            }
            Log.hr();
            Log.clg("Users setup finished!");
            Log.hr();
        }
    }

    function setupBalances(JSON.Users memory users, JSON.Assets memory assets) private {
        for (uint256 i; i < users.balances.length; i++) {
            JSON.Balance memory bal = users.balances[i];
            if (bal.user == JSON.ALL_USERS) {
                for (uint256 j; j < users.accounts.length; j++) {
                    setupBalance(assets, users.get(j), bal);
                }
            } else {
                setupBalance(assets, users.get(bal.user), bal);
            }
        }
    }

    function setupNativeWrapper(address user, JSON.Balance memory bal) private broadcasted(user) {
        if (bal.amount == 0) return;
        if (bal.assetsFrom == address(0)) {
            vm.deal(user, bal.amount);
            weth.deposit{value: bal.amount}();
        } else if (bal.assetsFrom == address(1)) {
            weth.deposit{value: bal.amount}();
        } else {
            _transfer(bal.assetsFrom, user, address(weth), bal.amount);
        }
    }

    function setupBalance(JSON.Assets memory assets, address user, JSON.Balance memory bal) internal rebroadcasted(user) returns (address token) {
        token = bal.symbol.cached();
        if (bal.amount == 0) return token;

        if (token == address(assets.wNative.token)) {
            setupNativeWrapper(user, bal);
            return token;
        }

        if (bal.assetsFrom == address(1)) {
            return token;
        }

        if (bal.assetsFrom == address(0)) {
            _mintTokens(user, token, bal.amount);
        } else {
            _transfer(bal.assetsFrom, user, token, bal.amount);
        }
    }

    function setupSCDP(JSON.Users memory users, JSON.Assets memory assets) private {
        for (uint256 i; i < users.scdp.length; i++) {
            JSON.SCDPPosition memory pos = users.scdp[i];
            if (pos.user == JSON.ALL_USERS) {
                for (uint256 j; j < users.accounts.length; j++) {
                    _setupSCDPUser(assets, users.get(j), j, pos);
                }
            } else {
                _setupSCDPUser(assets, users.get(pos.user), i, pos);
            }
        }
    }

    function setupICDP(JSON.Users memory users, JSON.Assets memory assets) private {
        function(JSON.Assets memory, address, uint256, JSON.ICDPPosition memory) setup;
        for (uint256 i; i < users.icdp.length; i++) {
            JSON.ICDPPosition memory pos = users.icdp[i];
            setup = pos.mintSymbol.equals("ONE") ? _setupONE : _setupICDP;

            if (pos.user == JSON.ALL_USERS) {
                for (uint256 j; j < users.accounts.length; j++) {
                    setup(assets, users.get(j), j, pos);
                }
            } else {
                setup(assets, users.get(pos.user), i, pos);
            }
        }
    }

    function _setupICDP(JSON.Assets memory assets, address user, uint256 idx, JSON.ICDPPosition memory pos) internal broadcasted(user) {
        if (pos.depositAmount > 0) {
            address collAddr = setupBalance(assets, user, JSON.Balance(idx, pos.depositSymbol, pos.depositAmount, pos.assetsFrom));

            _maybeApprove(collAddr, address(protocol), 1);
            protocol.depositCollateral(user, collAddr, pos.depositAmount);
        }

        if (pos.mintAmount == 0) return;
        if (user.balance < 0.005 ether) {
            vm.deal(getAddr(0), 0.01 ether);
            broadcastWith(0);
            payable(user).transfer(0.005 ether);
            broadcastWith(user);
        }
        protocol.mintKopio{value: pyth.viewData.ids.length}(MintArgs(user, pos.mintSymbol.cached(), pos.mintAmount, user), pyth.update);
    }

    function _setupONE(JSON.Assets memory assets, address user, uint256 idx, JSON.ICDPPosition memory pos) internal broadcasted(user) {
        if (pos.depositAmount > 0) {
            address addr = setupBalance(assets, user, JSON.Balance(idx, pos.depositSymbol, pos.depositAmount, pos.assetsFrom));
            _maybeApprove(addr, address(one), 1);
            one.vaultDeposit(addr, pos.depositAmount, user);
        } else {
            (uint256 assetsIn, ) = vault.previewMint(pos.depositSymbol.cached(), pos.mintAmount);
            address addr = setupBalance(assets, user, JSON.Balance(idx, pos.depositSymbol, assetsIn, pos.assetsFrom));

            _maybeApprove(addr, address(one), 1);
            one.vaultMint(addr, pos.mintAmount, user);
        }
    }

    function _setupSCDPUser(JSON.Assets memory assets, address user, uint256 idx, JSON.SCDPPosition memory pos) private broadcasted(user) {
        if (pos.oneDeposits == 0) return;

        address assetAddr = pos.vaultAssetSymbol.cached();
        (uint256 assetsIn, ) = vault.previewMint(assetAddr, pos.oneDeposits);

        setupBalance(assets, user, JSON.Balance(idx, pos.vaultAssetSymbol, assetsIn, pos.assetsFrom));

        _maybeApprove(assetAddr, address(one), 1);
        one.vaultMint(assetAddr, pos.oneDeposits, user);

        _maybeApprove(address(one), address(protocol), 1);
        protocol.depositSCDP(user, address(one), pos.oneDeposits);
    }

    function _maybeApprove(address token, address spender, uint256 amount) internal {
        if (ERC20Mock(token).allowance(msgSender(), spender) < amount) {
            ERC20Mock(token).approve(spender, type(uint256).max);
        }
    }

    function _mintTokens(address user, address token, uint256 amount) internal {
        ERC20Mock(token).mint(user, amount);
    }

    function _transfer(address from, address to, address token, uint256 amount) internal rebroadcasted(from) {
        ERC20Mock(token).transfer(to, amount);
    }

    function deploy(string memory network, string memory mnem, uint32 deployer, bool save, bool noLog) public mnemonic(mnem) returns (JSON.Config memory) {
        return deploy(network, network, mnem, deployer, save, noLog);
    }

    function deploy(
        string memory network,
        string memory configId,
        string memory mnem,
        uint32 deployer,
        bool save,
        bool noLog
    ) public mnemonic(mnem) returns (JSON.Config memory json) {
        if (noLog) LibDeploy.disableLog();
        else Log.clg(string.concat(network, ":", configId), "Deploying");
        if (save) LibDeploy.initOutputJSON(configId);

        json = exec(JSON.getConfig(network, configId), JSON.getSalts(network, configId), getAddr(deployer), noLog);

        if (save) LibDeploy.writeOutputJSON();
    }

    function deployTest(uint32 deployer) public returns (JSON.Config memory) {
        return deploy("test", "test-base", "MNEMONIC_KOPIO", deployer, true, true);
    }

    function deployTest(string memory mnemonic, string memory configId, uint32 deployer) public returns (JSON.Config memory) {
        return deploy("test", configId, mnemonic, deployer, true, true);
    }

    function deployFrom(
        string memory dir,
        string memory configId,
        string memory mnem,
        uint32 deployer,
        bool save,
        bool noLog
    ) public mnemonic(mnem) returns (JSON.Config memory json) {
        if (noLog) LibDeploy.disableLog();
        else Log.clg(string.concat(dir, configId), "Deploying from");
        if (save) LibDeploy.initOutputJSON(configId);

        json = exec(JSON.getConfigFrom(dir, configId), JSON.getSalts(configId, configId), getAddr(deployer), noLog);

        if (save) LibDeploy.writeOutputJSON();
    }

    function deployFromTest(string memory mnemonic, string memory dir, string memory configId, uint32 deployer) public returns (JSON.Config memory) {
        return deployFrom(dir, configId, mnemonic, deployer, false, true);
    }

    function get(string memory deployment) public returns (address) {
        return Deployed.addr(deployment);
    }
}
