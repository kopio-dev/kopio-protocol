// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {Convert, Deployment, Proxies, ProxyFactory, TransparentUpgradeableProxy} from "kopio/ProxyFactory.sol";
import {ShortAssert} from "kopio/vm/ShortAssert.t.sol";
import {Tested} from "kopio/vm/Tested.t.sol";
import {LogicA, LogicB} from "mocks/MockLogic.sol";
import {Kopio} from "asset/Kopio.sol";
import {KopioShare} from "asset/KopioShare.sol";
import {Ownable} from "@oz/access/Ownable.sol";
import {PLog} from "kopio/vm/PLog.s.sol";

// solhint-disable

bytes32 constant EIP1967_ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
bytes32 constant EIP1967_IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

contract DeployerTest is Tested {
    using stdStorage for StdStorage;
    using ShortAssert for *;
    using PLog for *;
    using Proxies for *;
    using Convert for *;

    ProxyFactory deployer;
    address initialOwner;

    bytes32 salt = keccak256("test");
    bytes32 salt2 = keccak256("test2");

    bytes PROXY_CREATION_CODE = type(TransparentUpgradeableProxy).creationCode;

    bytes LOGIC_A_CREATION_CODE = type(LogicA).creationCode;
    bytes LOGIC_B_CREATION_CODE = type(LogicB).creationCode;

    bytes CALLDATA_LOGIC_A;
    bytes CALLDATA_LOGIC_B;

    function setUp() public mnemonic("MNEMONIC_KOPIO") {
        initialOwner = getAddr(0);
        deployer = new ProxyFactory(initialOwner);

        CALLDATA_LOGIC_A = abi.encodeWithSelector(LogicA.initialize.selector);
        CALLDATA_LOGIC_B = abi.encodeWithSelector(LogicB.initialize.selector, getAddr(1), 100);
    }

    function testSetup() public {
        deployer.owner().eq(initialOwner);
    }

    function testCreateProxy() public prankedById(0) {
        LogicA logicA = new LogicA();
        Deployment memory proxy = deployer.createProxy(address(logicA), CALLDATA_LOGIC_A);
        address proxyAddr = address(proxy.proxy);

        address admin = address(uint160(uint256(vm.load(proxyAddr, EIP1967_ADMIN_SLOT))));
        admin.eq(address(deployer));

        proxyAddr.notEq(address(0));
        proxy.implementation.eq(address(logicA));
        proxy.createdAt.notEq(0);
        proxy.updatedAt.eq(proxy.createdAt);
        proxy.salt.eq(bytes32(0));
        proxy.version.eq(1);

        logicA.valueUint().eq(0);
        logicA.owner().eq(address(0));

        LogicA proxyLogicA = LogicA(proxyAddr);
        proxyLogicA.valueUint().eq(42);
        proxyLogicA.owner().eq(address(deployer));

        deployer.isProxy(address(logicA)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicA));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testCreate2Proxy() public prankedById(0) {
        LogicA logicA = new LogicA();

        address expectedProxyAddress = deployer.previewCreate2Proxy(address(logicA), CALLDATA_LOGIC_A, salt);
        expectedProxyAddress.notEq(address(0));

        Deployment memory proxy = deployer.create2Proxy(address(logicA), CALLDATA_LOGIC_A, salt);
        address proxyAddr = address(proxy.proxy);

        address admin = address(uint160(uint256(vm.load(proxyAddr, EIP1967_ADMIN_SLOT))));
        admin.eq(address(deployer));

        proxyAddr.notEq(address(0));
        proxyAddr.eq(expectedProxyAddress);
        proxy.implementation.eq(address(logicA));
        proxy.createdAt.notEq(0);
        proxy.updatedAt.eq(proxy.createdAt);
        proxy.salt.eq(salt);
        proxy.version.eq(1);

        logicA.valueUint().eq(0);
        logicA.owner().eq(address(0));

        LogicA proxyLogicA = LogicA(proxyAddr);
        proxyLogicA.valueUint().eq(42);
        proxyLogicA.owner().eq(address(deployer));

        // Bookeeping
        deployer.isProxy(address(logicA)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicA));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testCreate3Proxy() public prankedById(0) {
        LogicA logicA = new LogicA();

        address expectedSaltAddress = deployer.getCreate3Address(salt);
        address expectedProxyAddress = deployer.previewCreate3Proxy(salt);

        expectedSaltAddress.notEq(address(0));
        expectedProxyAddress.eq(expectedSaltAddress);

        Deployment memory proxy = deployer.create3Proxy(address(logicA), CALLDATA_LOGIC_A, salt);
        address proxyAddr = address(proxy.proxy);

        address admin = address(uint160(uint256(vm.load(proxyAddr, EIP1967_ADMIN_SLOT))));
        admin.eq(address(deployer));

        proxyAddr.notEq(address(0));
        proxyAddr.eq(expectedProxyAddress);
        proxy.implementation.eq(address(logicA));
        proxy.createdAt.notEq(0);
        proxy.updatedAt.eq(proxy.createdAt);
        proxy.salt.eq(salt);
        proxy.version.eq(1);

        logicA.valueUint().eq(0);
        logicA.owner().eq(address(0));

        LogicA proxyLogicA = LogicA(proxyAddr);
        proxyLogicA.valueUint().eq(42);
        /// @notice kopio: CREATE3 msg.sender is minimal deployer proxy
        proxyLogicA.owner().notEq(address(deployer));

        // Bookeeping
        deployer.isProxy(address(logicA)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicA));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testCreateProxyAndLogic() public prankedById(0) {
        Deployment memory proxy = deployer.createProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A);
        address proxyAddr = address(proxy.proxy);

        address admin = address(uint160(uint256(vm.load(proxyAddr, EIP1967_ADMIN_SLOT))));

        admin.eq(address(deployer));

        proxyAddr.notEq(address(0));

        proxy.implementation.notEq(address(0));
        proxy.createdAt.notEq(0);
        proxy.updatedAt.eq(proxy.createdAt);
        proxy.salt.eq(bytes32(0));
        proxy.version.eq(1);

        LogicA logicA = LogicA(proxy.implementation);
        logicA.valueUint().eq(0);
        logicA.owner().eq(address(0));

        LogicA proxyLogicA = LogicA(proxyAddr);
        proxyLogicA.valueUint().eq(42);
        proxyLogicA.owner().eq(address(deployer));

        deployer.isProxy(address(logicA)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicA));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testCreateProxy2AndLogic() public prankedById(0) {
        bytes32 implementationSalt = salt.add(1);

        (address expectedProxy, address expectedImplementation) = deployer.previewCreate2ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt);
        expectedProxy.notEq(address(0));
        expectedImplementation.notEq(address(0));
        expectedProxy.notEq(expectedImplementation);

        Deployment memory proxy = deployer.create2ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt);
        address proxyAddr = address(proxy.proxy);

        address admin = address(uint160(uint256(vm.load(proxyAddr, EIP1967_ADMIN_SLOT))));
        admin.eq(address(deployer));

        proxyAddr.eq(expectedProxy);
        proxyAddr.eq(
            deployer.getCreate2Address(implementationSalt.sub(1), abi.encodePacked(PROXY_CREATION_CODE, abi.encode(expectedImplementation, address(deployer), CALLDATA_LOGIC_A))),
            "proxySaltReversed"
        );

        proxy.implementation.eq(expectedImplementation);
        proxy.implementation.eq(deployer.getCreate2Address(implementationSalt, LOGIC_A_CREATION_CODE), "implementationSalt");
        proxy.createdAt.notEq(0);
        proxy.updatedAt.eq(proxy.createdAt);
        proxy.salt.eq(salt);
        proxy.version.eq(1);

        LogicA logicA = LogicA(proxy.implementation);
        logicA.valueUint().eq(0);
        logicA.owner().eq(address(0));

        LogicA proxyLogicA = LogicA(proxyAddr);
        proxyLogicA.valueUint().eq(42);
        proxyLogicA.owner().eq(address(deployer));

        // Bookeeping
        deployer.isProxy(address(logicA)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicA));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testCreate3ProxyAndLogic() public prankedById(0) {
        bytes32 implementationSalt = bytes32(uint256(salt) + 1);

        (address expectedProxy, address expectedImplementation) = deployer.previewCreate3ProxyAndLogic(salt);
        expectedProxy.notEq(address(0));
        expectedImplementation.notEq(address(0));
        expectedProxy.notEq(expectedImplementation);

        Deployment memory proxy = deployer.create3ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt);
        address proxyAddr = address(proxy.proxy);

        address admin = address(uint160(uint256(vm.load(proxyAddr, EIP1967_ADMIN_SLOT))));
        admin.eq(address(deployer));

        proxyAddr.eq(expectedProxy);
        proxyAddr.eq(deployer.getCreate3Address(bytes32(uint256(implementationSalt) - 1)), "proxySaltReversed");
        proxy.implementation.eq(expectedImplementation);
        proxy.implementation.eq(deployer.getCreate3Address(implementationSalt), "implementationSalt");
        proxy.createdAt.notEq(0);
        proxy.updatedAt.eq(proxy.createdAt);
        proxy.salt.eq(salt);
        proxy.version.eq(1);

        LogicA logicA = LogicA(proxy.implementation);
        logicA.valueUint().eq(0);
        logicA.owner().eq(address(0));

        LogicA proxyLogicA = LogicA(proxyAddr);
        proxyLogicA.valueUint().eq(42);
        /// @notice kopio: CREATE3 msg.sender is its temporary utility contract.
        proxyLogicA.owner().notEq(address(deployer));

        // Bookeeping
        deployer.isProxy(address(logicA)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicA));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testUpgradeAndCall() public prankedById(0) {
        Deployment memory proxy = deployer.createProxy(address(new LogicA()), abi.encodeWithSelector(LogicA.initialize.selector));

        LogicB logicB = new LogicB();
        LogicB proxyLogicB = LogicB(address(proxy.proxy));

        address newOwner = getAddr(1);
        uint256 newValue = 100;

        vm.warp(100);
        deployer.upgradeAndCall(proxy.proxy, address(logicB), abi.encodeWithSelector(LogicB.initialize.selector, newOwner, newValue));
        logicB.owner().eq(address(0));
        logicB.valueUint().eq(0);

        proxyLogicB.owner().eq(newOwner);
        proxyLogicB.valueUint().eq(newValue);

        Deployment memory upgraded = deployer.getDeployment(address(proxy.proxy));
        address proxyAddr = address(upgraded.proxy);
        upgraded.implementation.notEq(proxy.implementation);
        upgraded.version.eq(2);
        upgraded.createdAt.eq(proxy.createdAt);
        upgraded.updatedAt.notEq(proxy.updatedAt);
        upgraded.index.eq(0);
        upgraded.salt.eq(0);
        assertTrue(proxy.proxy == upgraded.proxy);

        // Bookeeping
        deployer.isProxy(address(logicB)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicB));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testCreate2UpgradeAndCall() public prankedById(0) {
        Deployment memory proxy = deployer.create2ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt);
        address newOwner = getAddr(1);
        uint256 newValue = 100;
        bytes memory _calldata = abi.encodeWithSelector(LogicB.initialize.selector, newOwner, newValue);

        (address expectedImplementation, uint256 version) = deployer.previewCreate2Upgrade(proxy.proxy, LOGIC_B_CREATION_CODE);
        proxy.implementation.notEq(expectedImplementation);
        LogicB proxyLogicB = LogicB(address(proxy.proxy));

        vm.warp(100);
        Deployment memory upgraded = deployer.create2UpgradeAndCall(proxy.proxy, LOGIC_B_CREATION_CODE, _calldata);
        LogicB logicB = LogicB(expectedImplementation);

        address proxyAddr = address(upgraded.proxy);
        proxyAddr.eq(
            deployer.getCreate2Address(
                upgraded.salt.add(version).sub(version),
                abi.encodePacked(PROXY_CREATION_CODE, abi.encode(proxy.implementation, address(deployer), CALLDATA_LOGIC_A))
            ),
            "proxySaltReversed"
        );

        logicB.owner().eq(address(0));
        logicB.valueUint().eq(0);

        proxyLogicB.owner().eq(newOwner);
        proxyLogicB.valueUint().eq(newValue);

        upgraded.implementation.notEq(proxy.implementation);
        upgraded.implementation.eq(expectedImplementation);
        upgraded.version.eq(2);
        upgraded.createdAt.eq(proxy.createdAt);
        upgraded.updatedAt.notEq(proxy.updatedAt);
        upgraded.index.eq(0);
        upgraded.salt.eq(salt);
        assertTrue(proxy.proxy == upgraded.proxy);

        // Bookeeping
        deployer.isProxy(address(logicB)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicB));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testCreate3UpgradeAndCall() public prankedById(0) {
        Deployment memory proxy = deployer.create3ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt);

        (address expectedImplementation, uint256 version) = deployer.previewCreate3Upgrade(proxy.proxy);
        proxy.implementation.notEq(expectedImplementation);

        vm.warp(100);
        Deployment memory upgraded = deployer.create3UpgradeAndCall(proxy.proxy, LOGIC_B_CREATION_CODE, CALLDATA_LOGIC_B);

        LogicB logicB = LogicB(expectedImplementation);
        LogicB proxyLogicB = LogicB(address(proxy.proxy));

        address proxyAddr = address(upgraded.proxy);

        logicB.owner().eq(address(0));
        logicB.valueUint().eq(0);

        proxyLogicB.owner().eq(getAddr(1));
        proxyLogicB.valueUint().eq(100);

        upgraded.implementation.notEq(proxy.implementation);
        upgraded.implementation.eq(deployer.getCreate3Address(salt.add(version)));
        upgraded.version.eq(2);
        upgraded.createdAt.eq(proxy.createdAt);
        upgraded.updatedAt.notEq(proxy.updatedAt);
        upgraded.index.eq(0);
        upgraded.salt.eq(salt);
        assertTrue(proxy.proxy == upgraded.proxy);

        // Bookeeping
        deployer.isProxy(address(logicB)).eq(false);
        deployer.isProxy(proxyAddr).eq(true);
        deployer.getImplementation(proxyAddr).eq(address(logicB));
        deployer.getDeployCount().eq(1);
        deployer.getDeployments().length.eq(1);
        assertTrue(deployer.getDeployments()[0].proxy == proxy.proxy);
    }

    function testBatching() public prankedById(0) {
        bytes[] memory initCalls = new bytes[](3);
        initCalls[0] = abi.encodeCall(deployer.createProxy, (address(new LogicA()), CALLDATA_LOGIC_A));
        initCalls[1] = abi.encodeCall(deployer.create2ProxyAndLogic, (LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt));
        initCalls[2] = abi.encodeCall(deployer.create3ProxyAndLogic, (LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt));
        Deployment[] memory proxies = deployer.batch(initCalls).map(Convert.toDeployment);

        for (uint256 i; i < proxies.length; i++) {
            Deployment memory proxy = proxies[i];
            address proxyAddr = address(proxy.proxy);

            LogicA logicA = LogicA(proxy.implementation);
            LogicA proxyLogicA = LogicA(proxyAddr);

            proxyAddr.notEq(address(0));
            proxy.implementation.notEq(address(0));

            logicA.owner().eq(address(0));
            logicA.valueUint().eq(0);

            proxyLogicA.valueUint().eq(42);
            proxy.index.eq(i);
            assertTrue(deployer.getDeployments()[i].proxy == proxy.proxy);
        }
        deployer.getDeployCount().eq(initCalls.length);

        address newOwner = getAddr(1);
        uint256 newValue = 101;

        bytes[] memory upgradeCalls = new bytes[](initCalls.length);
        bytes memory upgradeCalldata = abi.encodeWithSelector(LogicB.initialize.selector, newOwner, newValue);
        bytes memory upgradeCalldata3 = abi.encodeWithSelector(LogicB.initialize.selector, getAddr(2), 5000);

        upgradeCalls[0] = abi.encodeCall(deployer.upgradeAndCallReturn, (proxies[0].proxy, address(new LogicB()), upgradeCalldata));
        upgradeCalls[1] = abi.encodeCall(deployer.create2UpgradeAndCall, (proxies[1].proxy, LOGIC_B_CREATION_CODE, upgradeCalldata));
        upgradeCalls[2] = abi.encodeCall(deployer.create3UpgradeAndCall, (proxies[2].proxy, LOGIC_B_CREATION_CODE, upgradeCalldata3));

        vm.warp(100);
        Deployment[] memory upgradedProxies = deployer.batch(upgradeCalls).map(Convert.toDeployment);

        for (uint256 i; i < upgradedProxies.length; i++) {
            Deployment memory proxy = upgradedProxies[i];
            address proxyAddr = address(proxy.proxy);

            LogicB logicB = LogicB(proxy.implementation);
            LogicB proxyLogicB = LogicB(proxyAddr);

            proxyAddr.eq(address(proxies[i].proxy));
            proxy.implementation.notEq(proxies[i].implementation);

            logicB.owner().eq(address(0));
            logicB.valueUint().eq(0);

            if (i == 2) {
                proxyLogicB.owner().eq(getAddr(2));
                proxyLogicB.valueUint().eq(5000);
            } else {
                proxyLogicB.valueUint().eq(newValue);
                proxyLogicB.owner().eq(newOwner);
            }

            proxy.index.eq(i);
            proxy.createdAt.eq(proxies[i].createdAt);
            proxy.updatedAt.gt(proxies[i].updatedAt);
            assertTrue(deployer.getDeployments()[i].proxy == proxy.proxy);
        }
        deployer.getDeployCount().eq(initCalls.length);

        address newLogicA = address(new LogicA());
        vm.expectRevert();
        deployer.batch(abi.encodeCall(deployer.createProxy, (newLogicA, CALLDATA_LOGIC_B)).toArray());
    }

    function testDeployerPermission() public {
        address owner = getAddr(0);
        address whitelisted = getAddr(1);
        bytes memory notOwner = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (whitelisted));

        // cant unauthorized
        vm.prank(whitelisted);
        vm.expectRevert(notOwner);
        deployer.setDeployer(whitelisted, true);

        bytes[] memory deployCalls = new bytes[](3);
        deployCalls[0] = abi.encodeCall(deployer.createProxy, (address(new LogicA()), CALLDATA_LOGIC_A));
        deployCalls[1] = abi.encodeCall(deployer.create2ProxyAndLogic, (LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt));
        deployCalls[2] = abi.encodeCall(deployer.create3ProxyAndLogic, (LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, salt));

        // cant deploy yet
        vm.prank(whitelisted);
        vm.expectRevert(notOwner);
        deployer.batch(deployCalls);

        // whitelist
        vm.prank(owner);
        deployer.setDeployer(whitelisted, true);

        // run deploys
        vm.prank(whitelisted);
        Deployment[] memory proxies = deployer.batch(deployCalls).map(Convert.toDeployment);
        proxies.length.eq(deployCalls.length);

        // cannot upgrade
        vm.startPrank(whitelisted);
        address upgradedLogic = address(new LogicB());
        vm.expectRevert(notOwner);
        deployer.upgradeAndCall(proxies[0].proxy, upgradedLogic, CALLDATA_LOGIC_B);
        vm.expectRevert(notOwner);
        deployer.create2UpgradeAndCall(proxies[1].proxy, LOGIC_B_CREATION_CODE, CALLDATA_LOGIC_B);
        vm.expectRevert(notOwner);
        deployer.create3UpgradeAndCall(proxies[2].proxy, LOGIC_B_CREATION_CODE, CALLDATA_LOGIC_B);

        bytes[] memory mixedCalls = new bytes[](2);
        address newLogicA = address(new LogicA());
        mixedCalls[0] = abi.encodeCall(deployer.createProxy, (newLogicA, CALLDATA_LOGIC_A));
        mixedCalls[1] = abi.encodeCall(deployer.create2UpgradeAndCall, (proxies[1].proxy, LOGIC_B_CREATION_CODE, CALLDATA_LOGIC_B));

        vm.expectRevert(notOwner);
        deployer.batch(mixedCalls);
        vm.stopPrank();

        vm.prank(owner);
        deployer.setDeployer(whitelisted, false);

        vm.prank(whitelisted);
        vm.expectRevert(notOwner);
        deployer.createProxy(newLogicA, CALLDATA_LOGIC_A);

        (address implementationAddr, uint256 version) = deployer.previewCreate2Upgrade(proxies[1].proxy, LOGIC_B_CREATION_CODE);
        version.notEq(0);
        implementationAddr.notEq(address(0));

        vm.startPrank(owner);
        Deployment[] memory upgraded = deployer.batch(mixedCalls).map(Convert.toDeployment);
        upgraded.length.eq(mixedCalls.length);
        upgraded[0].implementation.eq(newLogicA);
        upgraded[0].version.eq(1);
        upgraded[0].index.eq(3);

        address(upgraded[1].proxy).eq(address(proxies[1].proxy));
        upgraded[1].implementation.eq(implementationAddr);
        upgraded[1].implementation.notEq(proxies[1].implementation);
        upgraded[1].version.notEq(proxies[1].version);
        upgraded[1].version.eq(version);
        upgraded[1].index.eq(1);
        vm.stopPrank();
    }

    function testStaticBatch() public {
        address logic = address(new LogicA());

        address owner = getAddr(0);
        address expectedAddr = deployer.getCreate3Address(salt);

        bytes memory createProxy = abi.encodeCall(deployer.create3Proxy, (logic, CALLDATA_LOGIC_A, salt));
        bytes memory getOwner = abi.encodeCall(deployer.owner, ());
        bytes memory create3Preview = abi.encodeCall(deployer.getCreate3Address, (salt));

        vm.prank(getAddr(0));
        deployer.createProxy(logic, CALLDATA_LOGIC_A);

        bytes[] memory validCalls = new bytes[](3);
        validCalls[0] = getOwner;
        validCalls[1] = create3Preview;
        validCalls[2] = getOwner;

        address[] memory results = deployer.batchStatic(validCalls).map(Convert.toAddr);

        results[0].eq(owner);
        results[1].eq(expectedAddr);
        results[2].eq(owner);

        bytes[] memory invalidCalls = new bytes[](3);
        validCalls[0] = getOwner;
        validCalls[1] = create3Preview;
        validCalls[2] = createProxy;

        vm.prank(owner);
        vm.expectRevert();
        deployer.batchStatic(invalidCalls);
    }

    function testAccessControl() public {
        vm.startPrank(getAddr(0));
        address logicA = address(new LogicA());
        address logicB = address(new LogicB());

        Deployment memory proxy1 = deployer.createProxy(logicA, CALLDATA_LOGIC_A);
        Deployment memory proxy2 = deployer.create2Proxy(logicA, CALLDATA_LOGIC_A, salt2);
        Deployment memory proxy3 = deployer.create3Proxy(logicA, CALLDATA_LOGIC_A, salt2);
        vm.stopPrank();

        address invalid = getAddr(2);
        bytes memory notOwner = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, (invalid));

        vm.startPrank(invalid);

        vm.expectRevert(notOwner);
        deployer.createProxy(logicA, CALLDATA_LOGIC_A);
        vm.expectRevert(notOwner);
        deployer.create2Proxy(logicA, CALLDATA_LOGIC_A, salt);
        vm.expectRevert(notOwner);
        deployer.create3Proxy(logicA, CALLDATA_LOGIC_A, salt);

        vm.expectRevert(notOwner);
        deployer.createProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A);
        vm.expectRevert(notOwner);
        deployer.create2ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, bytes32("salty"));
        vm.expectRevert(notOwner);
        deployer.create3ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, bytes32("saltier"));

        vm.expectRevert(notOwner);
        deployer.upgradeAndCall(proxy1.proxy, logicB, CALLDATA_LOGIC_B);
        vm.expectRevert(notOwner);
        deployer.upgradeAndCallReturn(proxy1.proxy, logicB, CALLDATA_LOGIC_B);
        vm.expectRevert(notOwner);
        deployer.create2UpgradeAndCall(proxy2.proxy, LOGIC_B_CREATION_CODE, CALLDATA_LOGIC_B);
        vm.expectRevert(notOwner);
        deployer.create3UpgradeAndCall(proxy3.proxy, LOGIC_B_CREATION_CODE, CALLDATA_LOGIC_B);

        vm.stopPrank();
        vm.startPrank(getAddr(0));

        deployer.createProxy(logicA, CALLDATA_LOGIC_A);
        deployer.create2Proxy(logicA, CALLDATA_LOGIC_A, salt);
        deployer.create3Proxy(logicA, CALLDATA_LOGIC_A, salt);

        deployer.createProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A);
        deployer.create2ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, bytes32("salty"));
        deployer.create3ProxyAndLogic(LOGIC_A_CREATION_CODE, CALLDATA_LOGIC_A, bytes32("saltier"));

        deployer.upgradeAndCall(proxy1.proxy, logicB, CALLDATA_LOGIC_B);
        deployer.upgradeAndCallReturn(proxy1.proxy, logicB, CALLDATA_LOGIC_B);
        deployer.create2UpgradeAndCall(proxy2.proxy, LOGIC_B_CREATION_CODE, CALLDATA_LOGIC_B);
        deployer.create3UpgradeAndCall(proxy3.proxy, LOGIC_B_CREATION_CODE, CALLDATA_LOGIC_B);

        vm.stopPrank();
    }

    function testDeployKopioAndShare() public prankedById(0) {
        address protocol = 0x7366d18831e535f3Ab0b804C01d454DaD72B4c36;
        address feeRecipient = 0xC4489F3A82079C5a7b0b610Fc85952B6E585E697;
        address admin = 0xFcbB93547B7C1936fEbfe56b4cEeD9Ab66dA1857;

        bytes memory kopioImpl = type(Kopio).creationCode;
        bytes memory kopioInitializer = abi.encodeCall(Kopio.initialize, ("Ether", "kETH", admin, protocol, address(0), feeRecipient, 0, 0));

        bytes32 kopioSalt = 0x6b72455448616b72455448000000000000000000000000000000000000000000;
        bytes32 shareSalt = 0x616b724554486b72455448000000000000000000000000000000000000000000;

        (address predictedAddress, address predictedImpl) = deployer.previewCreate2ProxyAndLogic(kopioImpl, kopioInitializer, kopioSalt);

        bytes memory shareImpl = abi.encodePacked(type(KopioShare).creationCode, abi.encode(predictedAddress));
        bytes memory shareInitializer = abi.encodeWithSelector(KopioShare.initialize.selector, "Kopio Ether Share", "ksETH", admin);

        (address predictedShareAddress, address predictedShareImpl) = deployer.previewCreate2ProxyAndLogic(shareImpl, shareInitializer, shareSalt);

        bytes[] memory assets = new bytes[](2);
        assets[0] = abi.encodeCall(deployer.create2ProxyAndLogic, (kopioImpl, kopioInitializer, kopioSalt));
        assets[1] = abi.encodeCall(deployer.create2ProxyAndLogic, (shareImpl, shareInitializer, shareSalt));

        Deployment[] memory proxies = deployer.batch(assets).map(Convert.toDeployment);
        Deployment memory kopio = proxies[0];
        Deployment memory share = proxies[1];

        address(kopio.proxy).eq(predictedAddress);
        address(share.proxy).eq(predictedShareAddress);
        kopio.implementation.eq(predictedImpl);
        share.implementation.eq(predictedShareImpl);
    }

    function _toArray(bytes memory call) internal pure returns (bytes[] memory calls) {
        calls = new bytes[](1);
        calls[0] = call;
    }
}
