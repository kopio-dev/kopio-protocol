// // SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {KopioCore} from "interfaces/KopioCore.sol";
import {Log} from "kopio/vm/VmLibs.s.sol";

import {IKopioMulticall} from "interfaces/IKopioMulticall.sol";
import {IERC20} from "kopio/token/IERC20.sol";
import {Asset, Oracle, PythConfig} from "common/Types.sol";
import {ArbDeploy} from "kopio/info/ArbDeploy.sol";
import {TData} from "periphery/data/DataTypes.sol";
import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {Enums} from "common/Constants.sol";
import {Connected} from "kopio/vm/Connected.s.sol";

// solhint-disable state-visibility, max-states-count, var-name-mixedcase, no-global-import, const-name-snakecase, no-empty-blocks, no-console

contract ArbScript is Connected, ArbDeploy {
    using Log for *;

    IKopioMulticall multicall = IKopioMulticall(multicallAddr);
    KopioCore protocol = KopioCore(address(0));
    constructor() {
        Deployed.factory(factoryAddr);
    }

    function initialize(string memory mnemonic) internal {
        connect(mnemonic, "arbitrum");
    }

    function initialize(uint256 blockNr) internal {
        connect("arbitrum", blockNr);
        states_looseOracles();
    }

    function approvals(address spender) internal {
        uint256 allowance = type(uint256).max;
        usdc.approve(spender, allowance);
        usdce.approve(spender, allowance);
        wbtc.approve(spender, allowance);
        weth.approve(spender, allowance);
        kETH.approve(spender, allowance);
        kBTC.approve(spender, allowance);
        kJPY.approve(spender, allowance);
        kEUR.approve(spender, allowance);
        kSOL.approve(spender, allowance);
        skETH.approve(spender, allowance);
        arb.approve(spender, allowance);
        one.approve(spender, allowance);
        IERC20(vaultAddr).approve(spender, allowance);
    }

    function approvals() internal {
        approvals(multicallAddr);
        approvals(routerv3Addr);
        approvals(address(0));
        approvals(oneAddr);
        approvals(vaultAddr);
    }

    function getUSDC(address to, uint256 amount) internal returns (uint256) {
        return getBal(usdcAddr, to, amount);
    }

    function getUSDCe(address to, uint256 amount) internal returns (uint256) {
        return getBal(usdceAddr, to, amount);
    }

    function getBal(address token, address to, uint256 amount) internal rebroadcasted(binanceAddr) returns (uint256) {
        IERC20(token).transfer(to, amount);
        return amount;
    }

    function getONED(address to, uint256 amount) internal returns (uint256 shares, uint256 assets, uint256 fees) {
        approvals(oneAddr);
        (assets, fees) = vault.previewMint(usdceAddr, amount);
        one.vaultDeposit(usdceAddr, getUSDCe(to, assets), to);
        return (amount, assets, fees);
    }

    function getONEM(address to, uint256 amount) internal returns (uint256 shares, uint256 assets, uint256 fees) {
        approvals(oneAddr);
        (assets, fees) = vault.previewMint(usdceAddr, amount);
        getUSDCe(to, assets);
        one.vaultMint(usdceAddr, amount, to);
        return (amount, assets, fees);
    }

    function states_noVaultFees() internal rebroadcasted(safe) {
        if (vault.getConfig().pendingGovernance != address(0)) vault.acceptGovernance();
        vault.setAssetFees(usdceAddr, 0, 0);
        vault.setAssetFees(usdcAddr, 0, 0);
    }

    function states_looseOracles() public rebroadcasted(safe) {
        vault.setAssetFeed(usdcAddr, 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, type(uint24).max);
        vault.setAssetFeed(usdceAddr, 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3, type(uint24).max);
        protocol.setOracleDeviation(25e2);

        TData.TAsset[] memory assets = protocol.aDataProtocol(pyth.viewData).assets;

        for (uint256 i; i < assets.length; i++) {
            Asset memory asset = assets[i].config;

            if (asset.oracles[0] == Enums.OracleType.Pyth) {
                Oracle memory primaryOracle = protocol.getOracleOfTicker(asset.ticker, asset.oracles[0]);
                protocol.setPythFeed(asset.ticker, PythConfig(primaryOracle.pythId, 1000000, primaryOracle.invertPyth, primaryOracle.isClosable));
            }
            if (asset.oracles[1] == Enums.OracleType.Chainlink) {
                Oracle memory secondaryOracle = protocol.getOracleOfTicker(asset.ticker, asset.oracles[1]);
                protocol.setChainLinkFeed(asset.ticker, secondaryOracle.feed, 1000000, secondaryOracle.isClosable);
            }
        }
    }

    function states_noFactorsNoFees() internal rebroadcasted(safe) {
        TData.TAsset[] memory assets = protocol.aDataProtocol(pyth.viewData).assets;
        for (uint256 i; i < assets.length; i++) {
            TData.TAsset memory asset = assets[i];
            if (asset.config.factor > 0) {
                asset.config.factor = 1e4;
            }
            if (asset.config.dFactor > 0) {
                asset.config.dFactor = 1e4;
                asset.config.swapInFee = 0;
                asset.config.swapOutFee = 0;
                asset.config.protocolFeeShareSCDP = 0;
                asset.config.closeFee = 0;
                asset.config.openFee = 0;
                if (asset.config.ticker != bytes32("ONE")) {
                    (bool success, ) = asset.addr.call(abi.encodeWithSelector(0x15360fb9, 0));
                    (success, ) = asset.addr.call(abi.encodeWithSelector(0xe8e5c3f3, 0));
                    success;
                }
            }

            protocol.updateAsset(asset.addr, asset.config);
        }

        states_noVaultFees();
    }
}
