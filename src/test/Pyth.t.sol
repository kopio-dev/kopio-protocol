// solhint-disable state-visibility, max-states-count, no-empty-blocks, no-console
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {PLog} from "kopio/vm/PLog.s.sol";
import {ShortAssert} from "kopio/vm/ShortAssert.t.sol";
import {Tested} from "kopio/vm/Tested.t.sol";
import {IPyth, PythView, Price} from "kopio/vendor/Pyth.sol";
import {Prices} from "libs/Prices.sol";
import {createMockPyth} from "kopio/mocks/MockPyth.sol";

contract PythTest is Tested {
    bytes32 constant PYTH_ETH = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;

    using PLog for *;
    using ShortAssert for *;

    IPyth mockPyth;

    uint8 oracleDec = 8;
    bytes32[] ids;
    Price[] prices;

    function setUp() public {
        useMnemonic("MNEMONIC_KOPIO");

        prices.push(Price({price: 2000e8, conf: 0, expo: -8, publishTime: 0}));
        ids.push(PYTH_ETH);

        mockPyth = createMockPyth(PythView(ids, prices));
    }

    function testInvertPythPrice() public {
        uint256 price = Prices.getPythAnswer(Price(147023, 23, -3, 1706735592), oracleDec, true);
        price.eq(680165, "usdJpy.price");
    }

    function testNormalizeOver8Dec() public {
        uint256 normalizedPrice = Prices.getPythAnswer(Price({price: 2000e9, conf: 0, expo: -9, publishTime: 0}), oracleDec, false);
        normalizedPrice.eq(2000e8, "normalizedPrice");
    }

    function testNormalizeUnder8Dec() public {
        uint256 normalizedPrice = Prices.getPythAnswer(Price({price: 2000e5, conf: 0, expo: -5, publishTime: 0}), oracleDec, false);
        normalizedPrice.eq(2000e8, "normalizedPrice");
    }

    function testNormalize8Dec() public {
        uint256 normalizedPrice = Prices.getPythAnswer(Price({price: 2000e8, conf: 0, expo: -8, publishTime: 0}), oracleDec, false);
        normalizedPrice.eq(2000e8, "normalizedPrice");
    }
}
