// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {Asset, OraclePrice} from "common/Types.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {KopioCore} from "interfaces/KopioCore.sol";
import {Utils, Log} from "kopio/vm/VmLibs.s.sol";
import {VaultAsset} from "vault/Types.sol";
import {IVault} from "interfaces/IVault.sol";
import {SwapRouteSetter} from "scdp/Types.sol";
import {LibDeploy} from "scripts/deploy/libs/LibDeploy.s.sol";
import "scripts/deploy/JSON.s.sol" as JSON;
import {toWad} from "common/funcs/Math.sol";
import {LibJSON} from "scripts/deploy/libs/LibJSON.s.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";

library LibDeployUtils {
    using Log for *;
    using Utils for *;
    using LibDeploy for *;
    using LibJSON for *;
    using Deployed for *;

    function getAllTradeRoutes(JSON.Config memory json, SwapRouteSetter[] storage routes, mapping(bytes32 => bool) storage routeExists, address one) internal {
        for (uint256 i; i < json.assets.kopios.length; i++) {
            JSON.KopioConfig memory kopio = json.assets.kopios[i];
            address assetIn = kopio.symbol.cached();
            bytes32 onePairId = one.pairId(assetIn);
            if (!routeExists[onePairId]) {
                routeExists[onePairId] = true;
                routes.push(SwapRouteSetter({assetIn: one, assetOut: assetIn, enabled: true}));
            }
            for (uint256 j; j < json.assets.kopios.length; j++) {
                address assetOut = json.assets.kopios[j].symbol.cached();
                if (assetIn == assetOut) continue;
                bytes32 pairId = assetIn.pairId(assetOut);
                if (routeExists[pairId]) continue;

                routeExists[pairId] = true;
                routes.push(SwapRouteSetter({assetIn: assetIn, assetOut: assetOut, enabled: true}));
            }
        }
    }

    function getCustomTradeRoutes(JSON.Config memory json, SwapRouteSetter[] storage routes) internal {
        for (uint256 i; i < json.assets.customTradeRoutes.length; i++) {
            JSON.TradeRouteConfig memory route = json.assets.customTradeRoutes[i];
            routes.push(SwapRouteSetter({assetIn: route.assetA.cached(), assetOut: route.assetA.cached(), enabled: route.enabled}));
        }
    }

    function logUserOutput(JSON.Config memory json, address user, KopioCore protocol, address one) internal view {
        if (LibDeploy.state().disableLog) return;
        Log.br();
        Log.hr();
        Log.clg("Test User");
        user.clg("Address");
        Log.hr();
        user.balance.dlg("Ether");

        for (uint256 i; i < json.assets.extAssets.length; i++) {
            JSON.ExtAsset memory asset = json.assets.extAssets[i];
            IERC20 token = IERC20(asset.addr);

            uint256 balance = token.balanceOf(user);
            balance.dlg(token.symbol(), token.decimals());
            protocol.getAccountCollateralAmount(user, address(token)).dlg("MDeposit", token.decimals());
        }

        for (uint256 i; i < json.assets.kopios.length; i++) {
            JSON.KopioConfig memory kopio = json.assets.kopios[i];
            IERC20 token = IERC20(kopio.symbol.cached());
            uint256 balance = token.balanceOf(user);

            balance.dlg(token.symbol(), token.decimals());
            protocol.getAccountCollateralAmount(user, address(token)).dlg("MDeposit", token.decimals());
            protocol.getAccountDebtAmount(user, address(token)).dlg("MDebt", token.decimals());
        }

        IERC20(one).balanceOf(user).dlg("ONE", 18);
        protocol.getDepositsSCDP(user).dlg("SCDP Deposits", 18);
    }

    function logOutput(JSON.Config memory json, KopioCore protocol, address one, address vault) internal view {
        if (LibDeploy.state().disableLog) return;
        Log.br();
        Log.hr();
        Log.clg("Protocol");
        address(protocol).clg("Address");
        address(one).clg("ONE");
        address(vault).clg(string.concat("Vault (name: ", IERC20(vault).name(), " symbol:", IERC20(vault).symbol(), ")"));
        address(json.params.factory).clg("ProxyFactory");
        address(protocol.getMarketStatusProvider()).clg("MarketStatus");
        protocol.hasRole(0, json.params.common.admin).clg("HasAdmin");
        Log.hr();
        for (uint256 i; i < json.assets.extAssets.length; i++) {
            JSON.ExtAsset memory asset = json.assets.extAssets[i];
            IERC20 token = IERC20(asset.addr);

            Log.hr();
            "Name".clg(token.name());
            "Symbol".clg(token.symbol());

            uint256 tSupply = token.totalSupply();
            uint256 bal = token.balanceOf(address(protocol));
            uint256 price = uint256(protocol.getPushPrice(address(token)).answer);

            tSupply.dlg("Total Supply", token.decimals());
            uint256 wadSupply = toWad(tSupply, token.decimals());
            wadSupply.wmul(price).dlg("Market Cap USD", 8);

            bal.dlg("kopio balance", token.decimals());

            uint256 wadBal = toWad(bal, token.decimals());
            wadBal.wmul(price).dlg("kopio balance USD", 8);
        }
        for (uint256 i; i < json.assets.kopios.length; i++) {
            JSON.KopioConfig memory kopio = json.assets.kopios[i];
            IERC20 token = IERC20(kopio.symbol.cached());

            Log.hr();
            "Name".clg(token.name());
            "Symbol".clg(token.symbol());

            uint256 tSupply = token.totalSupply();
            uint256 balance = token.balanceOf(address(protocol));
            uint256 price = uint256(protocol.getPushPrice(address(token)).answer);
            tSupply.dlg("Total Minted", token.decimals());
            tSupply.wmul(price).dlg("Market Cap USD", 8);
            balance.dlg("kopio balance", token.decimals());
            balance.wmul(price).dlg("kopio balance USD", 8);
        }
        {
            Log.hr();
            "Name".clg(IERC20(one).name());
            "Symbol".clg(IERC20(one).symbol());
            uint256 tSupply = IERC20(one).totalSupply();
            uint256 onePrice = uint256(protocol.getPushPrice(one).answer);
            tSupply.dlg("Total Minted", 18);
            tSupply.wmul(onePrice).dlg("Market Cap USD", 8);

            IERC20(one).balanceOf(address(protocol)).dlg("kopio balance");
            uint256 scdpDeposits = protocol.getDepositsSCDP(one);
            scdpDeposits.dlg("SCDP Deposits", 18);
            scdpDeposits.wmul(onePrice).dlg("SCDP Deposits USD", 8);
        }
    }

    function logAsset(Asset memory config, address protocol, address asset) internal view {
        if (LibDeploy.state().disableLog) return;
        IERC20 token = IERC20(asset);
        OraclePrice memory price = KopioCore(protocol).getPushPrice(asset);
        Log.br();

        ("/* ------------------------------ Protocol Asset ------------------------------ */").clg();
        "Name".clg(token.name());
        "Symbol".clg(token.symbol());
        asset.clg("Address");
        address(config.share).clg("Share");

        ("-------  Types --------").clg();
        config.isKopio.clg("ICDP Mintable");
        config.isCollateral.clg("ICDP Collateral");
        config.isSwapMintable.clg("SCDP Swappable");
        config.isGlobalDepositable.clg("SCDP Depositable");

        ("-------  Oracle --------").clg();
        config.ticker.str().clg("Ticker");
        price.feed.clg("Feed");
        uint256(price.answer).dlg("Feed Price", 8);
        uint8(config.oracles[0]).clg("Primary Oracle");
        uint8(config.oracles[1]).clg("Secondary Oracle");

        ("-------  Config --------").clg();
        config.mintLimit.dlg("ICDP Debt Limit", 18);
        config.mintLimitSCDP.dlg("SCDP Debt Limit", 18);
        config.dFactor.plg("dFactor");
        config.factor.plg("cFactor");
        config.openFee.plg("ICDP Open Fee");
        config.closeFee.plg("ICDP Close Fee");
        config.swapInFee.plg("SCDP Swap In Fee");
        config.swapOutFee.plg("SCDP Swap Out Fee");
        config.protocolFeeShareSCDP.plg("SCDP Protocol Fee");
        config.liqIncentiveSCDP.plg("SCDP Liquidation Incentive");
    }

    function logOutput(VaultAsset memory config, address vault) internal view {
        if (LibDeploy.state().disableLog) return;
        address assetAddr = address(config.token);
        Log.br();
        ("/* ------------------------------- Vault Asset ------------------------------ */").clg();
        "Name".clg(config.token.name());
        "Symbol".clg(config.token.symbol());
        assetAddr.clg("Address");
        config.token.decimals().clg("Decimals");
        ("-------  Oracle --------").clg();
        address(config.feed).clg("Feed");
        IVault(vault).assetPrice(assetAddr).dlg("Price", 8);
        config.staleTime.clg("Stale Price Time");
        ("-------  Config --------").clg();
        config.maxDeposits.dlg("Max Deposit Amount", config.decimals);
        config.depositFee.plg("Deposit Fee");
        config.withdrawFee.plg("Withdraw Fee");
    }
}
