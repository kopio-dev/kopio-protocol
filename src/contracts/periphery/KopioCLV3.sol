// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IAggregatorV3} from "kopio/vendor/IAggregatorV3.sol";
import {IKopioCLV3} from "kopio/IKopioCLV3.sol";
import {Utils} from "kopio/utils/Libs.sol";
import {OwnableUpgradeable} from "@oz-upgradeable/access/OwnableUpgradeable.sol";

contract KopioCLV3 is IKopioCLV3, OwnableUpgradeable {
    using Utils for uint256;

    address public constant ETH_FEED = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    uint256 public constant STALE_TIME = 86401;

    uint8 public constant PRICE_DEC = 8;
    uint8 public constant RATIO_DEC = 18;

    uint256 public constant PERCENT = (10 ** RATIO_DEC) / 100;

    uint256 public constant MIN_RATIO = 1 * PERCENT;
    uint256 public constant MAX_RATIO = 100_000_000 * PERCENT;

    bool public decimalConversions;

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __Ownable_init(owner);
    }

    function setDecimalConversions(bool enabled) external onlyOwner {
        decimalConversions = enabled;
    }

    function getAnswer() external view returns (Answer memory) {
        return getAnswer(ETH_FEED);
    }

    function getAnswer(address priceFeed) public view returns (Answer memory) {
        return _getAnswer(priceFeed, PRICE_DEC);
    }

    function getAnswer(address priceFeed, uint8 expectedDec) public view returns (Answer memory) {
        return _getAnswer(priceFeed, expectedDec);
    }

    function getDerivedAnswer(address ratioFeed) external view returns (Derived memory) {
        return getDerivedAnswer(ETH_FEED, ratioFeed);
    }

    function getDerivedAnswer(address priceFeed, address ratioFeed) public view returns (Derived memory) {
        return getDerivedAnswer(priceFeed, ratioFeed, PRICE_DEC, RATIO_DEC);
    }

    function getDerivedAnswer(
        address priceFeed,
        address ratioFeed,
        uint8 priceDec,
        uint8 ratioDec
    ) public view returns (Derived memory result) {
        Answer memory underlyingPrice = _getAnswer(priceFeed, priceDec);
        Answer memory ratio = getRatio(ratioFeed, ratioDec);

        result.underlyingPrice = underlyingPrice.answer;
        result.ratio = ratio.answer;

        result.price = result.underlyingPrice.wmul(result.ratio);
        result.age = _max(underlyingPrice.age, ratio.age);
    }

    function getDerivedAnswer(
        address[2] calldata priceFeeds,
        address[2] calldata ratioFeeds
    ) external view returns (Derived memory result) {
        Derived memory d1 = getDerivedAnswer(priceFeeds[0], ratioFeeds[0]);
        Derived memory d2 = getDerivedAnswer(priceFeeds[1], ratioFeeds[1]);

        result.underlyingPrice = _avg(d1.underlyingPrice, d2.underlyingPrice);
        result.ratio = _avg(d1.ratio, d2.ratio);

        result.price = _avg(d1.price, d2.price);
        result.age = _max(d1.age, d2.age);
    }

    function getRatio(address ratioFeed) public view returns (Answer memory) {
        return getRatio(ratioFeed, RATIO_DEC);
    }

    function getRatio(address ratioFeed, uint8 ratioDec) public view returns (Answer memory answer) {
        answer = _getAnswer(ratioFeed, ratioDec);
        require(answer.answer > MIN_RATIO, InvalidAnswer(int256(answer.answer), MIN_RATIO));
        require(answer.answer < MAX_RATIO, InvalidAnswer(int256(answer.answer), MAX_RATIO));
    }

    function _getAnswer(address feed, uint8 expectedDec) internal view returns (Answer memory) {
        return _getAnswer(IAggregatorV3(feed), expectedDec);
    }

    function _getAnswer(IAggregatorV3 feed, uint8 expectedDec) internal view returns (Answer memory) {
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();

        uint256 age = block.timestamp - updatedAt;
        require(age < STALE_TIME, StalePrice(age, updatedAt));

        return Answer({answer: _handleAnswer(answer, feed.decimals(), expectedDec), updatedAt: updatedAt, age: age});
    }

    function _handleAnswer(int256 answer, uint8 feedDec, uint8 expectedDec) internal view returns (uint256 result) {
        require(answer > 0, InvalidAnswer(answer, 1));

        result = uint256(answer);
        if (feedDec == expectedDec) return result;

        if (!decimalConversions) revert InvalidDecimals(feedDec, expectedDec);
        return result.toDec(feedDec, expectedDec);
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function _avg(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b) / 2;
    }
}
