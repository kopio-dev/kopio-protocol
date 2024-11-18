// solhint-disable state-visibility, max-states-count, no-empty-blocks, no-console
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Deployed} from "scripts/deploy/libs/Deployed.s.sol";
import {Deploy} from "scripts/deploy/Deploy.s.sol";
import {Log} from "kopio/vm/VmLibs.s.sol";
import {Tested} from "kopio/vm/Tested.t.sol";
import {IAccess} from "kopio/vendor/IAccess.sol";
import {Role} from "common/Constants.sol";
import {Kopio} from "asset/Kopio.sol";
import {IDiamondCutFacet, IExtendedDiamondCutFacet} from "interfaces/IDiamondCutFacet.sol";
import {FacetCut, Initializer} from "diamond/Types.sol";
import {CommonConfigFacet} from "facets/CommonConfigFacet.sol";
import {CommonInitializer} from "common/Types.sol";
import {ICDPInitializer} from "icdp/Types.sol";
import {ICDPConfigFacet} from "facets/ICDPConfigFacet.sol";
import {SCDPInitializer} from "scdp/Types.sol";
import {SCDPConfigFacet} from "facets/SCDPConfigFacet.sol";
import {ProxyFactory} from "kopio/ProxyFactory.sol";

contract InitializerTest {
    function initialize() public {
        // do nothing
    }
}

contract MetaTest is Tested, Deploy {
    using Log for *;
    using Deployed for *;

    address payable kETH;
    address admin;

    Kopio kETHAsset;

    function setUp() public {
        admin = Deploy.deployTest("MNEMONIC_KOPIO", "test-clean", 0).params.common.admin;
        kETH = payable(("kETH").addr());
        kETHAsset = Kopio(kETH);
    }

    function testFuzzAccessControl(address user) public {
        vm.assume(user != admin && user != address(0));
        prank(user);

        vm.deal(user, 1 ether);

        vm.expectRevert();
        IAccess(address(protocol)).transferOwnership(user);

        vm.expectRevert();
        IAccess(address(protocol)).acceptOwnership();

        vm.expectRevert();
        IDiamondCutFacet(address(protocol)).diamondCut(new FacetCut[](0), address(0), new bytes(0));

        Initializer[] memory initializers = new Initializer[](1);
        initializers[0] = Initializer(address(new InitializerTest()), "");

        vm.expectRevert();
        IExtendedDiamondCutFacet(address(protocol)).executeInitializers(initializers);

        vm.expectRevert();
        IExtendedDiamondCutFacet(address(protocol)).executeInitializer(initializers[0].initContract, initializers[0].initData);

        vm.expectRevert();
        IAccess(address(protocol)).grantRole(Role.DEFAULT_ADMIN, user);

        vm.expectRevert();
        IAccess(address(protocol)).revokeRole(Role.DEFAULT_ADMIN, admin);

        vm.expectRevert();
        vault.setGovernance(user);

        vm.expectRevert();
        vault.acceptGovernance();

        vm.expectRevert();
        kETHAsset.grantRole(Role.DEFAULT_ADMIN, user);

        vm.expectRevert();
        kETHAsset.revokeRole(Role.DEFAULT_ADMIN, admin);

        CommonInitializer memory args;

        vm.expectRevert();
        CommonConfigFacet(address(protocol)).initializeCommon(args);

        ICDPInitializer memory icdpInit;

        vm.expectRevert();
        ICDPConfigFacet(address(protocol)).initializeICDP(icdpInit);

        SCDPInitializer memory scdpInit;

        vm.expectRevert();
        SCDPConfigFacet(address(protocol)).initializeSCDP(scdpInit);

        vm.expectRevert();
        CommonConfigFacet(address(protocol)).setFeeRecipient(user);

        vm.expectRevert();
        factory.setDeployer(user, true);

        vm.expectRevert();
        ProxyFactory(address(factory)).transferOwnership(user);
    }
}
