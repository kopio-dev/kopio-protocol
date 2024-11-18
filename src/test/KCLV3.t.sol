// solhint-disable state-visibility, max-states-count, no-empty-blocks, no-console
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "kopio/vm/Tested.t.sol";
import "scripts/tasks/Periphery.s.sol";
import {MockOracle} from "kopio/mocks/MockOracle.sol";

contract KCLV3 is Tested, Periphery {
    using Log for *;
    using ShortAssert for *;
    using Utils for *;

    address stETH_USD = 0x07C5b924399cc23c24a95c8743DE4006a32b7f2a;
    address ETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    address wstETH_ETH = 0xb523AE262D20A936BC152e6023996e46FDC2A95D;
    address wstETH_stETH = 0xB1552C5e96B312d0Bf8b554186F846C40614a540;
    address weETH_ETH = 0xE141425bc1594b8039De6390db1cDaf4397EA22b;
    address ezETH_ETH = 0x989a480b6054389075CBCdC385C18CfB6FC08186;

    uint8 decRatio;
    uint8 decPrice;

    function setUp() public {
        connect("MNEMONIC_KOPIO", "arbitrum", 256534015);

        deployCLV3(sender);

        decRatio = newKopioCLV3.RATIO_DEC();
        decPrice = newKopioCLV3.PRICE_DEC();

        _mocks();
    }

    function testUnderlyingPrice() public {
        newKopioCLV3.ETH_FEED().eq(ETH_USD, "eth-feed");

        uint256 priceA = newKopioCLV3.getAnswer().answer;
        uint256 priceB = newKopioCLV3.getAnswer(ETH_USD).answer;
        uint256 priceC = newKopioCLV3.getAnswer(stETH_USD).answer;

        priceA.eq(_getAnswer(ETH_USD), "price-eth-1");
        priceB.eq(_getAnswer(ETH_USD), "price-eth-2");

        priceC.eq(_getAnswer(stETH_USD), "price-steth-1");

        priceA.dlg("eth-1-$", newKopioCLV3.PRICE_DEC());
        priceB.dlg("eth-2-$", newKopioCLV3.PRICE_DEC());
        priceC.dlg("steth-1-$", newKopioCLV3.PRICE_DEC());
    }

    function testRatio() public {
        _testRatio(weETH_ETH);
        _testRatio(ezETH_ETH);

        _testRatio(wstETH_ETH);
        _testRatio(wstETH_stETH);
    }

    function _testRatio(address feed) internal {
        uint256 ratio = newKopioCLV3.getRatio(feed).answer;

        ratio.eq(_getAnswer(feed), "ratio");

        ratio.dlg("ratio", newKopioCLV3.RATIO_DEC());
    }

    function _getAnswer(address feed) internal view returns (uint256) {
        (, int256 answer, , , ) = IAggregatorV3(feed).latestRoundData();
        assert(answer > 0);
        return uint256(answer);
    }

    function testDerivedPrice() public {
        _testDerivedPrice(weETH_ETH);
        _testDerivedPrice(ezETH_ETH);

        _testDerivedPrice(wstETH_ETH);
        _testDerivedPrice(stETH_USD, wstETH_stETH);

        _testDerivedPrice([stETH_USD, ETH_USD], [wstETH_stETH, wstETH_ETH]);
    }

    function _testDerivedPrice(address priceFeed, address ratioFeed) internal {
        IKopioCLV3.Derived memory derivedPrice = newKopioCLV3.getDerivedAnswer(priceFeed, ratioFeed);

        derivedPrice.underlyingPrice.eq(_getAnswer(priceFeed), "underlying-price");
        derivedPrice.price.gt(derivedPrice.underlyingPrice, "derived-price");
        derivedPrice.age.eq(_getMinAge(_toArr(priceFeed, ratioFeed)), "age");

        _log(derivedPrice);
    }

    function _testDerivedPrice(address[2] memory priceFeeds, address[2] memory ratioFeeds) internal {
        IKopioCLV3.Derived memory derivedPrice = newKopioCLV3.getDerivedAnswer(priceFeeds, ratioFeeds);

        derivedPrice.underlyingPrice.eq((_getAnswer(priceFeeds[0]) + _getAnswer(priceFeeds[1])) / 2, "underlying-price");

        uint256 a = newKopioCLV3.getDerivedAnswer(priceFeeds[0], ratioFeeds[0]).price;
        uint256 b = newKopioCLV3.getDerivedAnswer(priceFeeds[1], ratioFeeds[1]).price;
        derivedPrice.price.eq((a + b) / 2, "price");

        derivedPrice.price.gt(derivedPrice.underlyingPrice, "derived-price");
        derivedPrice.age.eq(_getMinAge(_toArr([priceFeeds[0], priceFeeds[1], ratioFeeds[0], ratioFeeds[1]])), "age");

        _log(derivedPrice);
    }

    function _testDerivedPrice(address ratioFeed) internal {
        uint256 uprice = newKopioCLV3.getAnswer().answer;
        uint256 ratio = newKopioCLV3.getRatio(ratioFeed).answer;

        IKopioCLV3.Derived memory derivedPrice = newKopioCLV3.getDerivedAnswer(ratioFeed);

        derivedPrice.ratio.eq(ratio, "ratio");

        derivedPrice.underlyingPrice.eq(uprice, "underlying-price");
        derivedPrice.price.gt(derivedPrice.underlyingPrice, "derived-price");

        derivedPrice.age.eq(_getMinAge(_toArr(newKopioCLV3.ETH_FEED(), ratioFeed)), "age");

        _log(derivedPrice);
    }

    function testInvalidUnderlyingDecimals() public {
        mocks.feedA.setDecimals(decRatio);
        mocks.feedB.setDecimals(decRatio);

        vm.expectRevert(Err.dec(decRatio, decPrice));
        newKopioCLV3.getAnswer(address(mocks.feedA));
        vm.expectRevert(Err.dec(decRatio, decPrice));
        newKopioCLV3.getDerivedAnswer(address(mocks.feedA), address(mocks.feedB));
    }

    function testInvalidRatioDecimals() public {
        mocks.feedA.setDecimals(decPrice);
        mocks.feedB.setDecimals(decPrice);

        vm.expectRevert(Err.dec(decPrice, decRatio));
        newKopioCLV3.getRatio(address(mocks.feedB));
        vm.expectRevert(Err.dec(decPrice, decRatio));
        newKopioCLV3.getDerivedAnswer(address(mocks.feedA), address(mocks.feedB));
        vm.expectRevert(Err.dec(decPrice, decRatio));
        newKopioCLV3.getDerivedAnswer(address(mocks.feedB));
    }

    function testInvalidUnderlyingAnswer() public {
        mocks.feedA.setPrice(0);
        vm.expectRevert(Err.answer(0, 1));
        newKopioCLV3.getAnswer(address(mocks.feedA));

        mocks.feedA.setIntPrice(-1);
        vm.expectRevert(Err.answer(-1, 1));
        newKopioCLV3.getAnswer(address(mocks.feedA));
    }
    function testInvalidDerivedAnswer() public {
        mocks.feedB.setPrice(0);
        vm.expectRevert(Err.answer(0, 1));
        newKopioCLV3.getRatio(address(mocks.feedB));

        mocks.feedB.setIntPrice(-1);
        vm.expectRevert(Err.answer(-1, 1));
        newKopioCLV3.getRatio(address(mocks.feedB));

        mocks.feedA.setIntPrice(1000e8);
        mocks.feedB.setIntPrice(1e18);

        newKopioCLV3.getDerivedAnswer(address(mocks.feedA), address(mocks.feedB)).price.eq(1000e8, "p-1");

        mocks.feedB.setIntPrice(1e4);
        vm.expectRevert(Err.answer(1e4, newKopioCLV3.MIN_RATIO()));
        newKopioCLV3.getDerivedAnswer(address(mocks.feedA), address(mocks.feedB));

        mocks.feedB.setIntPrice(100_000_000 ether);
        vm.expectRevert(Err.answer(100_000_000 ether, newKopioCLV3.MAX_RATIO()));
        newKopioCLV3.getDerivedAnswer(address(mocks.feedA), address(mocks.feedB));
    }

    function _getMinAge(address[] memory feeds) internal view returns (uint256 result) {
        for (uint256 i; i < feeds.length; i++) {
            (, , , uint256 updatedAt, ) = IAggregatorV3(feeds[i]).latestRoundData();
            if (result == 0 || result > updatedAt) {
                result = updatedAt;
            }
        }

        return block.timestamp - result;
    }

    function _toArr(address a, address b) internal pure returns (address[] memory arr) {
        arr = new address[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function _toArr(address[4] memory a) internal pure returns (address[] memory arr) {
        arr = new address[](4);
        arr[0] = a[0];
        arr[1] = a[1];
        arr[2] = a[2];
        arr[3] = a[3];
    }

    function _log(KopioCLV3.Derived memory price) internal view {
        price.price.dlg("price", decPrice);
        price.ratio.dlg("ratio", decRatio);
        price.underlyingPrice.dlg("underlying-price", decPrice);
        price.age.clg("age");
    }

    function _mocks() internal {
        mocks.feedA = new MockOracle("A", 10000.toDec(0, decPrice), decPrice);
        mocks.feedB = new MockOracle("B", 1.25e2.toDec(2, decRatio), decRatio);
    }

    Mocks mocks;
}

struct Mocks {
    MockOracle feedA;
    MockOracle feedB;
}

library Err {
    function answer(int256 val, uint256 valid) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IKopioCLV3.InvalidAnswer.selector, val, valid);
    }

    function dec(uint8 a, uint8 b) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IKopioCLV3.InvalidDecimals.selector, a, b);
    }
}
