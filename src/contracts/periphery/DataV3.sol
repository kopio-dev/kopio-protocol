// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {Asset, Enums, Oracle} from "kopio/IKopioCore.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {PythView, Price} from "kopio/vendor/Pyth.sol";
import {IData} from "./IData.sol";
import {Pyth} from "kopio/utils/Oracles.sol";
import {Utils} from "kopio/utils/Libs.sol";
import {iCore, addr} from "kopio/info/ArbDeploy.sol";
import {IPyth} from "kopio/vendor/Pyth.sol";
import {IQuoterV2} from "kopio/vendor/IQuoterV2.sol";
import {ILZ1155} from "kopio/token/ILZ1155.sol";
import {VaultAsset, IVault} from "kopio/IVault.sol";
import {IKopioCLV3} from "kopio/IKopioCLV3.sol";

contract DataV3 is IData {
    using Utils for *;

    IKopioCLV3 kclv3;
    IVault constant vault = IVault(addr.vault);

    ILZ1155 constant kreskian = ILZ1155(0xAbDb949a18d27367118573A217E5353EDe5A0f1E);
    ILZ1155 constant qfk = ILZ1155(0x1C04925779805f2dF7BbD0433ABE92Ea74829bF6);

    mapping(address => Oracles) oracles;
    mapping(address => bool) owners;

    function setOwner(address owner, bool isOwner) external {
        if (owners[msg.sender] || address(kclv3) == address(0)) {
            owners[owner] = isOwner;
        }
        _refresh();
    }

    function setOracles(Oracles[] memory exts) external {
        if (owners[msg.sender]) {
            for (uint256 i; i < exts.length; i++) {
                oracles[exts[i].addr] = exts[i];
            }
        }
        _refresh();
    }

    function _refresh() internal {
        kclv3 = IKopioCLV3(iCore.getKCLV3());
        (address[] memory addrs, Asset[] memory cfgs) = iCore.aDataAssetConfigs(0);
        for (uint256 i; i < addrs.length; i++) {
            (address taddr, Asset memory cfg) = (addrs[i], cfgs[i]);
            Oracle memory pyth = iCore.getOracleOfTicker(cfg.ticker, Enums.OracleType.Pyth);
            oracles[taddr] = Oracles({
                addr: taddr,
                clFeed: iCore.getFeedForAddress(taddr, cfg.oracles[1]),
                pythId: pyth.pythId,
                invertPyth: pyth.invertPyth,
                ext: false
            });
        }
    }

    function getGlobals(PythView calldata prices, address[] memory exts) public view returns (G memory) {
        Protocol memory p = iCore.aDataProtocol(prices);
        return
            G({
                assets: p.assets,
                scdp: p.scdp,
                icdp: p.icdp,
                maxDeviation: p.maxDeviation,
                oracleDec: p.oracleDecimals,
                safety: p.safety,
                tvl: p.tvl,
                pythEp: address(0),
                blockNr: 0,
                seqPeriod: p.seqGracePeriod,
                seqStart: p.seqStartAt,
                seqUp: p.seqUp,
                vault: _vault(),
                collections: _getCollectionData(address(1)),
                wraps: _wraps(p.assets),
                tokens: _getTokens(p.assets, address(0), exts),
                chainId: block.chainid,
                timestamp: uint32(block.timestamp)
            });
    }

    function getAccount(PythView calldata prices, address acc, address[] calldata exts) external view returns (A memory ac) {
        Account memory data = iCore.aDataAccount(prices, acc);
        ac.addr = data.addr;
        ac.icdp = data.icdp;
        ac.scdp = data.scdp;

        ac.collections = _getCollectionData(acc);
        ac.chainId = block.chainid;
        ac.tokens = _getTokens(iCore.aDataProtocol(prices).assets, acc, exts);
    }

    function _getTokens(TAsset[] memory assets, address acc, address[] memory exts) internal view returns (Tkn[] memory r) {
        r = new Tkn[](assets.length + exts.length + 1);

        uint256 i;
        uint256 ethPrice;

        for (i; i < assets.length; i++) {
            if (assets[i].config.ticker == "ETH") ethPrice = r[i].price;
            r[i] = _assetToToken(acc, assets[i]);
        }

        for (uint256 j; j < exts.length; j++) {
            r[i++] = _getExtToken(acc, exts[j]);
        }

        uint256 nativeBal = acc != address(0) ? acc.balance : 0;
        r[i] = Tkn({
            addr: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            name: "Ethereum",
            symbol: "ETH",
            decimals: 18,
            amount: nativeBal,
            val: nativeBal.wmul(ethPrice),
            tSupply: 0,
            price: ethPrice,
            chainId: block.chainid,
            isKopio: false,
            isCollateral: true,
            ticker: "ETH",
            oracleDec: 8
        });
    }

    function _getVAssets() internal view returns (VA[] memory va) {
        VaultAsset[] memory assets = vault.allAssets();
        va = new VA[](assets.length);

        for (uint256 i; i < assets.length; i++) {
            VaultAsset memory a = assets[i];

            va[i] = VA({
                addr: address(a.token),
                name: a.token.name(),
                symbol: _symbol(address(a.token)),
                tSupply: a.token.totalSupply(),
                vSupply: a.token.balanceOf(addr.vault),
                price: vault.assetPrice(address(a.token)),
                isMarketOpen: true,
                oracleDec: a.feed.decimals(),
                config: a
            });
        }
    }

    function _getCollectionItems(address acc, ILZ1155 coll) internal view returns (CItem[] memory res) {
        res = new CItem[](coll == kreskian ? 1 : 8);

        for (uint256 i; i < res.length; i++) {
            res[i] = CItem(i, coll.uri(i), coll.balanceOf(acc, i));
        }
    }

    function _getCollectionData(address acc) internal view returns (C[] memory res) {
        res = new C[](2);
        for (uint256 i; i < res.length; i++) {
            ILZ1155 coll = i == 0 ? kreskian : qfk;
            res[i] = C({
                uri: coll.contractURI(),
                addr: address(coll),
                name: coll.name(),
                symbol: coll.symbol(),
                items: _getCollectionItems(acc, coll)
            });
        }
    }

    function previewWithdraw(PreviewWd calldata args) external payable returns (uint256 amount, uint256 fee) {
        amount = args.outputAmount;

        if (args.path.length != 0) {
            (amount, , , ) = IQuoterV2(addr.quoterv2).quoteExactOutput(args.path, args.outputAmount);
        }
        return vault.previewWithdraw(args.vaultAsset, amount);
    }

    function _wraps(TAsset[] memory assets) internal view returns (W[] memory res) {
        uint256 items;
        for (uint256 i; i < assets.length; i++) {
            if (assets[i].wrap.underlying != address(0)) ++items;
        }
        res = new W[](items);
        for (uint256 i; i < assets.length; i++) {
            TAsset memory a = assets[i];
            if (a.wrap.underlying != address(0)) {
                uint256 amount = IERC20(a.wrap.underlying).balanceOf(a.addr);
                uint256 native = a.addr.balance;
                res[--items] = W(
                    a.addr,
                    a.wrap.underlying,
                    a.symbol,
                    a.price,
                    a.config.decimals,
                    amount,
                    native,
                    amount.toWad(a.wrap.underlyingDec).wmul(a.price),
                    native.wmul(a.price)
                );
            }
        }
    }

    function _getExtToken(address acc, address tkn) internal view returns (Tkn memory) {
        TokenData memory d = _tokenData(acc, tkn, 0, 0);

        return
            Tkn({
                addr: tkn,
                ticker: d.symbol,
                name: d.name,
                symbol: d.symbol,
                decimals: d.decimals,
                amount: d.balance,
                val: d.value,
                tSupply: d.tSupply,
                price: d.price,
                isKopio: false,
                isCollateral: false,
                oracleDec: d.oracleDec,
                chainId: block.chainid
            });
    }

    function _symbol(address tkn) internal view returns (string memory) {
        if (tkn == 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8) return "USDC.e";
        return IERC20(tkn).symbol();
    }

    function _getPrice(address tkn) internal view returns (uint256 price, uint8) {
        Oracles memory cfg = oracles[tkn];
        try IPyth(addr.pyth).getPriceNoOlderThan(cfg.pythId, 30) returns (Price memory p) {
            return Pyth.processPyth(p, cfg.invertPyth);
        } catch {
            if (iCore.getAsset(tkn).oracles[1] == Enums.OracleType.ChainlinkDerived) {
                price = kclv3.getDerivedAnswer(cfg.clFeed).price;
            }
            price = kclv3.getAnswer(cfg.clFeed).answer;
        }

        return (price, 8);
    }

    function _assetToToken(address acc, TAsset memory a) internal view returns (Tkn memory) {
        TokenData memory t = _tokenData(acc, a.addr, a.price, 8);
        return
            Tkn({
                addr: a.addr,
                ticker: a.config.ticker.str(),
                name: t.name,
                symbol: t.symbol,
                decimals: t.decimals,
                amount: t.balance,
                val: t.value,
                tSupply: t.tSupply,
                price: t.price,
                chainId: block.chainid,
                isKopio: a.config.dFactor > 0,
                isCollateral: a.config.factor > 0,
                oracleDec: t.oracleDec
            });
    }

    function _tokenData(address acc, address tkn, uint256 price, uint8 pdec) internal view returns (TokenData memory r) {
        if (price == 0) (price, pdec) = _getPrice(tkn);

        r.name = IERC20(tkn).name();
        r.symbol = _symbol(tkn);
        r.tSupply = IERC20(tkn).totalSupply();
        r.balance = acc != address(0) ? IERC20(tkn).balanceOf(acc) : 0;
        r.price = price;
        r.value = r.balance.toWad((r.decimals = IERC20(tkn).decimals())).wmul(price.toWad(pdec)).fromWad((r.oracleDec = 8));
    }

    function _vault() internal view returns (V memory r) {
        r.assets = _getVAssets();
        r.share.addr = addr.vault;
        r.share.price = vault.exchangeRate();
        r.share.symbol = vault.symbol();
        r.share.name = vault.name();
        r.share.tSupply = vault.totalSupply();
        r.share.decimals = vault.decimals();
        r.share.oracleDec = 18;
        r.share.chainId = block.chainid;
    }
}

struct TokenData {
    string name;
    string symbol;
    uint256 balance;
    uint256 value;
    uint256 price;
    uint256 tSupply;
    uint8 decimals;
    uint8 oracleDec;
}
