// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "scripts/tasks/Core.s.sol";
import "test/helpers/CoreTest.t.sol";
import {StdStorage, stdStorage} from "forge-std/StdStorage.sol";

contract TestUpgrades is ArbCoreTest, Core {
    using Utils for *;
    using Log for *;
    using ShortAssert for *;
    using stdStorage for StdStorage;

    uint256 exchangeRateBefore;
    uint256 oneSupplyBefore;
    uint256 oneBalanceBefore;
    address constant kcvl3Addr = 0x333333333331Bb94E66b5aB3acfa0D30936C028A;
    address constant pythEp = 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C;
    address constant pythForwarder = 0xfeEFeEfeED0bd9Df8d23dC0242FEF943c574468f;

    uint256 priceEthA;
    uint256 priceOneA;
    uint256 priceEthB;
    uint256 priceOneB;

    function setUp() public override {
        connect(275865509);

        (priceEthA, priceOneA) = (core.getPrice(kETHAddr), core.getPrice(oneAddr));

        exchangeRateBefore = vault.exchangeRate();
        oneSupplyBefore = one.totalSupply();
        oneBalanceBefore = one.balanceOf(user0);
        super.execUpgrade();
        setupCoreTest();
    }

    function testDealONE() external {
        dealONE(usdceAddr, user0, 10_000 ether);

        (one.balanceOf(user0) - oneBalanceBefore).eq(10_000 ether, "invalid-one-balance");
        one.totalSupply().eq(oneSupplyBefore + 10_000 ether, "invalid-one-supply");
    }

    function testAfterUpgrade() public {
        vault.exchangeRate().eq(exchangeRateBefore, "vault-exchange-rate");
        (priceEthB, priceOneB) = (core.getPrice(kETHAddr), core.getPrice(oneAddr));
        priceEthA.eq(priceEthB, "price-eth");
        priceOneA.eq(priceOneB, "price-one");
    }

    function testUpgradedConfig() public {
        address(vault.kopioCLV3()).eq(kcvl3Addr, "vault-kclv3");
        core.getKCLV3().eq(kcvl3Addr, "core-kclv3");
        core.getPythEndpoint().eq(0xff1a0f4744e8582DF1aE09D5611b887B6a12925C, "core-pyth");
    }
}
