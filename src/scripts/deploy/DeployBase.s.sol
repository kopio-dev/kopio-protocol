// solhint-disable state-visibility
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.26;

import {IPyth} from "kopio/vendor/Pyth.sol";
import {FacetData, getFacets, create1} from "kopio/vm-ffi/ffi-facets.s.sol";
import {IProxyFactory} from "kopio/IProxyFactory.sol";
import {IWETH9Arb} from "kopio/token/IWETH9.sol";
import {Connected} from "kopio/vm/Connected.s.sol";

import {TickerConfig, Config} from "scripts/deploy/JSON.s.sol";
import {LibJSON} from "scripts/deploy/libs/LibJSON.s.sol";
import {InitializerMismatch, DiamondBomb} from "scripts/utils/DiamondBomb.sol";
import {LibDeploy} from "scripts/deploy/libs/LibDeploy.s.sol";

import {KopioCore} from "interfaces/KopioCore.sol";
import {IONE} from "interfaces/IONE.sol";
import {IVault} from "interfaces/IVault.sol";
import {IKopioMulticall} from "interfaces/IKopioMulticall.sol";

import {Diamond} from "diamond/Diamond.sol";
import {FacetCut, Initializer, FacetCutAction} from "diamond/Types.sol";
import {ICDPConfigFacet} from "facets/ICDPConfigFacet.sol";
import {CommonConfigFacet} from "facets/CommonConfigFacet.sol";
import {SCDPConfigFacet} from "facets/SCDPConfigFacet.sol";
import {ProxyFactory} from "kopio/ProxyFactory.sol";

interface Create2Factory {
    function safeCreate2(bytes32 salt, bytes calldata codes) external payable returns (address);
}

abstract contract DeployBase is Connected {
    using LibDeploy for bytes;
    using LibDeploy for bytes32;
    using LibDeploy for Config;
    string internal facetLoc = "./src/contracts/facets/*Facet.sol";

    uint256 private constant INITIALIZER_COUNT = 3;

    KopioCore protocol;
    IONE one;
    IVault vault;
    IProxyFactory factory;
    IKopioMulticall multicall;
    IPyth pythEp;
    IWETH9Arb weth;

    modifier saveOutput(string memory id) {
        LibDeploy.JSONKey(id);
        _;
        LibDeploy.saveJSONKey();
    }

    function deployFactory(address initialOwner, address create2Fac, bytes32 salt) internal saveOutput("Factory") returns (address addr, bytes32 initHash) {
        bytes memory ctor = abi.encode(initialOwner);
        bytes memory factoryInit = abi.encodePacked(type(ProxyFactory).creationCode, ctor);

        initHash = keccak256(factoryInit);
        addr = block.chainid == 31337 ? address(new ProxyFactory{salt: salt}(initialOwner)) : address(Create2Factory(create2Fac).safeCreate2(salt, factoryInit));
        LibDeploy.state().factory = (factory = IProxyFactory(addr));
        LibDeploy.setJsonAddr("address", addr);
        LibDeploy.setJsonBytes("ctor", ctor);
        LibDeploy.setJsonBytes("INIT_CODE_HASH", bytes.concat(initHash));
    }

    function deployDiamond(Config memory json, address deployer, bytes32 salt) internal saveOutput("Protocol") returns (address diamond, bytes32 initHash) {
        require(address(LibDeploy.state().factory) != address(0), "No factory");
        (FacetCut[] memory facets, Initializer[] memory initializers) = deployFacets(json);

        bytes memory initCode = type(Diamond).creationCode.ctor(abi.encode(deployer, facets, initializers));

        LibDeploy.setJsonBytes("INIT_CODE_HASH", bytes.concat(initHash = keccak256(initCode)));
        protocol = KopioCore(initCode.d3("", salt).implementation);
        return (address(protocol), initHash);
    }

    function deployFacets(Config memory json) private returns (FacetCut[] memory cuts, Initializer[] memory inits) {
        FacetData[] memory facets = getFacets(facetLoc);
        bytes4[][] memory selectors = new bytes4[][](facets.length);
        for (uint256 i; i < facets.length; i++) {
            selectors[i] = facets[i].selectors;
        }
        (uint256[] memory initIds, bytes[] memory initDatas) = getInitializers(json, selectors);

        if (initIds.length != initDatas.length) {
            revert InitializerMismatch(initIds.length, initDatas.length);
        }
        cuts = new FacetCut[](facets.length);
        inits = new Initializer[](initDatas.length);

        for (uint256 i; i < facets.length; ) {
            cuts[i].action = FacetCutAction.Add;
            cuts[i].facetAddress = create1(facets[i].facet);
            cuts[i].functionSelectors = facets[i].selectors;
            unchecked {
                i++;
            }
        }
        for (uint256 i; i < initDatas.length; ) {
            inits[i].initContract = cuts[initIds[i]].facetAddress;
            inits[i].initData = initDatas[i];
            unchecked {
                i++;
            }
        }
    }

    function getInitializers(Config memory json, bytes4[][] memory selectors) private pure returns (uint256[] memory initializers, bytes[] memory datas) {
        initializers = new uint256[](INITIALIZER_COUNT);
        datas = new bytes[](INITIALIZER_COUNT);
        bytes4[INITIALIZER_COUNT] memory initSelectors = [
            CommonConfigFacet.initializeCommon.selector,
            ICDPConfigFacet.initializeICDP.selector,
            SCDPConfigFacet.initializeSCDP.selector
        ];
        bytes[INITIALIZER_COUNT] memory initDatas = [
            abi.encodeWithSelector(initSelectors[0], json.params.common),
            abi.encodeWithSelector(initSelectors[1], json.params.icdp),
            abi.encodeWithSelector(initSelectors[2], json.params.scdp)
        ];

        for (uint256 i; i < selectors.length; i++) {
            for (uint256 j; j < selectors[i].length; j++) {
                for (uint256 k; k < initSelectors.length; k++) {
                    if (selectors[i][j] == initSelectors[k]) {
                        initializers[k] = i;
                        datas[k] = initDatas[k];
                    }
                }
            }
        }
        require(initializers[INITIALIZER_COUNT - 1] != 0, "getInitializers: No initializers");
    }

    function deployDiamondOneTx(Config memory json, address deployer) internal returns (KopioCore) {
        FacetData[] memory facetDatas = getFacets(facetLoc);

        bytes[] memory facets = new bytes[](facetDatas.length);
        bytes4[][] memory selectors = new bytes4[][](facetDatas.length);

        for (uint256 i; i < facetDatas.length; i++) {
            facets[i] = facetDatas[i].facet;
            selectors[i] = facetDatas[i].selectors;
        }

        (uint256[] memory initializers, bytes[] memory calldatas) = getInitializers(json, selectors);
        return (protocol = KopioCore(address(new DiamondBomb().create(deployer, facets, selectors, initializers, calldatas))));
    }

    function updatePythLocal(TickerConfig[] memory tickers) internal {
        getMockPayload(LibJSON.getMockPrices(tickers));
        updatePyth(pyth.update, 0);
    }
}
