// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {Deployment} from "kopio/ProxyFactory.sol";
import {LibDeploy} from "scripts/deploy/libs/LibDeploy.s.sol";
import {JSON, LibJSON} from "scripts/deploy/libs/LibJSON.s.sol";
import {WETH9} from "kopio/token/WETH9.sol";
import {LibSafe} from "kopio/mocks/MockSafe.sol";
import {IWETH9Arb} from "kopio/token/IWETH9.sol";
import {MockSequencerUptimeFeed, ERC20Mock, MockOracle} from "mocks/Mocks.sol";
import {VmHelp, mvm, Utils} from "kopio/vm/VmLibs.s.sol";
import {MockMarketStatus, MockPyth} from "mocks/Mocks.sol";
import {KopioCLV3} from "periphery/KopioCLV3.sol";
library LibMocks {
    using VmHelp for *;
    using Utils for *;
    using LibDeploy for bytes;
    using LibDeploy for bytes32;
    using LibDeploy for JSON.Config;
    using LibJSON for *;
    bytes32 internal constant MOCKS_SLOT = keccak256("deploy.mocks.slot");

    bytes32 internal constant SEQ_FEED_SALT = bytes32("SEQ_FEED");
    modifier saveOutput(string memory id) {
        LibDeploy.JSONKey(id);
        _;
        LibDeploy.saveJSONKey();
    }

    /// @notice map tickers/symbols to deployed addresses
    struct MockState {
        address seqFeed;
        address mockSafe;
        mapping(string => ERC20Mock) tokens;
        mapping(string => MockOracle) feed;
        mapping(bytes32 => Deployment) deployment;
    }

    function state() internal pure returns (MockState storage s) {
        bytes32 slot = MOCKS_SLOT;
        assembly {
            s.slot := slot
        }
    }
    function createMockMarketStatusProvider(JSON.Config memory) internal saveOutput("MockMarketStatus") returns (address) {
        return type(MockMarketStatus).creationCode.d3("", "mockstatus").implementation;
    }

    function createMockPythEP(JSON.Config memory json) internal saveOutput("MockPythEP") returns (address) {
        bytes[] memory args = new bytes[](1);
        args[0] = abi.encode(json.assets.tickers.getMockPrices());
        bytes memory implementation = type(MockPyth).creationCode.ctor(abi.encode(args));
        return implementation.d3("", "pythmock").implementation;
    }

    function createMockKCLV3(address owner) internal saveOutput("MockKCLV3") returns (address) {
        return address(type(KopioCLV3).creationCode.p3(abi.encodeCall(KopioCLV3.initialize, (owner)), "mockclv3").proxy);
    }

    function createMocks(JSON.Config memory json, address deployer) internal returns (JSON.Config memory) {
        if (json.assets.wNative.mocked) {
            LibDeploy.JSONKey("wNative");
            address wNative = LibDeploy.d3(type(WETH9).creationCode, "", json.assets.wNative.symbol.mockTokenSalt()).implementation;
            json.assets.wNative.token = IWETH9Arb(wNative);
            LibDeploy.saveJSONKey();
        }

        if (json.params.common.sequencerUptimeFeed == address(0)) {
            json.params.common.sequencerUptimeFeed = address(deploySeqFeed());
            mvm.warp(mvm.unixTime() / 1000);
        }

        if (json.params.common.marketStatusProvider == address(0)) {
            json.params.common.marketStatusProvider = createMockMarketStatusProvider(json);
        }

        if (json.params.common.council == address(0)) {
            json.params.common.council = deployMockSafe(deployer);
        }

        if (json.params.common.kopioCLV3 == address(0)) {
            json.params.common.kopioCLV3 = createMockKCLV3(deployer);
        }

        for (uint256 i; i < json.assets.extAssets.length; i++) {
            JSON.ExtAsset memory ext = json.assets.extAssets[i];
            if (ext.addr == address(json.assets.wNative.token) || ext.symbol.equals(json.assets.wNative.symbol)) {
                json.assets.extAssets[i].addr = address(json.assets.wNative.token);
                json.assets.extAssets[i].symbol = json.assets.wNative.symbol;
                continue;
            }
            if (!ext.mocked) continue;

            json.assets.extAssets[i].addr = address(deployMockToken(ext.name, ext.symbol, ext.config.decimals, 0));
        }

        if (json.assets.mockFeeds) {
            for (uint256 i; i < json.assets.tickers.length; i++) {
                JSON.TickerConfig memory ticker = json.assets.tickers[i];
                if (ticker.ticker.equals("ONE")) continue;
                json.assets.tickers[i].chainlink = address(deployMockOracle(ticker.ticker, ticker.mockPrice, ticker.priceDecimals));
            }
        }

        if (json.params.common.pythEp == address(0)) {
            json.params.common.pythEp = createMockPythEP(json);
        }
        return json;
    }

    function deployMockOracle(string memory ticker, uint256 price, uint8 decimals) internal returns (MockOracle) {
        LibDeploy.JSONKey(LibJSON.feedStringId(ticker));
        bytes memory implementation = type(MockOracle).creationCode.ctor(abi.encode(ticker, price, decimals));
        Deployment memory deployment = implementation.d3("", LibJSON.feedBytesId(ticker));
        MockOracle result = MockOracle(deployment.implementation);
        LibDeploy.saveJSONKey();
        return result;
    }

    function deployMockToken(string memory name, string memory symbol, uint8 dec, uint256 supply) internal returns (ERC20Mock) {
        LibDeploy.JSONKey(symbol);

        ERC20Mock result = ERC20Mock(type(ERC20Mock).creationCode.ctor(abi.encode(name, symbol, dec, supply)).d3("", symbol.mockTokenSalt()).implementation);
        LibDeploy.saveJSONKey();
        return result;
    }

    function deploySeqFeed() internal returns (MockSequencerUptimeFeed result) {
        LibDeploy.JSONKey("SeqFeed");
        result = MockSequencerUptimeFeed(type(MockSequencerUptimeFeed).creationCode.d3("", SEQ_FEED_SALT).implementation);
        result.setAnswers(0, 1699456910, 1699456910);
        LibDeploy.saveJSONKey();
    }

    function deployMockSafe(address admin) internal returns (address result) {
        LibDeploy.JSONKey("council");
        result = address(LibSafe.createSafe(admin));
        LibDeploy.setJsonAddr("address", result);
        LibDeploy.saveJSONKey();
    }
}
